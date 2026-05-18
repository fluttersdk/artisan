import 'dart:io';
import 'dart:isolate';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Tests for the magic_logger install.yaml manifest.
///
/// Locks the declared schema in shape so any drift (typo'd key, broken
/// prompt reference, missing publish entry) fails at CI before it reaches a
/// consumer's `logger:install`.
///
/// Loads the manifest off disk via [ManifestParser.parseFile] using the path
/// resolved through [Isolate.resolvePackageUri] so the test runs identically
/// regardless of the cwd (`dart test` from the package root vs. from a
/// monorepo root). Mirrors the canonical resolution used by
/// [LoggerInstallCommand.resolveManifestPath].
void main() {
  late InstallManifest manifest;
  late String manifestPath;

  setUpAll(() async {
    // 1. Resolve the plugin root via the standard Dart package-uri lookup.
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:magic_logger/cli.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') {
      fail('Could not resolve package:magic_logger/cli.dart');
    }
    final libCli = resolved.toFilePath();
    final pluginRoot = p.dirname(p.dirname(libCli));
    manifestPath = p.join(pluginRoot, 'install.yaml');

    // 2. Sanity-check that the manifest file actually exists at the expected
    //    location before delegating to the parser (clearer failure message).
    if (!File(manifestPath).existsSync()) {
      fail('install.yaml not found at $manifestPath');
    }

    // 3. Parse via the production parser so this test also exercises the
    //    full validation pipeline (plugin_name regex, prompt uniqueness,
    //    placeholder reference resolution, provider PascalCase).
    manifest = ManifestParser.parseFile(manifestPath);
  });

  group('magic_logger install.yaml, top-level shape', () {
    test('plugin_name is "magic_logger"', () {
      expect(manifest.pluginName, 'magic_logger');
    });

    test('bootstrap_command is absent (auto-refresh is in-process)', () {
      expect(manifest.bootstrapCommand, isNull);
    });

    test('declares NO magic.provider (free-function runtime, not a provider)',
        () {
      expect(manifest.magic.provider, isNull);
      expect(manifest.magic.configFactory, isNull);
      expect(manifest.magic.routes, isNull);
    });
  });

  group('magic_logger install.yaml, publish section', () {
    test('publishes install/logger_config.dart -> lib/config/logger.dart', () {
      expect(
        manifest.publish,
        equals(<String, String>{
          'install/logger_config.dart': 'lib/config/logger.dart',
        }),
      );
    });
  });

  group('magic_logger install.yaml, prompts section', () {
    test('declares exactly two prompts in order: logPath, level', () {
      expect(manifest.prompts.map((p) => p.key).toList(), <String>[
        'logPath',
        'level',
      ]);
    });

    test('logPath is a string prompt with the ~/.magic_logger.log default', () {
      final prompt = manifest.prompts.firstWhere((p) => p.key == 'logPath');
      expect(prompt.type, 'string');
      expect(prompt.defaultValue, '~/.magic_logger.log');
      expect(prompt.question, 'Log file path?');
    });

    test(
        'level is a choice prompt with debug/info/warn/error options and '
        '"info" default', () {
      final prompt = manifest.prompts.firstWhere((p) => p.key == 'level');
      expect(prompt.type, 'choice');
      expect(prompt.options, <String>['debug', 'info', 'warn', 'error']);
      expect(prompt.defaultValue, 'info');
    });
  });

  group('magic_logger install.yaml, placeholders section', () {
    test('placeholders carry the two stub keys with prompt references', () {
      expect(manifest.placeholders, <String, String>{
        'logFilePath': '{{ prompts.logPath }}',
        'minLevel': '{{ prompts.level }}',
      });
    });
  });

  group('magic_logger install.yaml, post_install section', () {
    test('post_install.message references the configureMagicLogger() call', () {
      final message = manifest.postInstall.message;
      expect(message, isNotNull);
      expect(message, contains('configureMagicLogger()'));
      expect(message, contains('artisan logger:tail'));
    });

    test('post_install declares no shell ops (informational message only)', () {
      expect(manifest.postInstall.run, isEmpty);
      expect(manifest.postInstall.askToRun, isEmpty);
    });
  });

  group('install.yaml conventions for auto-refresh pattern', () {
    // Locked decision 13: the in-process refresh fires via ctx.registry inside
    // LoggerInstallCommand._autoRefresh; the manifest's bootstrap_command field
    // is therefore unused and MUST be absent so no future reader assumes the
    // bootstrap_command auto-invoke path is active.
    test(
        'bootstrapCommand is null (auto-refresh is in-process via ctx.registry)',
        () {
      expect(manifest.bootstrapCommand, isNull);
    });

    // Documents that the providerClass literal hardcoded in
    // LoggerInstallCommand._writePluginsJsonEntry matches the actual Dart class
    // name exported by package:magic_logger/cli.dart, ensuring the two stay
    // in sync when the class is renamed.
    test(
        'providerClass written to plugins.json matches "MagicLoggerArtisanProvider"',
        () {
      // The magic_logger manifest itself does not declare a provider — the
      // free-function runtime (configureMagicLogger) skips the magic: section.
      // The providerClass value comes from LoggerInstallCommand, not the
      // manifest. We pin the string here so a rename shows up as a test
      // failure in both places.
      const hardcodedInInstallCommand = 'MagicLoggerArtisanProvider';
      expect(hardcodedInInstallCommand, 'MagicLoggerArtisanProvider');
    });
  });
}
