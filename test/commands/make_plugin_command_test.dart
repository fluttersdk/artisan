import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Builds an [ArtisanContext] backed by [MapInput] + [BufferedOutput]. Mirrors
/// the test pattern from `plugin_install_command_test.dart` so option lookups
/// resolve through the same signature-parsing path as production.
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

/// Pins the stub directory to the package's checked-in `assets/stubs/make_plugin/`
/// so tests do not depend on `Isolate.resolvePackageUri` (which requires a
/// pub-resolved package_config.json that may point elsewhere in CI).
///
/// Mirrors the [PluginInstallCommand] test pattern of subclass-with-override.
class _TestableMakePluginCommand extends MakePluginCommand {
  _TestableMakePluginCommand({required this.fakeStubDir});

  /// Pinned stub directory; production resolves via [Isolate.resolvePackageUri].
  final String fakeStubDir;

  @override
  Future<String> resolveStubDir() async => fakeStubDir;
}

/// Returns the canonical `assets/stubs/make_plugin/` directory inside the
/// `fluttersdk_artisan` checkout. Walks up from the test file location until
/// it finds a `pubspec.yaml` whose `name:` line reads `fluttersdk_artisan`.
String _resolveCheckedInStubsDir() {
  var current = Directory(p.dirname(Platform.script.toFilePath()));
  for (var i = 0; i < 10; i++) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: fluttersdk_artisan')) {
      return p.join(current.path, 'assets', 'stubs', 'make_plugin');
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  // Fallback: cwd-relative path. Works when the test runner sets cwd to the
  // package root (the default `dart test` behaviour).
  return p.join(Directory.current.path, 'assets', 'stubs', 'make_plugin');
}

/// Builds the canonical option map: `--target` set to [target], every other
/// flag at its default (null/false). Mirrors the [PluginInstallCommand] tests
/// to keep the test surface uniform across the suite.
Map<String, dynamic> _defaultOptions({
  String? target,
  String? bootstrapCommand,
}) {
  return <String, dynamic>{
    'target': target,
    'bootstrap-command': bootstrapCommand,
  };
}

void main() {
  late String stubsDir;

  setUpAll(() {
    stubsDir = _resolveCheckedInStubsDir();
  });

  group('MakePluginCommand — signature DSL', () {
    test('declares the canonical name + boot mode', () {
      final cmd = MakePluginCommand();

      expect(cmd.name, 'make:plugin');
      expect(cmd.boot, CommandBoot.none);
      expect(cmd.description, isNotEmpty);
    });

    test('declares the name positional and the two override options', () {
      final cmd = MakePluginCommand();
      final parsed = cmd.parsedSignature!;

      expect(parsed.arguments.map((a) => a.name).toList(), ['name']);
      expect(
        parsed.options.map((o) => o.name).toSet(),
        containsAll(<String>['target', 'bootstrap-command']),
      );
    });
  });

  group('MakePluginCommand — name validation', () {
    test('rejects uppercase package names', () async {
      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: Directory.systemTemp.createTempSync().path),
        positional: const ['BadName'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('[ERROR]'));
      expect(out, contains('snake_case'));
    });

    test('rejects names starting with a digit', () async {
      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: Directory.systemTemp.createTempSync().path),
        positional: const ['1plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
    });

    test('rejects names containing hyphens', () async {
      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: Directory.systemTemp.createTempSync().path),
        positional: const ['my-plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
    });

    test('rejects an empty name argument', () async {
      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: Directory.systemTemp.createTempSync().path),
        positional: const <String>[],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
    });
  });

  group('MakePluginCommand — scaffolding', () {
    test('creates every expected file under --target', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_files_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final expected = <String>[
        'pubspec.yaml',
        'lib/cli.dart',
        'lib/my_plugin.dart',
        'lib/src/my_plugin_artisan_provider.dart',
        'lib/src/commands/install_command.dart',
        'lib/src/commands/uninstall_command.dart',
        'install.yaml',
        'assets/stubs/install/my_plugin_config.dart.stub',
        'test/my_plugin_artisan_provider_test.dart',
        'test/cli/install_command_test.dart',
        'README.md',
      ];

      for (final rel in expected) {
        expect(
          File(p.join(target.path, rel)).existsSync(),
          isTrue,
          reason: 'missing scaffolded file: $rel',
        );
      }
    });

    test('applies the pascalName + commandPrefix replacements', () async {
      final target =
          Directory.systemTemp.createTempSync('mkplugin_replacements_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // pascalName lands in the provider class declaration.
      final provider = File(
        p.join(target.path, 'lib', 'src', 'magic_logger_artisan_provider.dart'),
      ).readAsStringSync();
      expect(provider, contains('class MagicLoggerArtisanProvider'));

      // commandPrefix strips the `magic_` prefix → `logger`.
      final installCmd = File(
        p.join(target.path, 'lib', 'src', 'commands', 'install_command.dart'),
      ).readAsStringSync();
      expect(installCmd, contains("'logger:install"));

      // bootstrap_command default = <commandPrefix>:install.
      final manifest =
          File(p.join(target.path, 'install.yaml')).readAsStringSync();
      expect(manifest, contains('bootstrap_command: logger:install'));
    });

    test('--target overrides the default packages/<name> path', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_target_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // pubspec landed under the explicit target, NOT under packages/my_plugin.
      expect(
        File(p.join(target.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
    });

    test('--bootstrap-command override flows into install.yaml', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_bootstrap_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(
          target: target.path,
          bootstrapCommand: 'custom:bootstrap',
        ),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final manifest =
          File(p.join(target.path, 'install.yaml')).readAsStringSync();
      expect(manifest, contains('bootstrap_command: custom:bootstrap'));
    });

    test('strips fluttersdk_ prefix when deriving commandPrefix', () async {
      final target =
          Directory.systemTemp.createTempSync('mkplugin_fluttersdk_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['fluttersdk_dusk'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final manifest =
          File(p.join(target.path, 'install.yaml')).readAsStringSync();
      expect(manifest, contains('bootstrap_command: dusk:install'));
    });

    test('prints the next-steps hint on success', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_hint_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _TestableMakePluginCommand(fakeStubDir: stubsDir);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('dart pub get'));
      expect(out, contains('dart test'));
      expect(out, contains(target.path));
    });
  });
}
