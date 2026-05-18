import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Builds a fake consumer project tree under [root] with the four files
/// `plugin:install` validates before doing any work: pubspec.yaml listing the
/// plugin as a dep, .dart_tool/package_config.json resolving the plugin name,
/// and bin/artisan.dart wrapper.
///
/// @param root       The temp project root.
/// @param pluginName The plugin name to wire into both files.
/// @param wrapper    The initial bin/artisan.dart content; defaults to the
///                   canonical 6-line wrapper with the auto.commands anchor.
void _seedConsumerProject(
  Directory root, {
  required String pluginName,
  String? wrapper,
}) {
  // 1. pubspec.yaml — plugin listed under dependencies.
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: consumer\n'
    'dependencies:\n'
    '  $pluginName: ^1.0.0\n',
  );

  // 2. .dart_tool/package_config.json — plugin resolvable.
  final pkgConfigDir = Directory(p.join(root.path, '.dart_tool'))
    ..createSync(recursive: true);
  File(p.join(pkgConfigDir.path, 'package_config.json')).writeAsStringSync(
    '{"packages":[{"name": "$pluginName"}]}\n',
  );

  // 3. bin/artisan.dart — canonical wrapper with auto.commands anchor.
  final binDir = Directory(p.join(root.path, 'bin'))
    ..createSync(recursive: true);
  File(p.join(binDir.path, 'artisan.dart')).writeAsStringSync(
    wrapper ??
        "import 'package:fluttersdk_artisan/artisan.dart';\n\n"
            "Future<void> main(List<String> args) async {\n"
            "  final registry = ArtisanRegistry();\n"
            "  final auto = await loadAutoIndex();\n"
            "  registry.registerAll(auto.commands, providerName: 'app');\n"
            "  final app = ArtisanApplication(registry);\n"
            "  await app.run(args);\n"
            "}\n",
  );
}

/// Writes an `install.yaml` manifest at [path] with the supplied
/// [pluginName]. Minimal valid manifest, no sections.
void _writeInstallYaml(String path, String pluginName) {
  File(path).writeAsStringSync('plugin_name: $pluginName\n');
}

/// Builds an [ArtisanContext] backed by a [MapInput] carrying the supplied
/// option / argument values + a [BufferedOutput] for output assertions.
///
/// @param options     Map of option-name → value.
/// @param positional  Positional arguments in declaration order.
/// @param signature   Optional [CommandSignature] for name-based positional
///                    lookup via `ctx.input.argument('name')`.
/// @return A bare [ArtisanContext] suitable for direct `handle()` invocation.
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

/// Test subclass that pins the project root to a temp dir AND lets each test
/// inject a custom install.yaml resolver so the path resolution does not have
/// to round-trip through the host's real Isolate.resolvePackageUri.
class _TestablePluginInstallCommand extends PluginInstallCommand {
  _TestablePluginInstallCommand({
    required this.fakeProjectRoot,
    this.fakeInstallYamlPath,
  });

  /// Pinned project root for the test invocation. Overrides the production
  /// [FileHelper.findProjectRoot] traversal so tests do not depend on the
  /// host package's pubspec.yaml location.
  final String fakeProjectRoot;

  /// Optional install.yaml path the resolver returns. When `null`, the
  /// resolver reports "no manifest found" so the legacy branch fires.
  final String? fakeInstallYamlPath;

  @override
  String getProjectRoot() => fakeProjectRoot;

  @override
  Future<String?> resolveInstallYaml(String pluginName) async {
    return fakeInstallYamlPath;
  }
}

void main() {
  group('PluginInstallCommand — signature DSL', () {
    test('inherits the 4 base flags via ArtisanInstallCommand.baseFlags', () {
      final cmd = PluginInstallCommand();
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

    test('declares its own plugin-specific options on top of the base flags',
        () {
      final cmd = PluginInstallCommand();
      final parsed = cmd.parsedSignature!;
      final optionNames = parsed.options.map((o) => o.name).toSet();

      expect(
        optionNames,
        containsAll(<String>['provider', 'bootstrap-command', 'use-yaml-only']),
      );
    });

    test('extends ArtisanInstallCommand (CommandBoot.none)', () {
      final cmd = PluginInstallCommand();
      expect(cmd, isA<ArtisanInstallCommand>());
      expect(cmd.boot, CommandBoot.none);
    });

    test('pluginName(ctx) derives from the positional name argument', () {
      final cmd = PluginInstallCommand();
      final ctx = _ctxWith(
        const <String, dynamic>{},
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      expect(cmd.pluginName(ctx), 'magic_logger');
    });
  });

  group('PluginInstallCommand — legacy injection (no install.yaml)', () {
    test('appends import + registerProvider line to bin/artisan.dart',
        () async {
      final root = Directory.systemTemp.createTempSync('plinst_legacy_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'magic_logger');

      final cmd = _TestablePluginInstallCommand(fakeProjectRoot: root.path);
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': false,
          'dry-run': false,
          'non-interactive': false,
          'use-yaml-only': false,
          'bootstrap-command': null,
          'provider': null,
        },
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final wrapper =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();
      expect(wrapper, contains("import 'package:magic_logger/cli.dart';"));
      expect(wrapper,
          contains('registry.registerProvider(MagicLoggerArtisanProvider());'));
    });

    test('idempotent re-run leaves the wrapper unchanged when not --force',
        () async {
      final root = Directory.systemTemp.createTempSync('plinst_idem_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'magic_logger');

      final cmd = _TestablePluginInstallCommand(fakeProjectRoot: root.path);
      final opts = <String, dynamic>{
        'force': false,
        'no-bootstrap': false,
        'dry-run': false,
        'non-interactive': false,
        'use-yaml-only': false,
        'bootstrap-command': null,
        'provider': null,
      };

      await cmd.handle(_ctxWith(opts,
          positional: const ['magic_logger'], signature: cmd.parsedSignature));
      final firstSnapshot =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();

      await cmd.handle(_ctxWith(opts,
          positional: const ['magic_logger'], signature: cmd.parsedSignature));
      final secondSnapshot =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();

      expect(secondSnapshot, equals(firstSnapshot),
          reason: 'Second run must be a no-op when force is false.');
    });

    test('--provider override controls the registered class name', () async {
      final root = Directory.systemTemp.createTempSync('plinst_provider_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'magic_logger');

      final cmd = _TestablePluginInstallCommand(fakeProjectRoot: root.path);
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': false,
          'dry-run': false,
          'non-interactive': false,
          'use-yaml-only': false,
          'bootstrap-command': null,
          'provider': 'CustomLoggerProvider',
        },
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      await cmd.handle(ctx);

      final wrapper =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();
      expect(wrapper,
          contains('registry.registerProvider(CustomLoggerProvider());'));
    });

    test('--no-bootstrap skips the bootstrap hint line', () async {
      final root = Directory.systemTemp.createTempSync('plinst_nobootstrap_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'magic_logger');

      final cmd = _TestablePluginInstallCommand(fakeProjectRoot: root.path);
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': true,
          'dry-run': false,
          'non-interactive': false,
          'use-yaml-only': false,
          'bootstrap-command': null,
          'provider': null,
        },
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('Skipping plugin bootstrap'));
      expect(out, isNot(contains('Bootstrap with: artisan')));
    });

    test('errors when plugin missing from pubspec.yaml', () async {
      final root = Directory.systemTemp.createTempSync('plinst_nodep_');
      addTearDown(() => root.deleteSync(recursive: true));
      // Seed everything for "other_plugin" but request install of "magic_logger".
      _seedConsumerProject(root, pluginName: 'other_plugin');

      final cmd = _TestablePluginInstallCommand(fakeProjectRoot: root.path);
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': false,
          'dry-run': false,
          'non-interactive': false,
          'use-yaml-only': false,
          'bootstrap-command': null,
          'provider': null,
        },
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('[ERROR]'));
      expect(out, contains('not listed in pubspec.yaml'));
    });
  });

  group('PluginInstallCommand — install.yaml branch', () {
    test('routes through ManifestInstaller when install.yaml is found',
        () async {
      final root = Directory.systemTemp.createTempSync('plinst_yaml_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'demo_plugin');

      // Provide a minimal install.yaml.
      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      final cmd = _TestablePluginInstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
      );
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': true,
          'dry-run': false,
          'non-interactive': true,
          'use-yaml-only': false,
          'bootstrap-command': null,
          'provider': null,
        },
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      // Minimal manifest has no ops to apply; commit returns Success(0).
      expect(exit, 0);
      final out = (ctx.output as BufferedOutput).content;
      // Reaching this point proves the manifest branch fired (the legacy
      // branch would have appended to bin/artisan.dart; verify it did not).
      final wrapper =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();
      expect(wrapper, isNot(contains("import 'package:demo_plugin/cli.dart';")),
          reason: 'install.yaml branch must NOT do the legacy injection.');
      expect(out, isNot(contains('Skipping plugin bootstrap')),
          reason: 'Legacy bootstrap hint must NOT fire on the manifest path.');
    });

    test('--dry-run flows through to ManifestInstaller without disk writes',
        () async {
      final root = Directory.systemTemp.createTempSync('plinst_dryrun_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'demo_plugin');

      final manifestPath = p.join(root.path, 'demo_install.yaml');
      _writeInstallYaml(manifestPath, 'demo_plugin');

      final cmd = _TestablePluginInstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: manifestPath,
      );
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': true,
          'dry-run': true,
          'non-interactive': true,
          'use-yaml-only': false,
          'bootstrap-command': null,
          'provider': null,
        },
        positional: const ['demo_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // Dry-run never writes the install record.
      final recordPath =
          p.join(root.path, '.artisan', 'installed', 'demo_plugin.json');
      expect(File(recordPath).existsSync(), isFalse);
    });

    test('--use-yaml-only fails when install.yaml is absent', () async {
      final root = Directory.systemTemp.createTempSync('plinst_yamlonly_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'magic_logger');

      final cmd = _TestablePluginInstallCommand(
        fakeProjectRoot: root.path,
        fakeInstallYamlPath: null,
      );
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': false,
          'dry-run': false,
          'non-interactive': false,
          'use-yaml-only': true,
          'bootstrap-command': null,
          'provider': null,
        },
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('[ERROR]'));
      expect(out, contains('install.yaml'));
    });

    test('falls back to legacy injection when install.yaml is not found',
        () async {
      final root = Directory.systemTemp.createTempSync('plinst_fallback_');
      addTearDown(() => root.deleteSync(recursive: true));
      _seedConsumerProject(root, pluginName: 'magic_logger');

      final cmd = _TestablePluginInstallCommand(
        fakeProjectRoot: root.path,
        // No install.yaml → resolver returns null → legacy branch fires.
        fakeInstallYamlPath: null,
      );
      final ctx = _ctxWith(
        const <String, dynamic>{
          'force': false,
          'no-bootstrap': true,
          'dry-run': false,
          'non-interactive': false,
          'use-yaml-only': false,
          'bootstrap-command': null,
          'provider': null,
        },
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // Legacy fallback ran → wrapper got the injection.
      final wrapper =
          File(p.join(root.path, 'bin', 'artisan.dart')).readAsStringSync();
      expect(wrapper, contains("import 'package:magic_logger/cli.dart';"));
      expect(wrapper,
          contains('registry.registerProvider(MagicLoggerArtisanProvider());'));
    });
  });
}
