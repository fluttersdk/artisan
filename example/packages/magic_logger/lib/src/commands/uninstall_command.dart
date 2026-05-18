import 'dart:io';
import 'dart:isolate';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// `logger:uninstall`, reverses the magic_logger install via the bundled
/// install.yaml manifest.
///
/// Mirror image of [LoggerInstallCommand]:
///
///   - Resolves the manifest via [Isolate.resolvePackageUri] (the canonical
///     Dart way to locate a vendored package's root).
///   - Builds an [InstallContext] through the [ArtisanInstallCommand] base
///     class wiring.
///   - Prompts the operator to confirm a destructive op unless `--force` or
///     `--non-interactive` is set (Anilcan rule: every destructive action
///     asks for buy-in).
///   - Delegates 100% of the reverse work to
///     [ManifestInstaller.uninstall] which reads
///     `.artisan/installed/magic_logger.json`, replays each recorded op
///     through `reverseOf`, and commits the reverse transaction.
///   - Maps the [TransactionResult] onto the standard exit code table:
///     Success / DryRun → 0, Conflict → 1, Error → 2.
///
/// Test seam: [resolveManifestPath] + [buildContext] are overridable so the
/// test suite can subclass + inject a deterministic manifest path and an
/// in-memory [InstallContext.test].
class LoggerUninstallCommand extends ArtisanInstallCommand {
  /// Public default constructor. Test fixtures subclass + override the two
  /// `@visibleForTesting` hooks.
  LoggerUninstallCommand();

  @override
  String get signature => 'logger:uninstall $baseFlags';

  @override
  String get description =>
      'Uninstall magic_logger by reversing every op recorded in '
      '.artisan/installed/magic_logger.json.';

  @override
  String pluginName(ArtisanContext ctx) => 'magic_logger';

  /// Resolves the absolute filesystem path of the plugin's `install.yaml`.
  ///
  /// Production path: resolves `package:magic_logger/cli.dart` via
  /// [Isolate.resolvePackageUri], walks two directories up to the plugin
  /// root, returns `<root>/install.yaml` when present.
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

    final libCli = resolved.toFilePath();
    final pluginRoot = p.dirname(p.dirname(libCli));
    final manifestPath = p.join(pluginRoot, 'install.yaml');
    return File(manifestPath).existsSync() ? manifestPath : null;
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Resolve + parse the manifest. The manifest is still needed at
    //    uninstall time so the [ManifestInstaller] knows the plugin name and
    //    can locate the install record at `.artisan/installed/<plugin>.json`.
    final manifestPath = await resolveManifestPath();
    if (manifestPath == null) {
      ctx.output.error(
        'magic_logger install.yaml could not be resolved. The plugin asset '
        'bundle is missing or the package was loaded from an unexpected '
        'location.',
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

    // 2. Build the install context (same wiring used by [LoggerInstallCommand]).
    final installContext = buildContext(ctx);

    // 3. Confirm the destructive op unless --force or --non-interactive is
    //    set. The interactive path goes through the [InstallContext.prompt]
    //    seam so test subclasses can drive the answer through a fake driver.
    if (!isForce(ctx) && !isNonInteractive(ctx)) {
      final confirmed = installContext.prompt.confirm(
        'Uninstall magic_logger? This will reverse every op recorded in '
        '.artisan/installed/magic_logger.json.',
        defaultValue: false,
      );
      if (!confirmed) {
        ctx.output.info('Uninstall aborted by operator.');
        return 0;
      }
    }

    // 4. Delegate the actual reverse work. ManifestInstaller.uninstall
    //    handles the missing-record case (returns Error), the typed reverse
    //    derivation, the atomic commit, and the record-file cleanup on
    //    Success.
    final installer = ManifestInstaller(installContext, manifest);
    final result = await installer.uninstall(force: isForce(ctx));

    // 5. On Success, remove the plugins.json registry entry and trigger an
    //    in-process auto-refresh so the consumer's _plugins.g.dart drops the
    //    uninstalled plugin's commands immediately. Both operations are
    //    idempotent: removePlugin is a no-op when the name is absent, and
    //    plugins:refresh regenerates from whatever remains in plugins.json.
    if (result is Success) {
      final pluginsFile = PluginsRegistryFile(
        installContext.fs,
        installContext.projectRoot,
      );
      await pluginsFile.removePlugin('magic_logger');

      final refresh = ctx.registry?.find('plugins:refresh');
      if (refresh != null) {
        await refresh.handle(ctx);
      } else {
        ctx.output.info(
          'Run `dart run magic:artisan plugins:refresh` to unregister '
          'magic_logger commands.',
        );
      }
    }

    return _renderResult(ctx, result);
  }

  /// Translates a [TransactionResult] into an exit code while writing the
  /// matching summary line through [ArtisanOutput]. Mirrors the table used by
  /// [LoggerInstallCommand._renderResult] so consumers see consistent
  /// success / failure shapes on both ends of the lifecycle.
  ///
  /// @param ctx     The active [ArtisanContext] for output writes.
  /// @param result  The [TransactionResult] returned by
  ///                [ManifestInstaller.uninstall].
  /// @return The process exit code.
  int _renderResult(ArtisanContext ctx, TransactionResult result) {
    switch (result) {
      case Success():
        ctx.output.success('magic_logger uninstalled. ${result.describe()}');
        return 0;
      case DryRun():
        ctx.output.info(result.describe());
        return 0;
      case Conflict(conflicts: final list):
        ctx.output.error(
          'Conflict on ${list.length} file(s) during reverse. Re-run with '
          '--force to overwrite.',
        );
        return 1;
      case Error(error: final msg):
        ctx.output.error('Uninstall failed: $msg');
        return 2;
    }
  }
}
