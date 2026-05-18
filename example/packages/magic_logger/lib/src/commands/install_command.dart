import 'dart:io';
import 'dart:isolate';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// `logger:install`, installs magic_logger via the bundled install.yaml
/// manifest.
///
/// Demonstrates the canonical third-party-plugin install pattern post the
/// PluginInstaller DSL landing (Wave 4):
///
///   - Extends [ArtisanInstallCommand] so the four standard flags
///     (`--force`, `--dry-run`, `--non-interactive`, `--no-bootstrap`) and
///     the [InstallContext] plumbing come for free via [baseFlags] +
///     [buildContext].
///   - Adds two plugin-specific options (`--path`, `--level`) that bypass the
///     matching interactive prompts via [ManifestInstaller.promptOverrides].
///   - Delegates 100% of the install work to [ManifestInstaller]; no
///     imperative file writes live here. The previous ~125 LoC of inline
///     `StubLoader.load` + `FileHelper.writeFile` collapsed into a thin
///     translation layer.
///
/// Test seam: [resolveManifestPath] and [buildContext] are
/// `@visibleForTesting` (the base [buildContext] is already overridable) so
/// the test suite can subclass + inject a deterministic manifest path and an
/// in-memory [InstallContext.test] instead of round-tripping through the host
/// filesystem.
class LoggerInstallCommand extends ArtisanInstallCommand {
  /// Public default constructor. Test fixtures subclass + override the two
  /// `@visibleForTesting` hooks.
  LoggerInstallCommand();

  @override
  String get signature => 'logger:install '
      '$baseFlags'
      '{--path= : Log file path override (bypasses the interactive prompt)} '
      '{--level=info : Minimum log level override (debug|info|warn|error)}';

  @override
  String get description =>
      'Install magic_logger via the bundled install.yaml manifest.';

  @override
  String pluginName(ArtisanContext ctx) => 'magic_logger';

  /// Resolves the absolute filesystem path of the plugin's `install.yaml`.
  ///
  /// Production path: resolves `package:magic_logger/cli.dart` via
  /// [Isolate.resolvePackageUri] (the canonical Dart way to locate a vendored
  /// package's root from any cwd), then walks two directories up to the
  /// plugin root and checks for `install.yaml`.
  ///
  /// Returns `null` when the manifest cannot be located so the handler can
  /// surface a clean error instead of throwing.
  ///
  /// @return The absolute manifest path, or `null` when no manifest is found.
  @visibleForTesting
  Future<String?> resolveManifestPath() async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:magic_logger/cli.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') return null;

    // resolved → <plugin_root>/lib/cli.dart; two dirname() calls back out.
    final libCli = resolved.toFilePath();
    final pluginRoot = p.dirname(p.dirname(libCli));
    final manifestPath = p.join(pluginRoot, 'install.yaml');
    return File(manifestPath).existsSync() ? manifestPath : null;
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Resolve the manifest. A null result means the asset is missing, the
    //    plugin bundle is malformed, surface it as a hard error.
    final manifestPath = await resolveManifestPath();
    if (manifestPath == null) {
      ctx.output.error(
        'magic_logger install.yaml could not be resolved. The plugin asset '
        'bundle is missing or the package was loaded from an unexpected '
        'location.',
      );
      return 1;
    }

    // 2. Parse + validate the manifest via the shared parser. FormatException
    //    covers raw YAML breakage; ManifestValidationException covers schema
    //    drift (regex / placeholder reference / duplicate prompt key).
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

    // 3. Build CLI prompt overrides. `--path` (no default) supplies the
    //    logPath answer only when the operator passed a value. `--level`
    //    defaults to "info" via the signature, so the value is always set;
    //    forwarding it as an override is safe because matching the manifest
    //    default is a no-op semantically (PromptDriver would have returned the
    //    same string).
    final overrides = <String, String>{};
    final pathOverride = ctx.input.option('path') as String?;
    if (pathOverride != null && pathOverride.isNotEmpty) {
      overrides['logPath'] = pathOverride;
    }
    final levelOverride = ctx.input.option('level') as String?;
    if (levelOverride != null && levelOverride.isNotEmpty) {
      overrides['level'] = levelOverride;
    }

    // 4. Build the install context + delegate to ManifestInstaller. Test
    //    subclasses override [buildContext] to inject an in-memory FS;
    //    production uses the real wiring from [ArtisanInstallCommand].
    final installContext = buildContext(ctx);
    final installer = ManifestInstaller(
      installContext,
      manifest,
      promptOverrides: overrides,
    );
    final result = await installer.install(
      dryRun: isDryRun(ctx),
      force: isForce(ctx),
      nonInteractive: isNonInteractive(ctx),
    );

    // 5. On a successful (non-dry-run) install, register the plugin in
    //    .artisan/plugins.json and trigger an in-process registry refresh so
    //    the caller's `bin/artisan.dart` picks up the new commands immediately.
    //    Both operations are skipped on DryRun / Conflict / Error so the
    //    registry stays consistent with the actual disk state.
    if (result is Success) {
      await _writePluginsJsonEntry(ctx, installContext);
      await _autoRefresh(ctx);
    }

    // 6. Translate the TransactionResult into a process exit code + the
    //    matching operator-facing line.
    return _renderResult(ctx, result);
  }

  /// Writes the `magic_logger` entry into `.artisan/plugins.json`.
  ///
  /// Uses [installContext.fs] and [installContext.projectRoot] so the
  /// [InMemoryFs] test seam is honoured automatically. The [PluginsRegistryFile]
  /// call is idempotent: a pre-existing entry with the same name is replaced
  /// in-place rather than duplicated.
  ///
  /// @param ctx             The active [ArtisanContext] (used for output on
  ///                        unexpected errors).
  /// @param installContext  The wired install context carrying [VirtualFs] +
  ///                        [projectRoot].
  Future<void> _writePluginsJsonEntry(
    ArtisanContext ctx,
    InstallContext installContext,
  ) async {
    final pluginsFile = PluginsRegistryFile(
      installContext.fs,
      installContext.projectRoot,
    );
    await pluginsFile.addPlugin(
      PluginEntry(
        name: 'magic_logger',
        providerImport: 'package:magic_logger/cli.dart',
        providerClass: 'MagicLoggerArtisanProvider',
        registeredAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  /// Triggers an in-process `plugins:refresh` when it is registered in
  /// [ctx.registry], or emits a manual-refresh hint when it is absent.
  ///
  /// Using the registry (not `Process.run`) matches locked decision 13: keep
  /// refresh in-process so there is no subprocess latency and the operator's
  /// terminal sees a single cohesive output stream.
  ///
  /// @param ctx  The active [ArtisanContext] whose [registry] is consulted.
  Future<void> _autoRefresh(ArtisanContext ctx) async {
    final refresh = ctx.registry?.find('plugins:refresh');
    if (refresh != null) {
      await refresh.handle(ctx);
    } else {
      ctx.output.info(
        'Run `dart run magic:artisan plugins:refresh` to register '
        'magic_logger commands.',
      );
    }
  }

  /// Translates a [TransactionResult] into an exit code while writing the
  /// matching summary line through [ArtisanOutput].
  ///
  /// Exit map:
  ///   - [Success] → 0 (record path echoed via success())
  ///   - [DryRun]  → 0 (no disk side effect)
  ///   - [Conflict] → 1 (operator must rerun with --force)
  ///   - [Error]    → 2 (distinct from Conflict so CI can branch)
  ///
  /// @param ctx     The active [ArtisanContext] for output writes.
  /// @param result  The [TransactionResult] returned by [ManifestInstaller.install].
  /// @return The process exit code per the table above.
  int _renderResult(ArtisanContext ctx, TransactionResult result) {
    switch (result) {
      case Success(opCount: final n, recordPath: final path):
        ctx.output.success(
          'magic_logger installed ($n op(s)). Install record: $path',
        );
        return 0;
      case DryRun(opCount: final n):
        ctx.output.info(
          'Dry-run: $n op(s) staged; no files were written.',
        );
        return 0;
      case Conflict(conflicts: final list):
        ctx.output.error(
          'Conflict on ${list.length} file(s). Re-run with --force to '
          'overwrite.',
        );
        for (final c in list) {
          ctx.output.warning('  ${c.absPath}: ${c.reason}');
        }
        return 1;
      case Error(error: final msg, rolledBack: final ok):
        ctx.output.error('Install failed: $msg (rolledBack: $ok)');
        return 2;
    }
  }
}
