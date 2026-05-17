import 'dart:io';

import 'package:path/path.dart' as p;

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../console/string_helper.dart';
import '../helpers/config_editor.dart';
import '../helpers/file_helper.dart';

/// `plugin:install <name>` — register a third-party artisan plugin in
/// the consumer's `bin/artisan.dart` so its commands appear in `artisan
/// list` without manual editing.
///
/// Convention: a plugin named `foo_bar`:
///   - exports a CLI barrel at `package:foo_bar/cli.dart`
///   - declares a provider class `FooBarArtisanProvider` in that barrel
///
/// This command:
///   1. Verifies the package is listed in the consumer's pubspec.yaml
///      AND resolvable via `.dart_tool/package_config.json`.
///   2. Idempotently appends `import 'package:foo_bar/cli.dart';` to the
///      consumer's `bin/artisan.dart`.
///   3. Idempotently appends `registry.registerProvider(FooBarArtisanProvider());`
///      right after the auto-discovery line.
///   4. (Optional) Runs the plugin's own `foo_bar:install` command (or
///      a domain-specific equivalent like `logger:install`) so the
///      plugin's runtime config is also scaffolded. Skip with
///      `--no-bootstrap`.
///
/// Dart has no auto-discovery for service providers (Laravel's
/// `composer.json -> extra.laravel.providers` has no equivalent — no
/// `dart:mirrors` in AOT). This command IS the substitute: the consumer
/// adds the package as a pubspec dep + runs `plugin:install <name>` once
/// and never touches `bin/artisan.dart` by hand.
class PluginInstallCommand extends ArtisanCommand {
  @override
  String get signature => 'plugin:install '
      '{name : Plugin pubspec package name (e.g. magic_logger)} '
      '{--provider= : Override the auto-derived provider class name} '
      '{--bootstrap-command= : Plugin install sub-command to chain after registration (e.g. logger:install)} '
      '{--no-bootstrap : Skip the plugin install sub-command chain} '
      '{--force : Re-write the registration lines even when already present}';

  @override
  String get description =>
      'Register a third-party artisan plugin (adds import + registerProvider to bin/artisan.dart).';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final name = ctx.input.argument('name');
    if (name == null || name.isEmpty) {
      ctx.output.error('Missing required argument: name.');
      return 1;
    }
    final force = ctx.input.option('force') as bool;
    final skipBootstrap = ctx.input.option('no-bootstrap') as bool;
    final bootstrapOverride = ctx.input.option('bootstrap-command') as String?;
    final providerOverride = ctx.input.option('provider') as String?;

    // 1. Project root + bin/artisan.dart presence.
    final root = FileHelper.findProjectRoot();
    final wrapperPath = p.join(root, 'bin', 'artisan.dart');
    if (!File(wrapperPath).existsSync()) {
      ctx.output.error(
        'bin/artisan.dart not found at $wrapperPath. '
        'plugin:install needs the consumer wrapper present.',
      );
      return 1;
    }

    // 2. Pubspec dep check — saves the user from a confusing import error.
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

    // 4. Derive provider class name. Convention: snake_case → PascalCase
    //    + 'ArtisanProvider' suffix. Override via --provider=ClassName.
    final providerClass =
        providerOverride ?? '${_pascalCase(name)}ArtisanProvider';

    // 5. Idempotency check.
    final wrapperSource = File(wrapperPath).readAsStringSync();
    final importLine = "import 'package:$name/cli.dart';";
    final registerLine = '    registry.registerProvider($providerClass());';
    final alreadyImported = wrapperSource.contains(importLine);
    final alreadyRegistered = wrapperSource.contains(registerLine);
    if (alreadyImported && alreadyRegistered && !force) {
      ctx.output.info(
        '$name is already registered in bin/artisan.dart. Use --force to re-write.',
      );
      // Still chain to bootstrap if requested — install commands are
      // idempotent by convention.
    } else {
      // 5a. Append the import (idempotent helper).
      ConfigEditor.addImportToFile(
        filePath: wrapperPath,
        importStatement: importLine,
      );

      // 5b. Append the register line right after the auto.commands line.
      //     Pattern: `registerAll(auto.commands, providerName: 'app');`
      if (!alreadyRegistered || force) {
        if (force && alreadyRegistered) {
          // Strip the old line so the re-write does not double-insert.
          final stripped = File(wrapperPath).readAsStringSync().replaceFirst(
              RegExp('\\n\\s*${RegExp.escape(registerLine)}'), '');
          File(wrapperPath).writeAsStringSync(stripped);
        }
        _insertRegisterAfterAutoLine(wrapperPath, registerLine);
      }

      ctx.output.success(
        'Registered "$name" in $wrapperPath (provider: $providerClass).',
      );
    }

    // 6. Optional: chain to the plugin's own install command.
    if (skipBootstrap) {
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
  /// before the closing brace of `main(`'s try block when the anchor is
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
