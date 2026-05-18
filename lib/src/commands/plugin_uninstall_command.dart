import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../console/artisan_context.dart';
import '../helpers/file_helper.dart';
import '../installer/artisan_install_command.dart';
import '../installer/dry_run_renderer.dart';
import '../installer/install_context.dart';
import '../installer/install_exception.dart';
import '../installer/install_manifest.dart';
import '../installer/install_operation.dart';
import '../installer/install_transaction.dart';
import '../installer/manifest_installer.dart';
import '../installer/manifest_parser.dart';
import 'plugin_install_command.dart';

/// `plugin:uninstall <name>`, reverse a manifest-driven plugin install.
///
/// Mirror image of [PluginInstallCommand]:
///
///   1. Verifies an install record exists at
///      `<projectRoot>/.artisan/installed/<name>.json`. The record is what
///      [ManifestInstaller] writes on a successful install; without it
///      there is no plan to reverse.
///   2. Resolves and parses the plugin's `install.yaml` (still on disk
///      because the package itself is still a pubspec dep at uninstall
///      time).
///   3. Optionally prompts the operator to confirm a destructive op (unless
///      `--force` or `--non-interactive` is set).
///   4. On `--dry-run`, prints the planned reverse ops via [DryRunRenderer]
///      and exits without touching the filesystem.
///   5. Otherwise, delegates to [ManifestInstaller.uninstall] which derives
///      the reverse [InstallOperation]s from the record, commits a fresh
///      reverse transaction, and deletes the record on Success.
///   6. Finally, removes the plugin's `import` line + `registerProvider`
///      line from `bin/artisan.dart`, the inverse of the legacy injection
///      [PluginInstallCommand] performs when no manifest is found.
///
/// V1 limitation: only `WriteFile` / `DeleteFile` / `CopyFile` carry full
/// payload in the install record. Every other op type is recorded as a
/// type-only marker. [ManifestInstaller.uninstall] surfaces a warning for
/// those and skips. The Plugin Authoring Guide documents the trade-off.
class PluginUninstallCommand extends ArtisanInstallCommand {
  /// Public default constructor. Test fixtures subclass + override
  /// [getProjectRoot] / [resolveInstallYaml] / [promptConfirmation] to inject
  /// deterministic paths and answers.
  PluginUninstallCommand();

  @override
  String get signature => 'plugin:uninstall '
      '$baseFlags'
      '{name : Plugin pubspec package name}';

  @override
  String get description =>
      'Uninstall a third-party artisan plugin (reverses the manifest + '
      'removes the bin/artisan.dart registration).';

  @override
  String pluginName(ArtisanContext ctx) =>
      (ctx.input.argument('name') ?? '').toString();

  /// Resolves the consumer project root. Hook for test subclasses; production
  /// path defers to [FileHelper.findProjectRoot].
  ///
  /// @return Absolute path to the directory containing the consumer's
  ///         `pubspec.yaml`.
  @visibleForTesting
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Resolves the plugin's `install.yaml` location, or `null` when the
  /// plugin ships no manifest (uninstall cannot proceed in that case).
  ///
  /// Same lookup strategy as [PluginInstallCommand.resolveInstallYaml]:
  /// resolve `package:<pluginName>/cli.dart` via [Isolate.resolvePackageUri],
  /// walk two directories up to the plugin root, then check `install.yaml`
  /// followed by `assets/install.yaml`.
  ///
  /// @param pluginName  The plugin's pubspec package name.
  /// @return Absolute path to the install.yaml, or `null` when none found.
  @visibleForTesting
  Future<String?> resolveInstallYaml(String pluginName) async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:$pluginName/cli.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') return null;

    final libCli = resolved.toFilePath();
    final pluginRoot = p.dirname(p.dirname(libCli));

    final atRoot = p.join(pluginRoot, 'install.yaml');
    if (File(atRoot).existsSync()) return atRoot;

    final atAssets = p.join(pluginRoot, 'assets', 'install.yaml');
    if (File(atAssets).existsSync()) return atAssets;

    return null;
  }

  /// Interactive confirmation step. Returns the operator's `yes/no`
  /// decision. Hook for test subclasses; production path delegates to
  /// [InstallContext.prompt] (which wraps the static [Prompt.confirm]
  /// helper).
  ///
  /// @param ctx         The active [ArtisanContext].
  /// @param pluginName  The plugin scheduled for removal (rendered into the
  ///                    confirmation question).
  /// @return `true` when the operator confirms; `false` to abort.
  @visibleForTesting
  bool promptConfirmation(ArtisanContext ctx, String pluginName) {
    final installContext = buildContext(ctx);
    return installContext.prompt.confirm(
      'Uninstall plugin "$pluginName"? This will reverse every recorded '
      'install operation and remove the bin/artisan.dart registration.',
      defaultValue: false,
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Validate the positional name argument.
    final name = pluginName(ctx);
    if (name.isEmpty) {
      ctx.output.error('Missing required argument: name.');
      return 1;
    }

    // 2. Verify the install record exists. Without it the plugin was either
    //    never installed via the manifest path OR the record was deleted
    //    manually; either way the command cannot derive a reverse plan.
    final root = getProjectRoot();
    final recordPath = p.join(root, '.artisan', 'installed', '$name.json');
    if (!File(recordPath).existsSync()) {
      ctx.output.error(
        'Plugin "$name" is not installed via the manifest path '
        '(no install record at $recordPath). Nothing to uninstall.',
      );
      return 1;
    }

    // 3. Resolve + parse the manifest.
    final manifestPath = await resolveInstallYaml(name);
    if (manifestPath == null) {
      ctx.output.error(
        'No install.yaml found for plugin "$name". The manifest must be '
        'reachable so plugin:uninstall can replay the original install '
        'plan in reverse.',
      );
      return 1;
    }

    final InstallManifest manifest;
    try {
      manifest = ManifestParser.parseFile(manifestPath);
    } on FormatException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: $e');
      return 1;
    } on ManifestValidationException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: ${e.message}');
      return 1;
    }

    // 4. Build the install context once. Both the dry-run preview and the
    //    real uninstall share the same projectRoot + fs seam.
    final installContext = _buildScopedContext(ctx, projectRoot: root);

    // 5. Dry-run short-circuit: render the planned reverse ops and exit
    //    BEFORE the destructive confirm + commit. Op reconstruction mirrors
    //    ManifestInstaller.uninstall's internal flow so the preview matches
    //    what the real run would do.
    if (isDryRun(ctx)) {
      _renderDryRun(ctx, recordPath: recordPath, name: name);
      return 0;
    }

    // 6. Confirm prompt (skipped under --force / --non-interactive). The
    //    interactive path uses [promptConfirmation] which test subclasses
    //    override.
    if (!isForce(ctx) && !isNonInteractive(ctx)) {
      final ok = promptConfirmation(ctx, name);
      if (!ok) {
        ctx.output.info('Uninstall aborted by operator.');
        return 0;
      }
    }

    // 7. Delegate to ManifestInstaller. The reverse transaction deletes the
    //    record on Success (see ManifestInstaller.uninstall).
    final installer = ManifestInstaller(installContext, manifest);
    final result = await installer.uninstall(force: isForce(ctx));

    switch (result) {
      case Success():
        ctx.output.success(result.describe());
        // 8. Mirror the install-time bin/artisan.dart injection: strip the
        //    plugin's import + registerProvider lines so the next
        //    `dart run artisan list` no longer attempts to wire the plugin.
        _stripWrapperLines(
          installContext: installContext,
          pluginName: name,
          providerClassName: manifest.magic.provider,
        );
        return 0;
      case DryRun():
        // Unreachable in practice; ManifestInstaller.uninstall has no
        // dryRun parameter and the --dry-run branch returned above.
        ctx.output.info(result.describe());
        return 0;
      case Conflict():
        ctx.output.error(result.describe());
        return 2;
      case Error():
        ctx.output.error(result.describe());
        return 1;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Builds an [InstallContext] pinned to [projectRoot]. Pinning explicitly
  /// here keeps the test / production paths symmetrical (tests pin to a
  /// temp dir; production pins to [getProjectRoot]).
  InstallContext _buildScopedContext(
    ArtisanContext ctx, {
    required String projectRoot,
  }) {
    return InstallContext.real(ctx, projectRoot: projectRoot);
  }

  /// Reads the install record at [recordPath], reconstructs the recorded
  /// ops, derives the reverse ops via [ManifestInstaller.reverseOf], and
  /// prints them through [DryRunRenderer]. Skipped ops (those without a
  /// clean reverse in V1) are summarised in a trailing warning line.
  void _renderDryRun(
    ArtisanContext ctx, {
    required String recordPath,
    required String name,
  }) {
    // 1. Decode + reconstruct each op the install record carries. Type-only
    //    entries are skipped (V1 records only persist full payload for
    //    WriteFile / DeleteFile / CopyFile).
    final raw = File(recordPath).readAsStringSync();
    final Map<String, dynamic>? decoded = _decodeRecord(raw);
    if (decoded == null) {
      ctx.output.error('Install record at $recordPath is not a JSON object.');
      return;
    }
    final opsRaw = decoded['ops'];
    if (opsRaw is! List) {
      ctx.output.error('Install record at $recordPath has no "ops" array.');
      return;
    }

    final reverseOps = <InstallOperation>[];
    final skipped = <String>[];
    for (final entry in opsRaw) {
      if (entry is! Map) {
        skipped.add('non-map entry');
        continue;
      }
      final reconstructed = _opFromRecord(entry);
      if (reconstructed == null) {
        skipped.add('${entry['type']} (no payload in record)');
        continue;
      }
      final reverse = _reverseDecodedOp(reconstructed);
      if (reverse == null) {
        skipped.add('${reconstructed.runtimeType} (no reverse possible)');
        continue;
      }
      reverseOps.add(reverse);
    }

    // 2. Banner so the operator visually recognises the dry-run preview.
    ctx.output.info(
      'Dry run for plugin:uninstall $name; no changes will be written.',
    );

    // 3. Delegate to DryRunRenderer for the per-op detail.
    DryRunRenderer.render(ctx.output, reverseOps, pluginName: name);

    // 4. Surface skipped ops so the operator sees what would remain.
    if (skipped.isNotEmpty) {
      ctx.output.warning(
        'Would skip ${skipped.length} op(s) without a clean reverse: '
        '${skipped.join(', ')}.',
      );
    }
  }

  /// JSON-decodes the install record. Returns `null` when the payload is not
  /// a top-level map (the only shape ManifestInstaller emits).
  ///
  /// @param raw  The raw record file contents.
  /// @return The decoded top-level map, or `null` on shape mismatch / parse
  ///         failure.
  Map<String, dynamic>? _decodeRecord(String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Reconstructs a typed [InstallOperation] from a record entry. Returns
  /// `null` for type-only entries; same contract as
  /// `ManifestInstaller._opFromRecord` (kept local to avoid widening that
  /// method's visibility).
  ///
  /// @param entry  One element from the record's `ops` list.
  /// @return The typed [InstallOperation], or `null` for type-only entries.
  InstallOperation? _opFromRecord(Map entry) {
    final type = entry['type'];
    switch (type) {
      case 'WriteFile':
        final target = entry['targetPath'];
        final content = entry['content'];
        if (target is String && content is String) {
          return WriteFile(targetPath: target, content: content);
        }
        return null;
      case 'DeleteFile':
        final target = entry['targetPath'];
        if (target is String) {
          return DeleteFile(targetPath: target);
        }
        return null;
      case 'CopyFile':
        final source = entry['sourcePath'];
        final target = entry['targetPath'];
        if (source is String && target is String) {
          return CopyFile(sourcePath: source, targetPath: target);
        }
        return null;
      default:
        return null;
    }
  }

  /// Returns the reverse op for a record-reconstructed [InstallOperation],
  /// or `null` when no clean reverse exists.
  ///
  /// Only the three op types [_opFromRecord] can reconstruct reach this
  /// branch: `WriteFile`, `DeleteFile`, `CopyFile`. We deliberately do NOT
  /// call [ManifestInstaller.reverseOf] here because that helper is
  /// `@visibleForTesting`; mirroring the relevant slice keeps the
  /// production call graph clean.
  ///
  /// Mapping:
  ///   - `WriteFile`  → [DeleteFile] of the same target path.
  ///   - `CopyFile`   → [DeleteFile] of the destination path.
  ///   - `DeleteFile` → `null` (we never persisted the deleted bytes).
  ///
  /// @param op  A typed op reconstructed from the install record.
  /// @return The reverse op, or `null` when no clean reverse is available.
  InstallOperation? _reverseDecodedOp(InstallOperation op) {
    return switch (op) {
      WriteFile(:final targetPath) => DeleteFile(targetPath: targetPath),
      CopyFile(:final targetPath) => DeleteFile(targetPath: targetPath),
      DeleteFile() => null,
      _ => null,
    };
  }

  /// Strips the plugin's `import 'package:<name>/cli.dart';` and
  /// `registry.registerProvider(<Provider>());` lines from
  /// `<projectRoot>/bin/artisan.dart`. Inverse of the legacy injection
  /// [PluginInstallCommand] performs when no manifest is found.
  ///
  /// Goes through [InstallContext.fs] (rather than direct `dart:io`) so the
  /// op is testable against an [InMemoryFs] and consistent with the rest of
  /// the installer's filesystem seam.
  ///
  /// @param installContext     Active [InstallContext] (carries projectRoot
  ///                           + [VirtualFs] seam).
  /// @param pluginName         Pubspec package name (matched against the
  ///                           import line).
  /// @param providerClassName  Optional PascalCase provider class name. When
  ///                           supplied (manifest declared `magic.provider`)
  ///                           the matching register line is stripped too.
  void _stripWrapperLines({
    required InstallContext installContext,
    required String pluginName,
    String? providerClassName,
  }) {
    final wrapperPath =
        p.join(installContext.projectRoot, 'bin', 'artisan.dart');
    if (!installContext.fs.exists(wrapperPath)) return;

    var content = installContext.fs.readAsString(wrapperPath);

    // 1. Strip the import line (with optional surrounding newlines).
    final importLine = "import 'package:$pluginName/cli.dart';";
    content = content.replaceAll(
      RegExp('\\n?${RegExp.escape(importLine)}\\n?'),
      '\n',
    );

    // 2. Strip the register-provider line. Two candidate class names cover
    //    both manifest-declared providers and the legacy snake-to-pascal
    //    convention plugin:install uses by default.
    final candidates = <String>{
      if (providerClassName != null) providerClassName,
      _legacyProviderClassName(pluginName),
    };
    for (final cls in candidates) {
      final pattern = RegExp(
        r'\n?\s*registry\.registerProvider\(' +
            RegExp.escape(cls) +
            r'\(\)\);\n?',
      );
      content = content.replaceAll(pattern, '\n');
    }

    // 3. Collapse any accidental triple-newline run the strips left behind.
    content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    installContext.fs.writeAsString(wrapperPath, content);
  }

  /// snake_case to `'<PascalCase>ArtisanProvider'`. Matches the convention
  /// applied by [PluginInstallCommand] when the operator does not pass
  /// `--provider=`.
  ///
  /// @param pluginName  Pubspec package name in snake_case.
  /// @return Derived provider class name (`magic_logger` → `MagicLoggerArtisanProvider`).
  static String _legacyProviderClassName(String pluginName) {
    final parts = pluginName
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join();
    return '${parts}ArtisanProvider';
  }
}
