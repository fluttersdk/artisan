import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../helpers/config_editor.dart';
import '../helpers/env_editor.dart';
import '../helpers/gradle_editor.dart';
import '../helpers/html_editor.dart';
import '../helpers/json_editor.dart';
import '../helpers/main_dart_editor.dart';
import '../helpers/platform_helper.dart';
import '../helpers/plist_writer.dart';
import '../helpers/podfile_editor.dart';
import '../helpers/route_registry_editor.dart';
import '../helpers/xml_editor.dart';
import 'conflict_detector.dart';
import 'dry_run_renderer.dart';
import 'install_context.dart';
import 'install_operation.dart';

/// Orchestrator that stages a list of [InstallOperation]s and either applies
/// them atomically to disk, renders a dry-run preview, or refuses to write
/// when [ConflictDetector] flags a target file the user has modified
/// out-of-band.
///
/// Commit semantics are all-or-nothing:
///
/// 1. Every file write lands on `<absPath>.tmp` first via [InstallContext.fs].
/// 2. Only after every `.tmp` write succeeds do the renames + deletes apply.
/// 3. If any `.tmp` write throws, every staged `.tmp` is removed and the
///    method returns an [Error] with `rolledBack: true`.
///
/// One-shot: each [InstallTransaction] instance commits exactly once. A
/// second [commit] throws [StateError] so callers cannot replay operations
/// against stale state.
///
/// ## Usage
///
/// ```dart
/// final tx = InstallTransaction(ctx, pluginName: 'firebase_messaging');
/// tx.stage(const WriteFile(targetPath: 'lib/config/firebase.dart', content: '...'));
/// tx.stage(const InjectImport(targetFile: 'lib/main.dart', importStatement: "..."));
///
/// final result = await tx.commit();
/// switch (result) {
///   case Success(:final opCount, :final recordPath):
///     ctx.artisanContext.output.success('Installed $opCount ops; record: $recordPath');
///   case DryRun(:final opCount):
///     ctx.artisanContext.output.info('Previewed $opCount ops; nothing written');
///   case Conflict(:final conflicts):
///     ctx.artisanContext.output.warning('${conflicts.length} conflicts; pass --force to override');
///   case Error(:final error, :final rolledBack):
///     ctx.artisanContext.output.error('Failed: $error (rolled back: $rolledBack)');
/// }
/// ```
class InstallTransaction {
  /// Creates a transaction bound to [ctx] for the plugin identified by
  /// [pluginName]. The plugin name threads into the
  /// `.artisan/installed/<pluginName>.json` record path written on success.
  ///
  /// @param ctx         The active [InstallContext] (fs / clock / output).
  /// @param pluginName  Identifier used for the install record filename.
  InstallTransaction(InstallContext ctx, {required String pluginName})
      : _ctx = ctx,
        _pluginName = pluginName;

  final InstallContext _ctx;
  final String _pluginName;
  final List<InstallOperation> _ops = <InstallOperation>[];

  /// Conflict list injected by tests via [debugSetConflictsForTest]. Until
  /// Step 7's `ConflictDetector` lands, the production code path treats this
  /// as the authoritative pre-flight conflict source.
  List<FileConflict> _conflictsOverride = const <FileConflict>[];

  /// One-shot guard. Flipped to `true` after the first [commit] returns so a
  /// second call throws [StateError] instead of replaying ops against stale
  /// state.
  bool _committed = false;

  /// Number of operations staged but not yet committed.
  ///
  /// @return The length of the internal pending-op list.
  int get pendingCount => _ops.length;

  /// Read-only view of the staged operations in insertion order. Mutating
  /// the returned list throws [UnsupportedError].
  ///
  /// @return An unmodifiable [List] of the pending [InstallOperation]s.
  List<InstallOperation> get pendingOps =>
      List<InstallOperation>.unmodifiable(_ops);

  /// Appends [op] to the staged operation queue.
  ///
  /// Staging is pure: nothing is written to disk until [commit] runs. Ops
  /// execute in stage order.
  ///
  /// @param op  The [InstallOperation] to enqueue.
  void stage(InstallOperation op) {
    _ops.add(op);
  }

  /// Test-only seam (will be removed once Step 7's `ConflictDetector` is
  /// wired): pre-populates the conflict list returned by [_detectConflicts].
  ///
  /// @param conflicts  The synthetic conflict set to surface during the next
  ///                   non-dry-run [commit].
  @visibleForTesting
  void debugSetConflictsForTest(List<FileConflict> conflicts) {
    _conflictsOverride = List<FileConflict>.unmodifiable(conflicts);
  }

  /// Executes the staged operations.
  ///
  /// @param dryRun  When `true`, prints the staged ops and returns [DryRun]
  ///                without touching disk.
  /// @param force   When `true`, bypasses the conflict pre-flight so the
  ///                transaction commits over user-modified files.
  /// @return A [TransactionResult] describing the outcome.
  /// @throws StateError  When invoked more than once on the same instance.
  Future<TransactionResult> commit({
    bool dryRun = false,
    bool force = false,
  }) async {
    if (_committed) {
      throw StateError(
        'InstallTransaction.commit() called twice on the same instance; '
        'transactions are one-shot.',
      );
    }
    _committed = true;

    // 1. Dry-run short-circuit: print the preview, return without touching disk.
    if (dryRun) {
      _renderDryRun();
      return DryRun(opCount: _ops.length);
    }

    // 2. Conflict pre-flight. Until Step 7 wires the real ConflictDetector,
    //    `_detectConflicts` returns the test-seeded list (or an empty list in
    //    production). The `force` flag bypasses this gate.
    final conflicts = _detectConflicts();
    if (conflicts.isNotEmpty && !force) {
      return Conflict(conflicts: conflicts);
    }

    // 3. Stage every op into an in-memory write plan. A `null` value marks a
    //    delete; a non-null value carries the final UTF-8 content to write.
    //    Unknown / not-yet-implemented op types short-circuit the whole commit
    //    with an [Error] (no disk side effects yet, so rolledBack is false).
    final stagedWrites = <String, String?>{};
    for (final op in _ops) {
      final stageError = _stageOp(op, stagedWrites);
      if (stageError != null) {
        return stageError;
      }
    }

    // 4. Atomic disk flush. Write every non-null entry to `<absPath>.tmp`
    //    first. If any single write throws, loop the successful temps and
    //    delete them all before returning an [Error] with rolledBack=true.
    final committedTemps = <String>[];
    try {
      for (final entry in stagedWrites.entries) {
        final content = entry.value;
        if (content == null) continue;
        final tmpPath = '${entry.key}.tmp';
        _ctx.fs.writeAsString(tmpPath, content);
        committedTemps.add(tmpPath);
      }
    } catch (e) {
      for (final tmp in committedTemps) {
        _ctx.fs.delete(tmp);
      }
      return Error(error: e.toString(), rolledBack: true);
    }

    // 5. All `.tmp` writes succeeded. Rename each one over its target, and
    //    apply pending deletes. Rename + delete failures here are not rolled
    //    back: the .tmp swap is the atomic boundary on POSIX. Any partial
    //    failure past this point is surfaced as an [Error] with rolledBack
    //    false so the operator can inspect manually.
    try {
      for (final entry in stagedWrites.entries) {
        final absPath = entry.key;
        if (entry.value == null) {
          _ctx.fs.delete(absPath);
        } else {
          _ctx.fs.rename('$absPath.tmp', absPath);
        }
      }
    } catch (e) {
      return Error(error: e.toString(), rolledBack: false);
    }

    // 6. Run deferred shell ops (RunShell). These execute AFTER every file
    //    mutation has landed so a hook like `flutter pub get` observes the
    //    final on-disk state. A non-zero exit aborts the transaction and
    //    leaves the record file unwritten; the operator can re-run the
    //    install once the shell precondition is fixed.
    final shellError = _runShellOps();
    if (shellError != null) {
      return shellError;
    }

    // 7. Persist the install record so `plugin:uninstall` can replay-reverse.
    final recordPath = p.join(
      _ctx.projectRoot,
      '.artisan',
      'installed',
      '$_pluginName.json',
    );
    final record = _buildRecord(stagedWrites);
    _ctx.fs.writeAsString(recordPath, _encodeJson(record));

    return Success(opCount: _ops.length, recordPath: recordPath);
  }

  /// Resolves [relPath] against [InstallContext.projectRoot]. Absolute paths
  /// pass through unchanged.
  String _abs(String relPath) {
    if (p.isAbsolute(relPath)) return relPath;
    return p.join(_ctx.projectRoot, relPath);
  }

  /// Runs conflict pre-flight via [ConflictDetector].
  ///
  /// When [_conflictsOverride] has been populated via the
  /// [debugSetConflictsForTest] seam, that list is returned directly so tests
  /// that pre-date the real detector can still exercise the conflict branch
  /// without setting up filesystem state. In production the seam list is
  /// always empty and the real detector runs.
  ///
  /// @return The list of [FileConflict]s for this transaction's ops.
  List<FileConflict> _detectConflicts() {
    if (_conflictsOverride.isNotEmpty) return _conflictsOverride;
    return ConflictDetector(_ctx).detect(_ops, pluginName: _pluginName);
  }

  /// Computes the staged write/delete entry for a single [op].
  ///
  /// Three classes of behaviour live here:
  ///
  /// 1. Pure file ops ([WriteFile] / [DeleteFile] / [CopyFile] / [PublishFile])
  ///    populate [stagedWrites] and ride the atomic `.tmp` swap in
  ///    [commit]'s phase 4.
  /// 2. Helper-backed ops ([AddDependency] / [AddPubspecAsset] / [MergeJson] /
  ///    every `Inject*`) call legacy helpers (`ConfigEditor`, `JsonEditor`,
  ///    `MainDartEditor`, `XmlEditor`, `PlistWriter`, `PodfileEditor`,
  ///    `GradleEditor`, `HtmlEditor`, `EnvEditor`) which write through
  ///    `dart:io` directly. These commits land synchronously during stage and
  ///    are NOT covered by the `.tmp` rollback. See `PluginInstaller`'s
  ///    "Limitations" docblock for the V1 trade-off.
  /// 3. [RunShell] is deferred until phase 5 (`_runShellOps`) so commands
  ///    only fire after every file mutation succeeded.
  TransactionResult? _stageOp(
    InstallOperation op,
    Map<String, String?> stagedWrites,
  ) {
    try {
      switch (op) {
        case WriteFile():
          stagedWrites[_abs(op.targetPath)] = op.content;
          return null;
        case DeleteFile():
          stagedWrites[_abs(op.targetPath)] = null;
          return null;
        case CopyFile():
          // Read source content NOW (stage time) so the atomic write phase only
          // depends on the in-memory plan, never on disk state the user could
          // change between stage and commit.
          final sourceAbs = _abs(op.sourcePath);
          final content = _ctx.fs.readAsString(sourceAbs);
          stagedWrites[_abs(op.targetPath)] = content;
          return null;
        case PublishFile():
          // Load + substitute now, ride the atomic .tmp swap during commit
          // phase 4 alongside WriteFile/DeleteFile/CopyFile.
          final stub = _ctx.stubs.load(op.sourceStubName);
          final rendered = _ctx.stubs.replace(stub, op.replacements);
          stagedWrites[_abs(op.targetPath)] = rendered;
          return null;

        // ---------- Pubspec ----------
        case AddDependency():
          final pubspec = _pubspecPath();
          if (op.isDev) {
            ConfigEditor.addDevDependencyToPubspec(
              pubspecPath: pubspec,
              name: op.name,
              version: op.version,
            );
          } else {
            ConfigEditor.addDependencyToPubspec(
              pubspecPath: pubspec,
              name: op.name,
              version: op.version,
            );
          }
          return null;
        case AddPathDependency():
          ConfigEditor.addPathDependencyToPubspec(
            pubspecPath: _pubspecPath(),
            name: op.name,
            path: op.path,
          );
          return null;
        case RemoveDependency():
          ConfigEditor.removeDependencyFromPubspec(
            pubspecPath: _pubspecPath(),
            name: op.name,
          );
          return null;
        case AddPubspecAsset():
          // CRITICAL: use appendPubspecListEntry, NOT updatePubspecValue —
          // the latter clobbers the entire `flutter.assets` list.
          ConfigEditor.appendPubspecListEntry(
            pubspecPath: _pubspecPath(),
            keyPath: const <String>['flutter', 'assets'],
            value: op.assetPath,
          );
          return null;

        // ---------- JSON ----------
        case MergeJson():
          JsonEditor.mergeJsonData(
            _abs(op.targetPath),
            op.sourceData,
            additive: op.additive,
          );
          return null;

        // ---------- Generic Dart injection ----------
        case InjectImport():
          ConfigEditor.addImportToFile(
            filePath: _abs(op.targetFile),
            importStatement: op.importStatement,
          );
          return null;
        case InjectBeforePattern():
          ConfigEditor.insertCodeBeforePattern(
            filePath: _abs(op.targetFile),
            pattern: op.pattern,
            code: op.code,
          );
          return null;
        case InjectAfterPattern():
          ConfigEditor.insertCodeAfterPattern(
            filePath: _abs(op.targetFile),
            pattern: op.pattern,
            code: op.code,
          );
          return null;

        // ---------- main.dart ----------
        case InjectMainDartImport():
          MainDartEditor.addImport(_mainDartPath(), op.importStatement);
          return null;
        case InjectIntoMainDart():
          switch (op.placement) {
            case MainDartPlacement.beforeInit:
              MainDartEditor.injectBeforeMagicInit(_mainDartPath(), op.code);
            case MainDartPlacement.afterInit:
              MainDartEditor.injectAfterMagicInit(_mainDartPath(), op.code);
            case MainDartPlacement.wrapRunApp:
              MainDartEditor.wrapRunApp(_mainDartPath(), op.code);
          }
          return null;

        // ---------- Route registry ----------
        case InjectRouteRegistration():
          RouteRegistryEditor.addRouteRegistration(
            _routeProviderPath(),
            op.functionName,
          );
          return null;

        // ---------- Android native ----------
        case InjectAndroidPermission():
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, 'android')) {
            _logSkip('InjectAndroidPermission', 'android');
            return null;
          }
          XmlEditor.addAndroidPermission(
            PlatformHelper.androidManifestPath(_ctx.projectRoot),
            op.permission,
          );
          return null;
        case InjectAndroidMetaData():
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, 'android')) {
            _logSkip('InjectAndroidMetaData', 'android');
            return null;
          }
          XmlEditor.addAndroidMetaData(
            PlatformHelper.androidManifestPath(_ctx.projectRoot),
            name: op.name,
            value: op.value,
          );
          return null;
        case InjectGradlePlugin():
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, 'android')) {
            _logSkip('InjectGradlePlugin', 'android');
            return null;
          }
          GradleEditor.addPlugin(
            _appBuildGradlePath(),
            op.pluginId,
            version: op.version,
          );
          return null;
        case InjectGradleDependency():
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, 'android')) {
            _logSkip('InjectGradleDependency', 'android');
            return null;
          }
          GradleEditor.addDependency(
            _appBuildGradlePath(),
            op.scope,
            op.notation,
          );
          return null;

        // ---------- iOS / macOS native ----------
        case InjectInfoPlistKey():
          final platform = op.platform;
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, platform)) {
            _logSkip('InjectInfoPlistKey', platform);
            return null;
          }
          final plistPath = _infoPlistPathFor(platform);
          final value = op.value;
          if (value is String) {
            PlistWriter.setStringKey(plistPath, op.key, value);
            return null;
          }
          if (value is bool) {
            PlistWriter.setBoolKey(plistPath, op.key, value);
            return null;
          }
          if (value is List<String>) {
            PlistWriter.setArrayKey(plistPath, op.key, value);
            return null;
          }
          return Error(
            error:
                'InjectInfoPlistKey: unsupported value type ${value.runtimeType} '
                'for key ${op.key} (expected String, bool, or List<String>).',
            rolledBack: false,
          );
        case InjectEntitlement():
          final platform = op.platform;
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, platform)) {
            _logSkip('InjectEntitlement', platform);
            return null;
          }
          final entitlementsPath = _entitlementsPathFor(platform);
          final value = op.value;
          if (value is bool) {
            PlistWriter.setBoolKey(entitlementsPath, op.key, value);
            return null;
          }
          if (value is String) {
            PlistWriter.setStringKey(entitlementsPath, op.key, value);
            return null;
          }
          return Error(
            error:
                'InjectEntitlement: unsupported value type ${value.runtimeType} '
                'for key ${op.key} (expected String or bool).',
            rolledBack: false,
          );
        case InjectPodfileLine():
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, op.platform)) {
            _logSkip('InjectPodfileLine', op.platform);
            return null;
          }
          PodfileEditor.addPodLine(
            _podfilePathFor(op.platform),
            'Runner',
            op.line,
          );
          return null;

        // ---------- Web ----------
        case InjectIntoWebHead():
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, 'web')) {
            _logSkip('InjectIntoWebHead', 'web');
            return null;
          }
          HtmlEditor.injectBeforeClose(
            PlatformHelper.webIndexPath(_ctx.projectRoot),
            '</head>',
            op.content,
          );
          return null;
        case AddWebMetaTag():
          if (!PlatformHelper.hasPlatform(_ctx.projectRoot, 'web')) {
            _logSkip('AddWebMetaTag', 'web');
            return null;
          }
          HtmlEditor.addMetaTag(
            PlatformHelper.webIndexPath(_ctx.projectRoot),
            op.attributes,
          );
          return null;

        // ---------- Env ----------
        case InjectEnvVar():
          EnvEditor.setKey(
            _envPath(),
            op.key,
            op.value,
          );
          return null;

        // ---------- Shell (deferred to phase 5) ----------
        case RunShell():
          // Deferred: do not write or run anything here; phase 5 of `commit`
          // iterates the op list a second time after all file writes settle.
          return null;
      }
    } catch (e) {
      // Helper-backed ops can throw (missing files, malformed YAML, missing
      // anchors). Surface as a stage-time Error so the transaction halts
      // before the .tmp swap touches anything.
      return Error(
        error: '${op.runtimeType} dispatch failed: $e',
        rolledBack: false,
      );
    }
  }

  /// Resolves `<projectRoot>/pubspec.yaml`.
  String _pubspecPath() => p.join(_ctx.projectRoot, 'pubspec.yaml');

  /// Resolves `<projectRoot>/lib/main.dart`.
  String _mainDartPath() => p.join(_ctx.projectRoot, 'lib', 'main.dart');

  /// Resolves `<projectRoot>/lib/app/providers/route_service_provider.dart`.
  String _routeProviderPath() => p.join(
        _ctx.projectRoot,
        'lib',
        'app',
        'providers',
        'route_service_provider.dart',
      );

  /// Resolves `<projectRoot>/.env`.
  String _envPath() => p.join(_ctx.projectRoot, '.env');

  /// Resolves the Android app `build.gradle.kts` (preferred Kotlin DSL) or
  /// falls back to the Groovy `build.gradle` when the Kotlin variant is
  /// absent.
  String _appBuildGradlePath() {
    final kts = p.join(_ctx.projectRoot, 'android', 'app', 'build.gradle.kts');
    if (File(kts).existsSync()) return kts;
    return p.join(_ctx.projectRoot, 'android', 'app', 'build.gradle');
  }

  /// Resolves `<projectRoot>/<ios|macos>/Runner/Info.plist`. Mirrors
  /// [PlatformHelper.infoPlistPath] for iOS and applies the same layout for
  /// macOS so plugins can target either platform off the same op type.
  String _infoPlistPathFor(String platform) {
    return p.join(_ctx.projectRoot, platform, 'Runner', 'Info.plist');
  }

  /// Resolves `<projectRoot>/<ios|macos>/Runner/Runner.entitlements`.
  String _entitlementsPathFor(String platform) {
    return p.join(
      _ctx.projectRoot,
      platform,
      'Runner',
      'Runner.entitlements',
    );
  }

  /// Resolves `<projectRoot>/<ios|macos>/Podfile`.
  String _podfilePathFor(String platform) {
    return p.join(_ctx.projectRoot, platform, 'Podfile');
  }

  /// Emits an info-level skip line to the command output when an op targeted
  /// a platform directory that does not exist on the consumer project.
  void _logSkip(String opName, String platform) {
    _ctx.artisanContext.output.info(
        'Skipping $opName: no $platform/ directory at ${_ctx.projectRoot}.');
  }

  /// Iterates [_ops] and fires every [RunShell] via [Process.runSync]. Runs
  /// after every file mutation has landed so a shell hook (e.g.
  /// `flutter pub get`) observes the final on-disk state.
  ///
  /// Returns the first failure as a non-rolled-back [Error]; subsequent shell
  /// ops are skipped so the operator sees a single root cause.
  TransactionResult? _runShellOps() {
    for (final op in _ops) {
      if (op is! RunShell) continue;
      try {
        final result = Process.runSync(
          op.command,
          op.args,
          workingDirectory: op.workingDir ?? _ctx.projectRoot,
        );
        if (result.exitCode != 0) {
          return Error(
            error: 'RunShell failed (${op.command} ${op.args.join(' ')}, exit '
                '${result.exitCode}): ${result.stderr}',
            rolledBack: false,
          );
        }
      } catch (e) {
        return Error(
          error: 'RunShell threw for ${op.command}: $e',
          rolledBack: false,
        );
      }
    }
    return null;
  }

  /// Delegates dry-run rendering to [DryRunRenderer].
  ///
  /// Emits the structured preview to [InstallContext.artisanContext]'s output
  /// without touching the filesystem.
  void _renderDryRun() {
    DryRunRenderer.render(
      _ctx.artisanContext.output,
      _ops,
      pluginName: _pluginName,
    );
  }

  /// Builds the `.artisan/installed/<plugin>.json` record payload.
  Map<String, dynamic> _buildRecord(Map<String, String?> stagedWrites) {
    final stubHashes = <String, String>{};
    for (final entry in stagedWrites.entries) {
      if (entry.value == null) continue;
      // The file just landed via rename, so md5 reads the freshly-committed
      // content. Tracking the hash here (rather than at write time) makes
      // ConflictDetector's later compare a single read per file.
      stubHashes[entry.key] = _ctx.fs.md5(entry.key);
    }

    return <String, dynamic>{
      'plugin': _pluginName,
      'installedAt': _ctx.clock().toUtc().toIso8601String(),
      'ops': _ops.map(_serializeOp).toList(),
      'stubHashes': stubHashes,
    };
  }

  /// Serializes an [InstallOperation] into the JSON shape stored in the
  /// install record. Only the three dispatched op types are emitted with
  /// full payload data; everything else (currently unreachable since the
  /// dispatcher rejects them) falls back to a type-only marker.
  Map<String, dynamic> _serializeOp(InstallOperation op) {
    return switch (op) {
      WriteFile(:final targetPath, :final content) => <String, dynamic>{
          'type': 'WriteFile',
          'targetPath': targetPath,
          'content': content,
        },
      DeleteFile(:final targetPath) => <String, dynamic>{
          'type': 'DeleteFile',
          'targetPath': targetPath,
        },
      CopyFile(:final sourcePath, :final targetPath) => <String, dynamic>{
          'type': 'CopyFile',
          'sourcePath': sourcePath,
          'targetPath': targetPath,
        },
      _ => <String, dynamic>{'type': op.runtimeType.toString()},
    };
  }

  String _encodeJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }
}

/// Sealed outcome of [InstallTransaction.commit].
///
/// Four subclasses cover the full result space: [Success], [DryRun],
/// [Conflict], [Error]. Exhaustive `switch` dispatch is compiler-checked.
sealed class TransactionResult {
  /// Allows subclasses to declare `const` constructors.
  const TransactionResult();

  /// Returns a single-line human-readable summary of the result.
  String describe();
}

/// All staged operations applied; the install record was persisted.
final class Success extends TransactionResult {
  /// Number of operations applied.
  final int opCount;

  /// Absolute path of the persisted `.artisan/installed/<plugin>.json` record.
  final String recordPath;

  /// Creates a [Success] result.
  const Success({required this.opCount, required this.recordPath});

  @override
  String describe() => 'Success: applied $opCount ops; record at $recordPath';
}

/// Dry-run completed: ops were rendered but nothing was written.
final class DryRun extends TransactionResult {
  /// Number of operations that would have been applied.
  final int opCount;

  /// Creates a [DryRun] result.
  const DryRun({required this.opCount});

  @override
  String describe() => 'DryRun: previewed $opCount ops; no changes written';
}

/// Pre-flight conflict detector flagged one or more user-modified files and
/// the caller did not pass `force: true`.
final class Conflict extends TransactionResult {
  /// The conflict list returned by the detector.
  final List<FileConflict> conflicts;

  /// Creates a [Conflict] result.
  const Conflict({required this.conflicts});

  @override
  String describe() =>
      'Conflict: ${conflicts.length} file(s) modified out-of-band; '
      'pass --force to override';
}

/// A write failed, an unimplemented op was encountered, or a post-rename step
/// raised. [rolledBack] reflects whether the `.tmp` cleanup ran.
final class Error extends TransactionResult {
  /// Human-readable error description (typically the underlying exception
  /// message).
  final String error;

  /// `true` when the `.tmp` cleanup ran (failure happened during the atomic
  /// write phase); `false` when the failure was earlier (unimplemented op)
  /// or later (post-rename) so no rollback was needed or possible.
  final bool rolledBack;

  /// Creates an [Error] result.
  const Error({required this.error, required this.rolledBack});

  @override
  String describe() => 'Error: $error (rolled back: $rolledBack)';
}
