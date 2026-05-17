import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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

    // 6. Persist the install record so `plugin:uninstall` can replay-reverse.
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

  /// Computes the staged write/delete entry for a single [op]. Returns an
  /// [Error] result when [op] belongs to an op type whose dispatcher has not
  /// yet been implemented (Wave 3 extends this method per chain-method-batch).
  TransactionResult? _stageOp(
    InstallOperation op,
    Map<String, String?> stagedWrites,
  ) {
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
      // The remaining 23 op types land in Wave 3 (Steps 18 through 23). Until
      // then the dispatcher refuses them explicitly so misconfigured plugins
      // fail fast instead of silently dropping operations.
      case AddDependency():
      case AddPathDependency():
      case RemoveDependency():
      case AddPubspecAsset():
      case PublishFile():
      case MergeJson():
      case InjectImport():
      case InjectBeforePattern():
      case InjectAfterPattern():
      case InjectAndroidPermission():
      case InjectAndroidMetaData():
      case InjectInfoPlistKey():
      case InjectEntitlement():
      case InjectPodfileLine():
      case InjectGradlePlugin():
      case InjectGradleDependency():
      case InjectEnvVar():
      case InjectIntoWebHead():
      case AddWebMetaTag():
      case InjectMainDartImport():
      case InjectIntoMainDart():
      case InjectRouteRegistration():
      case RunShell():
        return Error(
          error: 'Dispatcher for ${op.runtimeType} not yet implemented.',
          rolledBack: false,
        );
    }
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
