import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../console/artisan_context.dart';
import '../console/string_helper.dart';
import '../helpers/config_editor.dart';
import '../helpers/file_helper.dart';
import '../installer/artisan_install_command.dart';
import '../installer/install_exception.dart';
import '../installer/install_manifest.dart';
import '../installer/install_transaction.dart';
import '../installer/manifest_installer.dart';
import '../installer/manifest_parser.dart';
import '../installer/plugins_registry_file.dart';
import '../installer/virtual_fs.dart';
import 'plugins_refresh_command.dart';

/// `plugin:install <name>`, register a third-party artisan plugin into the
/// consumer project.
///
/// Two flows live in this command:
///
///   1. **Manifest flow** (preferred): when the plugin ships an
///      `install.yaml` at its package root or `assets/install.yaml`, parse
///      it via [ManifestParser], translate it via [ManifestInstaller], and
///      commit through the [PluginInstaller] DSL. This is the standard
///      Plugin Authoring Guide path (declarative; supports dry-run, conflict
///      detection, install records, reverse on uninstall).
///
///   2. **Legacy flow** (fallback): when no `install.yaml` is found, fall
///      back to the original behaviour, append
///      `import 'package:<name>/cli.dart';` and
///      `registry.registerProvider(<Provider>())` to the consumer's
///      `bin/artisan.dart`. Kept for backward compatibility with plugins
///      authored before the manifest schema landed.
///
/// Pass `--use-yaml-only` to make the manifest flow strict: when no
/// manifest is found the command errors out instead of falling back.
///
/// Plugin authoring conventions assumed by the legacy flow:
///   - Plugin exports a CLI barrel at `package:<name>/cli.dart`.
///   - Plugin declares a provider class named `<PascalCaseName>ArtisanProvider`
///     in that barrel. Override with `--provider=ClassName` when the plugin
///     uses a different naming convention.
///
/// Pre-flight validation (both flows):
///   - The package must be listed in the consumer's `pubspec.yaml`.
///   - The package must be resolvable via
///     `.dart_tool/package_config.json` (so `flutter pub get` ran).
///   - `bin/artisan.dart` must exist (legacy flow injects into it; manifest
///     flow keeps it as the conventional wrapper).
///
/// Dart has no auto-discovery for service providers (no `dart:mirrors` under
/// AOT, no Laravel-style `composer.json` extras). This command IS the
/// substitute: the consumer adds the dep + runs `plugin:install <name>` once
/// and never touches `bin/artisan.dart` by hand.
class PluginInstallCommand extends ArtisanInstallCommand {
  /// Public default constructor. Test fixtures subclass + override
  /// [getProjectRoot] / [resolveInstallYaml] to inject deterministic paths
  /// without depending on the host's filesystem layout.
  PluginInstallCommand();

  @override
  String get signature => 'plugin:install '
      '$baseFlags'
      '{name : Plugin pubspec package name (e.g. magic_logger)} '
      '{--provider= : Override the auto-derived provider class name} '
      '{--bootstrap-command= : Plugin install sub-command to chain after registration (e.g. logger:install)} '
      '{--use-yaml-only : Fail if install.yaml not found instead of falling back to legacy injection}';

  @override
  String get description =>
      'Register a third-party artisan plugin (install.yaml manifest preferred; '
      'legacy bin/artisan.dart injection as fallback).';

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
  /// plugin ships no manifest.
  ///
  /// Resolution strategy (canonical Dart approach used elsewhere in this
  /// package, see magic_logger install_command for the prior art):
  ///   1. Resolve `package:<pluginName>/cli.dart` via [Isolate.resolvePackageUri].
  ///   2. Walk two directories up from `lib/cli.dart` to reach the plugin
  ///      root.
  ///   3. Check `<root>/install.yaml` first; fall back to
  ///      `<root>/assets/install.yaml`.
  ///
  /// Returns `null` for any failure mode (URI scheme not file, no candidate
  /// file present, resolution exception). Callers treat `null` as "no
  /// manifest" and proceed to the legacy branch (or fail when
  /// `--use-yaml-only` is set).
  ///
  /// @param pluginName  The plugin's pubspec package name.
  /// @return Absolute path to the install.yaml, or `null` when none found.
  @visibleForTesting
  Future<String?> resolveInstallYaml(String pluginName) async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:$pluginName/cli.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') return null;

    // resolved → <plugin_root>/lib/cli.dart; two dirname() calls back out.
    final libCli = resolved.toFilePath();
    final pluginRoot = p.dirname(p.dirname(libCli));

    final atRoot = p.join(pluginRoot, 'install.yaml');
    if (File(atRoot).existsSync()) return atRoot;

    final atAssets = p.join(pluginRoot, 'assets', 'install.yaml');
    if (File(atAssets).existsSync()) return atAssets;

    return null;
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Validate the positional name argument first so the rest of the
    //    handler can rely on a non-empty plugin name.
    final name = pluginName(ctx);
    if (name.isEmpty) {
      ctx.output.error('Missing required argument: name.');
      return 1;
    }

    // 2. Run the shared pre-flight (pubspec dep + package_config + wrapper
    //    presence). Both branches need the wrapper present.
    final root = getProjectRoot();
    final wrapperPath = p.join(root, 'bin', 'artisan.dart');
    final preflight =
        _preflight(ctx, root: root, name: name, wrapperPath: wrapperPath);
    if (preflight != 0) return preflight;

    // 3. Resolve the plugin's install.yaml. When found, route to the
    //    manifest flow; otherwise honour --use-yaml-only, fall through to
    //    the direct-registration flow (canonical scaffold path), or fall
    //    back to the legacy injection.
    final manifestPath = await resolveInstallYaml(name);
    if (manifestPath != null) {
      return _runManifestFlow(ctx, manifestPath: manifestPath);
    }

    if (isUseYamlOnly(ctx)) {
      ctx.output.error(
        'No install.yaml found for plugin "$name" and --use-yaml-only '
        'was passed. Either remove --use-yaml-only to allow the legacy '
        'injection fallback, or add an install.yaml manifest to the '
        'plugin (see doc/install_yaml_schema.md).',
      );
      return 1;
    }

    // 3b. Generic plugin (no install.yaml) AND canonical consumer scaffold
    //     present (lib/app/_plugins.g.dart exists). Skip the legacy
    //     bin/artisan.dart injection: write directly to .artisan/plugins.json
    //     and refresh _plugins.g.dart. This is the Magic-less parallel of
    //     the manifest-flow `_registerArtisanProvider` step, working purely
    //     against the canonical scaffold from `install`.
    if (File(p.join(root, 'lib', 'app', '_plugins.g.dart')).existsSync()) {
      await _registerArtisanProvider(ctx, name: name);
      ctx.output.success(
        'Registered "$name" via canonical scaffold (no install.yaml needed).',
      );
      return 0;
    }

    return _runLegacyFlow(ctx, name: name, wrapperPath: wrapperPath);
  }

  /// Returns `true` when the operator passed `--use-yaml-only`.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return The boolean value of the `--use-yaml-only` flag.
  bool isUseYamlOnly(ArtisanContext ctx) =>
      ctx.input.option('use-yaml-only') as bool? ?? false;

  // ---------------------------------------------------------------------------
  // Pre-flight
  // ---------------------------------------------------------------------------

  /// Runs the three pre-flight checks shared by both flows. Returns `0` when
  /// every check passes; non-zero exit code on the first failure (after
  /// writing the matching error to `ctx.output`).
  int _preflight(
    ArtisanContext ctx, {
    required String root,
    required String name,
    required String wrapperPath,
  }) {
    // 1. Wrapper presence, the framework injects into bin/artisan.dart and
    //    expects the file to exist even on the manifest path (the file IS
    //    the conventional CLI entry point).
    if (!File(wrapperPath).existsSync()) {
      ctx.output.error(
        'bin/artisan.dart not found at $wrapperPath. '
        'plugin:install needs the consumer wrapper present.',
      );
      return 1;
    }

    // 2. Pubspec dep check, saves the user from a confusing import error.
    final pubspecPath = p.join(root, 'pubspec.yaml');
    if (File(pubspecPath).existsSync()) {
      final pubspec = File(pubspecPath).readAsStringSync();
      if (!pubspec.contains(RegExp('^\\s+$name:', multiLine: true))) {
        ctx.output.error(
          'Package "$name" is not listed in pubspec.yaml dependencies. '
          'Add it first, then run `flutter pub get`, then retry.',
        );
        return 1;
      }
    }

    // 3. Package resolvable in package_config.json.
    final packageConfig = File(
      p.join(root, '.dart_tool', 'package_config.json'),
    );
    if (packageConfig.existsSync() &&
        !packageConfig.readAsStringSync().contains('"name": "$name"')) {
      ctx.output.error(
        'Package "$name" is not in .dart_tool/package_config.json. '
        'Run `flutter pub get` first.',
      );
      return 1;
    }

    return 0;
  }

  // ---------------------------------------------------------------------------
  // Manifest flow
  // ---------------------------------------------------------------------------

  /// Parses the install.yaml at [manifestPath] and commits via
  /// [ManifestInstaller]. On a non-dry-run [Success], also registers the
  /// plugin's [ArtisanServiceProvider] in `.artisan/plugins.json` and
  /// regenerates `lib/app/_plugins.g.dart` so commands appear in
  /// `dart run magic:artisan list` without a separate `plugins:refresh` step.
  Future<int> _runManifestFlow(
    ArtisanContext ctx, {
    required String manifestPath,
  }) async {
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

    final installContext = buildContext(ctx);
    final installer = ManifestInstaller(installContext, manifest);
    final result = await installer.install(
      dryRun: isDryRun(ctx),
      force: isForce(ctx),
      nonInteractive: isNonInteractive(ctx),
    );

    final exit = _renderResultAndExit(ctx, result, manifest: manifest);
    if (result is Success && !isDryRun(ctx)) {
      await _registerArtisanProvider(ctx, name: manifest.pluginName);
    }
    return exit;
  }

  /// Convention-based registration of the plugin's [ArtisanServiceProvider] in
  /// `.artisan/plugins.json`, then a synchronous regeneration of
  /// `lib/app/_plugins.g.dart` via [PluginsRefreshCommand] so the host's
  /// `bin/artisan.dart` picks up the plugin's commands on the next invocation.
  ///
  /// Naming convention: `package:<name>/cli.dart` is the import URI and
  /// `<PascalCaseName>ArtisanProvider` is the class name. Plugins that follow
  /// a different convention are out of scope here; they can run
  /// `plugins:refresh` manually after editing `.artisan/plugins.json` by hand.
  Future<void> _registerArtisanProvider(
    ArtisanContext ctx, {
    required String name,
  }) async {
    final root = getProjectRoot();
    final pascalName = _pascalCase(name);
    final entry = PluginEntry(
      name: name,
      providerImport: 'package:$name/cli.dart',
      providerClass: '${pascalName}ArtisanProvider',
      registeredAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await PluginsRegistryFile(const RealFs(), root).addPlugin(entry);
      await PluginsRefreshCommand(projectRoot: root).handle(ctx);
    } catch (e) {
      ctx.output.warning(
        'Plugin "$name" was installed but artisan command auto-registration '
        'failed: $e. Run `dart run magic:artisan plugins:refresh` manually.',
      );
    }
  }

  /// Maps a [TransactionResult] to the appropriate user-facing output +
  /// process exit code.
  int _renderResultAndExit(
    ArtisanContext ctx,
    TransactionResult result, {
    required InstallManifest manifest,
  }) {
    switch (result) {
      case Success():
        ctx.output.success(result.describe());
        _emitBootstrapHint(ctx, manifest: manifest);
        return 0;
      case DryRun():
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

  /// Emits the one-line bootstrap hint when the manifest declares a
  /// `bootstrap_command` and the operator did not pass `--no-bootstrap`.
  void _emitBootstrapHint(
    ArtisanContext ctx, {
    required InstallManifest manifest,
  }) {
    final bootstrap = manifest.bootstrapCommand;
    if (bootstrap == null || isSkipBootstrap(ctx)) return;
    ctx.output.info(
      'Re-run `artisan list` to see new commands. '
      'Bootstrap with: artisan $bootstrap',
    );
  }

  // ---------------------------------------------------------------------------
  // Legacy flow (preserved for plugins without install.yaml)
  // ---------------------------------------------------------------------------

  /// Original imperative injection: appends an import line + a
  /// `registerProvider(...)` line into the consumer's `bin/artisan.dart`.
  /// Kept for backward compatibility with plugins that have not authored a
  /// manifest yet.
  Future<int> _runLegacyFlow(
    ArtisanContext ctx, {
    required String name,
    required String wrapperPath,
  }) async {
    final providerOverride = ctx.input.option('provider') as String?;
    final bootstrapOverride = ctx.input.option('bootstrap-command') as String?;

    // 1. Derive provider class name. Convention: snake_case → PascalCase
    //    + 'ArtisanProvider' suffix. Override via --provider=ClassName.
    final providerClass =
        providerOverride ?? '${_pascalCase(name)}ArtisanProvider';

    // 2. Idempotency check.
    final wrapperSource = File(wrapperPath).readAsStringSync();
    final importLine = "import 'package:$name/cli.dart';";
    final registerLine = '    registry.registerProvider($providerClass());';
    final alreadyImported = wrapperSource.contains(importLine);
    final alreadyRegistered = wrapperSource.contains(registerLine);

    final force = isForce(ctx);
    if (alreadyImported && alreadyRegistered && !force) {
      ctx.output.info(
        '$name is already registered in bin/artisan.dart. Use --force to re-write.',
      );
      // Still chain to bootstrap if requested, install commands are
      // idempotent by convention.
    } else {
      // 2a. Append the import (idempotent helper).
      ConfigEditor.addImportToFile(
        filePath: wrapperPath,
        importStatement: importLine,
      );

      // 2b. Append the register line right after the auto.commands line.
      if (!alreadyRegistered || force) {
        if (force && alreadyRegistered) {
          // Strip the old line so the re-write does not double-insert.
          final stripped = File(wrapperPath).readAsStringSync().replaceFirst(
                RegExp('\\n\\s*${RegExp.escape(registerLine)}'),
                '',
              );
          File(wrapperPath).writeAsStringSync(stripped);
        }
        _insertRegisterAfterAutoLine(wrapperPath, registerLine);
      }

      ctx.output.success(
        'Registered "$name" in $wrapperPath (provider: $providerClass).',
      );
    }

    // 3. Optional: chain to the plugin's own install command.
    if (isSkipBootstrap(ctx)) {
      ctx.output.info('Skipping plugin bootstrap command (--no-bootstrap).');
      return 0;
    }
    final bootstrapName = bootstrapOverride ?? _deriveBootstrapName(name);
    ctx.output.info(
      'Re-run `artisan list` to see the new commands. '
      'Bootstrap with: artisan $bootstrapName',
    );
    return 0;
  }

  /// snake_case → PascalCase. `magic_logger` → `MagicLogger`.
  static String _pascalCase(String snake) {
    return snake
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(StringHelper.toPascalCase)
        .join();
  }

  /// Derive the plugin's domain install command name from the package
  /// name. Convention: strip leading `magic_` / `fluttersdk_` prefix,
  /// keep what remains, append `:install`.
  ///
  /// `magic_logger` → `logger:install`
  /// `fluttersdk_dusk` → `dusk:install` (if the plugin exposes one)
  /// `magic_starter` → `starter:install`
  static String _deriveBootstrapName(String pkg) {
    var stripped = pkg;
    for (final prefix in const ['magic_', 'fluttersdk_']) {
      if (stripped.startsWith(prefix)) {
        stripped = stripped.substring(prefix.length);
        break;
      }
    }
    return '$stripped:install';
  }

  /// Inserts [registerLine] right after the `registerAll(auto.commands,
  /// ...)` invocation in the consumer wrapper. Falls back to appending
  /// before the `ArtisanApplication` construction line when the anchor is
  /// not present (handles hand-edited wrappers).
  static void _insertRegisterAfterAutoLine(
    String wrapperPath,
    String registerLine,
  ) {
    final content = File(wrapperPath).readAsStringSync();
    final anchor = RegExp(
      r"registry\.registerAll\(auto\.commands,\s*providerName:\s*'app'\);",
    );
    final match = anchor.firstMatch(content);
    if (match != null) {
      final head = content.substring(0, match.end);
      final tail = content.substring(match.end);
      File(wrapperPath).writeAsStringSync('$head\n$registerLine$tail');
      return;
    }
    // Fallback: insert before the ArtisanApplication construction line.
    ConfigEditor.insertCodeBeforePattern(
      filePath: wrapperPath,
      pattern: RegExp(r'\s*final app = ArtisanApplication'),
      code: '\n$registerLine\n',
    );
  }
}
