import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Builds a fake consumer project tree under [root] with the four files
/// `plugin:uninstall` needs: pubspec.yaml, package_config.json, the legacy
/// bin/artisan.dart wrapper (already carrying the plugin's import + register
/// line — uninstall MUST be able to strip both), and the install record at
/// `.artisan/installed/<plugin>.json`.
///
/// @param root         Temp project root.
/// @param pluginName   Plugin pubspec package name.
/// @param providerName PascalCase provider class name (matches the register
///                     line shape produced by [PluginInstallCommand]).
/// @param ops          Optional list of recorded ops to embed in the install
///                     record. Defaults to a single WriteFile so the reverse
///                     transaction has something concrete to undo.
void _seedInstalledProject(
  Directory root, {
  required String pluginName,
  required String providerName,
  List<Map<String, dynamic>>? ops,
}) {
  // 1. pubspec.yaml.
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: consumer\n'
    'dependencies:\n'
    '  $pluginName: ^1.0.0\n',
  );

  // 2. .dart_tool/package_config.json.
  final pkgConfigDir = Directory(p.join(root.path, '.dart_tool'))
    ..createSync(recursive: true);
  File(p.join(pkgConfigDir.path, 'package_config.json')).writeAsStringSync(
    '{"packages":[{"name": "$pluginName"}]}\n',
  );

  // 3. bin/artisan.dart with the plugin already registered (mirror of the
  //    state plugin:install leaves behind).
  final binDir = Directory(p.join(root.path, 'bin'))
    ..createSync(recursive: true);
  File(p.join(binDir.path, 'artisan.dart')).writeAsStringSync(
    "import 'package:fluttersdk_artisan/artisan.dart';\n"
    "import 'package:$pluginName/cli.dart';\n\n"
    "Future<void> main(List<String> args) async {\n"
    "  final registry = ArtisanRegistry();\n"
    "  final auto = await loadAutoIndex();\n"
    "  registry.registerAll(auto.commands, providerName: 'app');\n"
    "    registry.registerProvider($providerName());\n"
    "  final app = ArtisanApplication(registry);\n"
    "  await app.run(args);\n"
    "}\n",
  );

  // 4. Published config file (the WriteFile op in the record points here).
  final configPath = p.join(root.path, 'lib', 'config', 'demo.dart');
  Directory(p.dirname(configPath)).createSync(recursive: true);
  File(configPath).writeAsStringSync('const x = 1;\n');

  // 5. Install record.
  final recordDir = Directory(p.join(root.path, '.artisan', 'installed'))
    ..createSync(recursive: true);
  File(p.join(recordDir.path, '$pluginName.json')).writeAsStringSync(
    jsonEncode(<String, dynamic>{
      'plugin': pluginName,
      'installedAt': '2025-01-01T00:00:00.000Z',
      'ops': ops ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'WriteFile',
              'targetPath': configPath,
              'content': 'const x = 1;\n',
            },
          ],
      'stubHashes': <String, String>{},
    }),
  );
}

/// Writes an `install.yaml` manifest at [path] declaring [pluginName].
void _writeInstallYaml(String path, String pluginName) {
  File(path).writeAsStringSync('plugin_name: $pluginName\n');
}

/// Builds an [ArtisanContext] backed by a [MapInput] + [BufferedOutput].
ArtisanContext _ctxWith(
  Map<String, dynamic> options, {
  List<String> positional = const [],
  CommandSignature? signature,
}) {
  return ArtisanContext.bare(
    MapInput(options, positional: positional, signature: signature),
    BufferedOutput(),
  );
}

/// Test subclass injecting deterministic paths so the command never touches
/// the host package's filesystem layout.
class _TestablePluginUninstallCommand extends PluginUninstallCommand {
  _TestablePluginUninstallCommand({
    required this.fakeProjectRoot,
    required this.fakeInstallYamlPath,
    this.confirmAnswer = true,
  });

  /// Pinned project root for the test invocation.
  final String fakeProjectRoot;

  /// install.yaml path the resolver returns (the manifest still exists at
  /// uninstall time so the command can re-parse it).
  final String fakeInstallYamlPath;

  /// Forced confirm() answer for tests that exercise the interactive prompt.
  final bool confirmAnswer;

  @override
  String getProjectRoot() => fakeProjectRoot;

  @override
  Future<String?> resolveInstallYaml(String pluginName) async =>
      fakeInstallYamlPath;

  @override
  bool promptConfirmation(ArtisanContext ctx, String pluginName) =>
      confirmAnswer;
}

/// Builds the standard option map for an uninstall invocation. Tests pass
/// partial overrides via the [overrides] map.
Map<String, dynamic> _baseOpts({Map<String, dynamic>? overrides}) {
  final base = <String, dynamic>{
    'force': false,
    'dry-run': false,
    'non-interactive': false,
    'no-bootstrap': false,
  };
  if (overrides != null) base.addAll(overrides);
  return base;
}

void main() {
  group('PluginUninstallCommand — signature DSL', () {
    test('inherits the 4 base flags via ArtisanInstallCommand.baseFlags', () {
      final cmd = PluginUninstallCommand();
      final parsed = cmd.parsedSignature!;
      final optionNames = parsed.options.map((o) => o.name).toSet();

      expect(
        optionNames,
        containsAll(<String>[
          'force',
          'dry-run',
          'non-interactive',
          'no-bootstrap',
        ]),
      );
    });

    test('declares only the {name} positional on top of the base flags', () {
      final cmd = PluginUninstallCommand();
      final parsed = cmd.parsedSignature!;

      expect(parsed.name, 'plugin:uninstall');
      expect(parsed.arguments.map((a) => a.name), contains('name'));
      expect(parsed.options.length, 4,
          reason: 'No plugin-specific flags beyond the base 4.');
    });

    test('extends ArtisanInstallCommand (CommandBoot.none)', () {
      final cmd = PluginUninstallCommand();
      expect(cmd, isA<ArtisanInstallCommand>());
      expect(cmd.boot, CommandBoot.none);
    });

    test('pluginName(ctx) derives from the positional name argument', () {
      final cmd = PluginUninstallCommand();
      final ctx = _ctxWith(
        const <String, dynamic>{},
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );
      expect(cmd.pluginName(ctx), 'magic_logger');
    });
  });

  group('PluginUninstallCommand — happy path', () {
    test('full uninstall removes published file + record + wrapper lines',
        () async {
      final root = Directory.systemTemp.createTempSync('plun_full_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedInstalledProject(
        root,
        pluginName: 'demo_plugin',
        providerName: 'DemoPluginArtisanProvider',
      );
      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      final cmd = _TestablePluginUninstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
      );
      final ctx = _ctxWith(
        _baseOpts(overrides: const {'force': true}),
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // Published file reversed by the WriteFile → DeleteFile mapping.
      expect(File(p.join(root.path, 'lib', 'config', 'demo.dart')).existsSync(),
          isFalse);

      // Install record deleted on Success.
      expect(
          File(p.join(root.path, '.artisan', 'installed', 'demo_plugin.json'))
              .existsSync(),
          isFalse);

      // bin/artisan.dart no longer carries the plugin's import / register.
      final wrapper =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();
      expect(
          wrapper, isNot(contains("import 'package:demo_plugin/cli.dart';")));
      expect(
          wrapper,
          isNot(contains(
              'registry.registerProvider(DemoPluginArtisanProvider())')));
    });

    test('--force skips the interactive confirm prompt', () async {
      final root = Directory.systemTemp.createTempSync('plun_force_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedInstalledProject(
        root,
        pluginName: 'demo_plugin',
        providerName: 'DemoPluginArtisanProvider',
      );
      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      // Confirm answer is set to FALSE — if --force is honoured the command
      // must skip the prompt entirely and proceed regardless.
      final cmd = _TestablePluginUninstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
        confirmAnswer: false,
      );
      final ctx = _ctxWith(
        _baseOpts(overrides: const {'force': true}),
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);
      expect(
          File(p.join(root.path, '.artisan', 'installed', 'demo_plugin.json'))
              .existsSync(),
          isFalse);
    });

    test('--non-interactive skips the confirm prompt', () async {
      final root = Directory.systemTemp.createTempSync('plun_nonint_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedInstalledProject(
        root,
        pluginName: 'demo_plugin',
        providerName: 'DemoPluginArtisanProvider',
      );
      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      final cmd = _TestablePluginUninstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
        confirmAnswer: false,
      );
      final ctx = _ctxWith(
        _baseOpts(overrides: const {'non-interactive': true}),
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);
    });

    test('interactive decline returns 0 without modifying state', () async {
      final root = Directory.systemTemp.createTempSync('plun_decline_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedInstalledProject(
        root,
        pluginName: 'demo_plugin',
        providerName: 'DemoPluginArtisanProvider',
      );
      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      // Neither --force nor --non-interactive → prompt runs; confirmAnswer
      // says NO → command must abort without mutating anything.
      final cmd = _TestablePluginUninstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
        confirmAnswer: false,
      );
      final ctx = _ctxWith(
        _baseOpts(),
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // State preserved.
      expect(
          File(p.join(root.path, '.artisan', 'installed', 'demo_plugin.json'))
              .existsSync(),
          isTrue);
      expect(File(p.join(root.path, 'lib', 'config', 'demo.dart')).existsSync(),
          isTrue);
      final wrapper =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();
      expect(wrapper, contains("import 'package:demo_plugin/cli.dart';"));
    });
  });

  group('PluginUninstallCommand — dry-run', () {
    test('--dry-run reports the planned reverse without touching disk',
        () async {
      final root = Directory.systemTemp.createTempSync('plun_dryrun_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedInstalledProject(
        root,
        pluginName: 'demo_plugin',
        providerName: 'DemoPluginArtisanProvider',
      );
      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      final cmd = _TestablePluginUninstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
      );
      final ctx = _ctxWith(
        _baseOpts(overrides: const {'dry-run': true, 'force': true}),
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // Nothing actually mutated.
      expect(
          File(p.join(root.path, '.artisan', 'installed', 'demo_plugin.json'))
              .existsSync(),
          isTrue,
          reason: 'Dry-run must NOT delete the record.');
      expect(File(p.join(root.path, 'lib', 'config', 'demo.dart')).existsSync(),
          isTrue,
          reason: 'Dry-run must NOT delete published files.');
      final wrapper =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();
      expect(wrapper, contains("import 'package:demo_plugin/cli.dart';"),
          reason: 'Dry-run must NOT mutate the wrapper.');

      final out = (ctx.output as BufferedOutput).content;
      expect(out.toLowerCase(), contains('dry'),
          reason: 'Operator must see a dry-run banner.');
    });
  });

  group('PluginUninstallCommand — failure modes', () {
    test('missing record file errors with a helpful message + exit 1',
        () async {
      final root = Directory.systemTemp.createTempSync('plun_missing_');
      addTearDown(() => root.deleteSync(recursive: true));
      // Seed everything EXCEPT the install record.
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: c\n');
      final binDir = Directory(p.join(root.path, 'bin'))
        ..createSync(recursive: true);
      File(p.join(binDir.path, 'artisan.dart'))
          .writeAsStringSync('void main(){}\n');
      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      final cmd = _TestablePluginUninstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
      );
      final ctx = _ctxWith(
        _baseOpts(overrides: const {'force': true}),
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 1);

      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('[ERROR]'));
      expect(out.toLowerCase(), contains('not installed'));
    });

    test('missing install.yaml errors with a helpful message + exit 1',
        () async {
      final root = Directory.systemTemp.createTempSync('plun_noyaml_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedInstalledProject(
        root,
        pluginName: 'demo_plugin',
        providerName: 'DemoPluginArtisanProvider',
      );

      // Subclass returns null for the install.yaml lookup.
      final cmd = _TestablePluginUninstallCommandNoYaml(
        fakeProjectRoot: root.path,
      );
      final ctx = _ctxWith(
        _baseOpts(overrides: const {'force': true}),
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('[ERROR]'));
      expect(out, contains('install.yaml'));
    });

    test('missing plugin name argument errors with exit 1', () async {
      final cmd = PluginUninstallCommand();
      final ctx = _ctxWith(
        _baseOpts(),
        positional: const [],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('[ERROR]'));
      expect(out, contains('Missing required argument'));
    });
  });
}

/// Test subclass for the "no install.yaml" failure mode — separate from
/// `_TestablePluginUninstallCommand` because the latter requires the path to
/// be non-nullable per its constructor contract.
class _TestablePluginUninstallCommandNoYaml extends PluginUninstallCommand {
  _TestablePluginUninstallCommandNoYaml({required this.fakeProjectRoot});

  final String fakeProjectRoot;

  @override
  String getProjectRoot() => fakeProjectRoot;

  @override
  Future<String?> resolveInstallYaml(String pluginName) async => null;

  @override
  bool promptConfirmation(ArtisanContext ctx, String pluginName) => true;
}
