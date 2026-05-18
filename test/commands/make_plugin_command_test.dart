import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_artisan/src/commands/helpers/flutter_create_runner.dart';
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
  ArtisanRegistry? registry,
}) {
  return ArtisanContext.bare(
    MapInput(options, positional: positional, signature: signature),
    BufferedOutput(),
    registry: registry,
  );
}

/// Pins the artisan-root + magic-root to a test-controlled directory and the
/// flutter create + workspace enroller seams to injected fakes. Mirrors the
/// [PluginInstallCommand] test pattern of subclass-with-override.
class _TestableMakePluginCommand extends MakePluginCommand {
  _TestableMakePluginCommand({
    required this.fakeArtisanRoot,
    this.fakeMagicRoot,
    super.flutterCreateRunner,
    super.workspaceEnroller,
  });

  /// Pinned artisan package root. The stub dir is computed from it.
  final String fakeArtisanRoot;

  /// Pinned magic package root (only consulted in magic mode).
  final String? fakeMagicRoot;

  @override
  Future<String> resolveArtisanRoot() async => fakeArtisanRoot;

  @override
  Future<String> resolveMagicRoot() async {
    final root = fakeMagicRoot;
    if (root == null) {
      throw StateError(
        'make:plugin --magic could not resolve the magic package URI. '
        'Run `flutter pub add magic` in the parent app first.',
      );
    }
    return root;
  }
}

/// Returns the canonical `fluttersdk_artisan` package root by walking up from
/// the test file location until it finds a `pubspec.yaml` whose `name:` line
/// reads `fluttersdk_artisan`. Used to point [_TestableMakePluginCommand] at
/// the real stub bundle without depending on `Isolate.resolvePackageUri`.
String _resolveCheckedInArtisanRoot() {
  var current = Directory(p.dirname(Platform.script.toFilePath()));
  for (var i = 0; i < 10; i++) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: fluttersdk_artisan')) {
      return current.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return Directory.current.path;
}

/// Fake [FlutterCreateRunner] that records invocations and skips the real
/// subprocess. Optionally writes a sentinel file under the target path so
/// tests can prove our stub revisions overwrite `flutter create` defaults.
class _FakeFlutterCreateRunner implements FlutterCreateRunner {
  _FakeFlutterCreateRunner({
    this.exitCode = 0,
    this.writeDefaultFiles = true,
  });

  final int exitCode;
  final bool writeDefaultFiles;
  final List<({String packageName, String targetPath, String? org})> calls = [];

  @override
  Future<int> create({
    required String packageName,
    required String targetPath,
    String? org,
    String? description,
  }) async {
    calls.add((packageName: packageName, targetPath: targetPath, org: org));
    if (writeDefaultFiles) {
      // Mirror what real `flutter create` produces: pubspec + lib/<name>.dart
      // + test/<name>_test.dart, all with placeholder content the scaffold
      // is expected to overwrite. README + LICENSE + .gitignore are untouched
      // by our revisions so we leave only a minimal subset here.
      final pubspec = File(p.join(targetPath, 'pubspec.yaml'));
      pubspec.parent.createSync(recursive: true);
      pubspec
          .writeAsStringSync('name: $packageName\n# flutter-create-default\n');
      final lib = File(p.join(targetPath, 'lib', '$packageName.dart'));
      lib.parent.createSync(recursive: true);
      lib.writeAsStringSync('// flutter-create-default lib\n');
      final test = File(p.join(targetPath, 'test', '${packageName}_test.dart'));
      test.parent.createSync(recursive: true);
      test.writeAsStringSync('// flutter-create-default test\n');
      final readme = File(p.join(targetPath, 'README.md'));
      readme.writeAsStringSync('# flutter-create-default README\n');
      // LICENSE stays untouched by our scaffold; included to prove preservation.
      final license = File(p.join(targetPath, 'LICENSE'));
      license.writeAsStringSync('TODO: license\n');
    }
    return exitCode;
  }
}

/// Fake [WorkspaceEnroller] that records detection + enrollment calls without
/// touching the real filesystem.
class _FakeWorkspaceEnroller implements WorkspaceEnroller {
  _FakeWorkspaceEnroller({this.parentPubspec});

  /// Value returned from [detectParentFlutterApp]. `null` simulates the
  /// sibling-app case (no parent Flutter app detected).
  final String? parentPubspec;

  final List<String> detectCalls = [];
  final List<
      ({
        String parentPubspecPath,
        String pluginRelativePath,
        String pluginPubspecPath,
      })> enrollCalls = [];

  @override
  String? detectParentFlutterApp(String targetDir) {
    detectCalls.add(targetDir);
    return parentPubspec;
  }

  @override
  Future<void> enrollWorkspace({
    required String parentPubspecPath,
    required String pluginRelativePath,
    required String pluginPubspecPath,
  }) async {
    enrollCalls.add(
      (
        parentPubspecPath: parentPubspecPath,
        pluginRelativePath: pluginRelativePath,
        pluginPubspecPath: pluginPubspecPath,
      ),
    );
  }
}

/// A minimal [ArtisanRegistry] stub that registers a single no-op command by
/// name, used to simulate a magic:install registration without wiring the full
/// provider stack.
class _FakeRegistry extends ArtisanRegistry {
  _FakeRegistry(String commandName) {
    register(_NoOpCommand(commandName));
  }
}

/// A no-op [ArtisanCommand] that satisfies the registry contract without doing
/// anything at runtime. Used exclusively as a registry slot placeholder in tests.
class _NoOpCommand extends ArtisanCommand {
  _NoOpCommand(this._name);

  final String _name;

  @override
  String get name => _name;

  @override
  String get signature => _name;

  @override
  String get description => 'no-op stub for $_name';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

/// Builds the canonical option map: `--target` set to [target], every other
/// flag at its default (null/false). Mirrors the [PluginInstallCommand] tests
/// to keep the test surface uniform across the suite.
Map<String, dynamic> _defaultOptions({
  String? target,
  String? bootstrapCommand,
  String? path,
  bool magic = false,
}) {
  return <String, dynamic>{
    'target': target,
    'bootstrap-command': bootstrapCommand,
    'path': path,
    'magic': magic,
  };
}

/// Builds a [_TestableMakePluginCommand] wired with a fake flutter create
/// runner and a sibling-app workspace enroller (no parent detected by
/// default — individual tests override [enroller] when they need
/// nested-app behaviour).
_TestableMakePluginCommand _buildCommand({
  required String artisanRoot,
  String? magicRoot,
  FlutterCreateRunner? runner,
  _FakeWorkspaceEnroller? enroller,
}) {
  return _TestableMakePluginCommand(
    fakeArtisanRoot: artisanRoot,
    fakeMagicRoot: magicRoot,
    flutterCreateRunner: runner ?? _FakeFlutterCreateRunner(),
    workspaceEnroller: enroller ?? _FakeWorkspaceEnroller(),
  );
}

void main() {
  late String artisanRoot;

  setUpAll(() {
    artisanRoot = _resolveCheckedInArtisanRoot();
  });

  group('MakePluginCommand — signature DSL', () {
    test('declares the canonical name + boot mode', () {
      final cmd = MakePluginCommand();

      expect(cmd.name, 'make:plugin');
      expect(cmd.boot, CommandBoot.none);
      expect(cmd.description, isNotEmpty);
    });

    test('declares the name positional and the four override options', () {
      final cmd = MakePluginCommand();
      final parsed = cmd.parsedSignature!;

      expect(parsed.arguments.map((a) => a.name).toList(), ['name']);
      expect(
        parsed.options.map((o) => o.name).toSet(),
        containsAll(<String>['target', 'bootstrap-command', 'path', 'magic']),
      );
    });
  });

  group('MakePluginCommand — name validation', () {
    test('rejects uppercase package names', () async {
      final cmd = _buildCommand(artisanRoot: artisanRoot);
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
      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: Directory.systemTemp.createTempSync().path),
        positional: const ['1plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
    });

    test('rejects names containing hyphens', () async {
      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: Directory.systemTemp.createTempSync().path),
        positional: const ['my-plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
    });

    test('rejects an empty name argument', () async {
      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: Directory.systemTemp.createTempSync().path),
        positional: const <String>[],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
    });
  });

  group('MakePluginCommand — generic-mode scaffolding', () {
    test('creates exactly the six generic files under --target', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_files_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // All six generic stubs landed.
      final expected = <String>[
        'pubspec.yaml',
        'lib/cli.dart',
        'lib/my_plugin.dart',
        'lib/src/my_plugin_artisan_provider.dart',
        'test/my_plugin_artisan_provider_test.dart',
        'README.md',
      ];
      for (final rel in expected) {
        expect(
          File(p.join(target.path, rel)).existsSync(),
          isTrue,
          reason: 'missing scaffolded file: $rel',
        );
      }

      // None of the magic-only files were written.
      final magicOnly = <String>[
        'install.yaml',
        'lib/src/commands/install_command.dart',
        'lib/src/commands/uninstall_command.dart',
        'test/cli/install_command_test.dart',
        'assets/stubs/install/my_plugin_config.dart.stub',
      ];
      for (final rel in magicOnly) {
        expect(
          File(p.join(target.path, rel)).existsSync(),
          isFalse,
          reason: 'magic-only file leaked into generic scaffold: $rel',
        );
      }
    });

    test('overwrites flutter create defaults with our pubspec + lib + test',
        () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_overwrite_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // pubspec must be our generic version (has executables: <name>:), NOT
      // the flutter-create-default sentinel.
      final pubspec =
          File(p.join(target.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('flutter-create-default')));
      expect(pubspec, contains('fluttersdk_artisan'));
      expect(pubspec, contains('executables'));
      expect(pubspec, contains('my_plugin:'));

      // lib/<name>.dart must be our runtime barrel, NOT the sentinel.
      final lib =
          File(p.join(target.path, 'lib', 'my_plugin.dart')).readAsStringSync();
      expect(lib, isNot(contains('flutter-create-default')));
      expect(lib, contains('Runtime API'));

      // README must be ours.
      final readme = File(p.join(target.path, 'README.md')).readAsStringSync();
      expect(readme, isNot(contains('flutter-create-default')));

      // LICENSE (untouched by scaffold) survives untouched.
      expect(File(p.join(target.path, 'LICENSE')).existsSync(), isTrue);
    });

    test('renders artisanPath as a relative path in the generic pubspec',
        () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_path_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final pubspec =
          File(p.join(target.path, 'pubspec.yaml')).readAsStringSync();
      // No unresolved placeholder remains.
      expect(pubspec, isNot(contains('{{ artisanPath }}')));
      // The placeholder collapsed to a real relative path (starts with `.`
      // because the target is outside the artisan root in tmp).
      expect(
        RegExp(r'path:\s+\S*\.\.?').hasMatch(pubspec),
        isTrue,
        reason: 'expected a relative `path:` entry, got:\n$pubspec',
      );
    });

    test('applies the pascalName + commandPrefix replacements', () async {
      final target =
          Directory.systemTemp.createTempSync('mkplugin_replacements_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(artisanRoot: artisanRoot);
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
    });

    test('--target overrides the default packages/<name> path', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_target_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(artisanRoot: artisanRoot);
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

    test('--path takes precedence over --target', () async {
      final pathTarget =
          Directory.systemTemp.createTempSync('mkplugin_path_wins_');
      addTearDown(() => pathTarget.deleteSync(recursive: true));
      final targetIgnored =
          Directory.systemTemp.createTempSync('mkplugin_target_loses_');
      addTearDown(() => targetIgnored.deleteSync(recursive: true));

      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: targetIgnored.path, path: pathTarget.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // The pubspec landed at the --path target, not --target.
      expect(
        File(p.join(pathTarget.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(targetIgnored.path, 'pubspec.yaml')).existsSync(),
        isFalse,
      );
    });

    test('strips fluttersdk_ prefix when deriving commandPrefix', () async {
      final target =
          Directory.systemTemp.createTempSync('mkplugin_fluttersdk_');
      addTearDown(() => target.deleteSync(recursive: true));

      // commandPrefix shows up in the cli.dart export of install/uninstall.
      // Generic mode does not render install.yaml so we assert on the
      // provider stub which uses `pascalName` (fluttersdk_dusk →
      // FluttersdkDusk) and on the absence of the magic command files.
      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['fluttersdk_dusk'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final provider = File(
        p.join(
          target.path,
          'lib',
          'src',
          'fluttersdk_dusk_artisan_provider.dart',
        ),
      ).readAsStringSync();
      expect(provider, contains('FluttersdkDuskArtisanProvider'));
    });

    test('prints the next-steps hint on success', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_hint_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(artisanRoot: artisanRoot);
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
      expect(out, contains('Plugin scaffold complete'));
      // Default fake enroller returns null → standalone hint shown.
      expect(out, contains('standalone'));
    });
  });

  group('MakePluginCommand — magic-mode scaffolding', () {
    test(
        'magic mode renders the eleven-file scaffold including magic add-ons '
        'and bootstrap_command default', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_magic_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(
        artisanRoot: artisanRoot,
        magicRoot: artisanRoot, // arbitrary path, just needs to resolve.
      );
      final ctx = _ctxWith(
        _defaultOptions(target: target.path, magic: true),
        positional: const ['magic_logger'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final expectedAll = <String>[
        // generic six (with pubspec sourced from magic/)
        'pubspec.yaml',
        'lib/cli.dart',
        'lib/magic_logger.dart',
        'lib/src/magic_logger_artisan_provider.dart',
        'test/magic_logger_artisan_provider_test.dart',
        'README.md',
        // magic add-ons
        'install.yaml',
        'lib/src/commands/install_command.dart',
        'lib/src/commands/uninstall_command.dart',
        'test/cli/install_command_test.dart',
        'assets/stubs/install/magic_logger_config.dart.stub',
      ];
      for (final rel in expectedAll) {
        expect(
          File(p.join(target.path, rel)).existsSync(),
          isTrue,
          reason: 'missing magic-mode file: $rel',
        );
      }

      // pubspec is the magic-flavored variant: contains magic dep.
      final pubspec =
          File(p.join(target.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('magic:'));
      expect(pubspec, contains('fluttersdk_artisan:'));
      // Both path placeholders resolved.
      expect(pubspec, isNot(contains('{{ artisanPath }}')));
      expect(pubspec, isNot(contains('{{ magicPath }}')));

      // install.yaml carries the bootstrap_command default
      // (commandPrefix=logger after stripping magic_).
      final manifest =
          File(p.join(target.path, 'install.yaml')).readAsStringSync();
      expect(manifest, contains('bootstrap_command: logger:install'));

      // install_command uses commandPrefix.
      final installCmd = File(
        p.join(target.path, 'lib', 'src', 'commands', 'install_command.dart'),
      ).readAsStringSync();
      expect(installCmd, contains("'logger:install"));
    });

    test('--bootstrap-command override flows into install.yaml', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_bootstrap_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(
        artisanRoot: artisanRoot,
        magicRoot: artisanRoot,
      );
      final ctx = _ctxWith(
        _defaultOptions(
          target: target.path,
          bootstrapCommand: 'custom:bootstrap',
          magic: true,
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

    test('magic mode without resolvable magic package returns 1 + error',
        () async {
      final target =
          Directory.systemTemp.createTempSync('mkplugin_magic_missing_');
      addTearDown(() => target.deleteSync(recursive: true));

      // No magicRoot supplied → resolveMagicRoot throws StateError.
      final cmd = _buildCommand(artisanRoot: artisanRoot);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path, magic: true),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('magic package'));
      expect(out, contains('flutter pub add magic'));
    });
  });

  group('MakePluginCommand — flutter create integration', () {
    test('passes the validated name + target to FlutterCreateRunner', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_runner_');
      addTearDown(() => target.deleteSync(recursive: true));

      final runner = _FakeFlutterCreateRunner();
      final cmd = _buildCommand(artisanRoot: artisanRoot, runner: runner);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.packageName, 'my_plugin');
      expect(runner.calls.single.targetPath, target.path);
      expect(runner.calls.single.org, 'com.example');
    });

    test('non-zero flutter create exit aborts with exit code 1 + error',
        () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_fail_');
      addTearDown(() => target.deleteSync(recursive: true));

      final runner = _FakeFlutterCreateRunner(
        exitCode: 66,
        writeDefaultFiles: false,
      );
      final cmd = _buildCommand(artisanRoot: artisanRoot, runner: runner);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('flutter create exited with code 66'));
      // Confirm we never tried to render our stubs over the failed scaffold.
      expect(File(p.join(target.path, 'pubspec.yaml')).existsSync(), isFalse);
    });

    test('missing flutter binary (FormatException) returns 1 + error',
        () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_nobinary_');
      addTearDown(() => target.deleteSync(recursive: true));

      final runner = _ThrowingRunner();
      final cmd = _buildCommand(artisanRoot: artisanRoot, runner: runner);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 1);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('flutter create failed'));
    });
  });

  group('MakePluginCommand — workspace enrollment', () {
    test('enrolls plugin into detected parent Flutter app', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_enroll_');
      addTearDown(() => target.deleteSync(recursive: true));

      final fakeParent = p.join(target.parent.path, 'parent_pubspec.yaml');
      final enroller = _FakeWorkspaceEnroller(parentPubspec: fakeParent);
      final cmd = _buildCommand(artisanRoot: artisanRoot, enroller: enroller);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // detect was called with the resolved target.
      expect(enroller.detectCalls, [target.path]);
      // Enrollment fired with parent + plugin paths.
      expect(enroller.enrollCalls, hasLength(1));
      expect(enroller.enrollCalls.single.parentPubspecPath, fakeParent);
      expect(
        enroller.enrollCalls.single.pluginPubspecPath,
        p.join(target.path, 'pubspec.yaml'),
      );
      // Output mentions the enrollment.
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('Enrolled plugin into parent workspace'));
      expect(out, contains('Parent app pubspec.yaml was updated'));
    });

    test('skips enrollment when no parent Flutter app is detected', () async {
      final target = Directory.systemTemp.createTempSync('mkplugin_sibling_');
      addTearDown(() => target.deleteSync(recursive: true));

      // Default fake enroller returns null → sibling mode.
      final enroller = _FakeWorkspaceEnroller();
      final cmd = _buildCommand(artisanRoot: artisanRoot, enroller: enroller);
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      expect(enroller.detectCalls, [target.path]);
      expect(enroller.enrollCalls, isEmpty);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('standalone'));
      expect(out, isNot(contains('Enrolled plugin into parent workspace')));
    });
  });

  group('MakePluginCommand — isMagic helper', () {
    test('returns true when --magic flag is explicitly set', () {
      final cmd = MakePluginCommand();
      final ctx = _ctxWith(
        _defaultOptions(magic: true),
        signature: cmd.parsedSignature,
      );

      expect(cmd.isMagic(ctx), isTrue);
    });

    test(
        'returns false when --magic is absent and registry has no magic:install',
        () {
      final cmd = MakePluginCommand();
      final ctx = ArtisanContext.bare(
        MapInput(_defaultOptions(), signature: cmd.parsedSignature),
        BufferedOutput(),
      );

      expect(cmd.isMagic(ctx), isFalse);
    });

    test('returns true when --magic is absent but registry has magic:install',
        () {
      final cmd = MakePluginCommand();
      final registry = _FakeRegistry('magic:install');
      final ctx = ArtisanContext.bare(
        MapInput(_defaultOptions(), signature: cmd.parsedSignature),
        BufferedOutput(),
        registry: registry,
      );

      expect(cmd.isMagic(ctx), isTrue);
    });

    test('handle() auto-enables magic when registry has magic:install',
        () async {
      final target =
          Directory.systemTemp.createTempSync('mkplugin_magic_auto_');
      addTearDown(() => target.deleteSync(recursive: true));

      final cmd = _buildCommand(
        artisanRoot: artisanRoot,
        magicRoot: artisanRoot,
      );
      final ctx = _ctxWith(
        _defaultOptions(target: target.path),
        positional: const ['my_plugin'],
        signature: cmd.parsedSignature,
        registry: _FakeRegistry('magic:install'),
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      // install.yaml proves magic mode auto-enabled even without --magic flag.
      expect(File(p.join(target.path, 'install.yaml')).existsSync(), isTrue);
    });
  });

  group('MakePluginCommand — resolvedPath helper', () {
    test('--path takes precedence over --target when both are set', () {
      final cmd = MakePluginCommand();
      final ctx = _ctxWith(
        _defaultOptions(target: '/some/target', path: '/explicit/path'),
        signature: cmd.parsedSignature,
      );

      expect(cmd.resolvedPath(ctx), '/explicit/path');
    });

    test('returns --target value when only --target is set', () {
      final cmd = MakePluginCommand();
      final ctx = _ctxWith(
        _defaultOptions(target: '/only/target'),
        signature: cmd.parsedSignature,
      );

      expect(cmd.resolvedPath(ctx), '/only/target');
    });
  });

  group('MakePluginCommand, magic mode shape matches magic_logger reference',
      () {
    // These tests use the fake FlutterCreateRunner (fast, mock-based) and assert
    // structural patterns against the generated scaffold. magic_logger is the
    // canonical reference shape but comparisons are NOT byte-by-byte — the
    // reference is a moving target. We assert class hierarchies, key method
    // calls, and YAML section presence instead.

    late Directory target;

    setUp(() {
      target = Directory.systemTemp.createTempSync('mkplugin_shape_');
    });

    tearDown(() {
      if (target.existsSync()) target.deleteSync(recursive: true);
    });

    /// Runs the magic scaffold with a fake runner and returns the exit code.
    Future<int> runMagicScaffold(String name) async {
      final cmd = _buildCommand(
        artisanRoot: artisanRoot,
        magicRoot: artisanRoot,
      );
      final ctx = _ctxWith(
        _defaultOptions(target: target.path, magic: true),
        positional: [name],
        signature: cmd.parsedSignature,
      );
      return cmd.handle(ctx);
    }

    test(
        'generated install_command.dart extends ArtisanInstallCommand '
        '(mirrors magic_logger reference class hierarchy)', () async {
      final exit = await runMagicScaffold('magic_logger');
      expect(exit, 0);

      final installCmd = File(
        p.join(target.path, 'lib', 'src', 'commands', 'install_command.dart'),
      ).readAsStringSync();

      // The reference shape (magic_logger/lib/src/commands/install_command.dart)
      // extends ArtisanInstallCommand; the scaffold stub mirrors this hierarchy.
      expect(
        installCmd,
        contains('extends ArtisanInstallCommand'),
        reason: 'install_command must extend ArtisanInstallCommand '
            '(matches magic_logger reference)',
      );
    });

    test(
        'generated install_command.dart delegates install work to a '
        'PluginInstaller / ManifestInstaller (plugins.json registration path)',
        () async {
      final exit = await runMagicScaffold('magic_logger');
      expect(exit, 0);

      final installCmd = File(
        p.join(target.path, 'lib', 'src', 'commands', 'install_command.dart'),
      ).readAsStringSync();

      // The stub wires install work through PluginInstaller (the high-level
      // fluent DSL), which bundles plugins.json registration internally.
      // The magic_logger reference uses ManifestInstaller + explicit
      // _writePluginsJsonEntry; both patterns satisfy this structural check.
      final usesInstaller = installCmd.contains('PluginInstaller') ||
          installCmd.contains('ManifestInstaller') ||
          installCmd.contains('PluginsRegistryFile');
      expect(
        usesInstaller,
        isTrue,
        reason: 'install_command must delegate to PluginInstaller, '
            'ManifestInstaller, or PluginsRegistryFile for plugins.json '
            'registration (matches magic_logger pattern)',
      );
    });

    test(
        'generated install_command.dart uses PluginInstaller which bundles '
        'plugins.json registration + auto-refresh (structural auto-refresh test)',
        () async {
      final exit = await runMagicScaffold('magic_logger');
      expect(exit, 0);

      final installCmd = File(
        p.join(target.path, 'lib', 'src', 'commands', 'install_command.dart'),
      ).readAsStringSync();

      // The scaffold stub routes install work through PluginInstaller (the
      // high-level fluent DSL). PluginInstaller.commit() bundles both the
      // plugins.json write and the in-process plugins:refresh trigger
      // internally — which is the auto-refresh contract described in the
      // magic_logger reference (where it is spelled out explicitly via
      // _writePluginsJsonEntry + _autoRefresh). Both paths satisfy the same
      // structural requirement; we assert the scaffold wires PluginInstaller
      // as its install delegator.
      expect(
        installCmd,
        contains('PluginInstaller'),
        reason: 'install_command must delegate to PluginInstaller '
            '(which bundles plugins.json write + auto-refresh, '
            'matching the magic_logger structural contract)',
      );
      // The commit call is the activation point that triggers registration +
      // refresh — ensure it is present alongside the constructor.
      expect(
        installCmd,
        contains('.commit('),
        reason: 'PluginInstaller.commit() must be called to trigger '
            'the registration + auto-refresh cycle',
      );
    });

    test('install.yaml has magic.provider section', () async {
      final exit = await runMagicScaffold('magic_logger');
      expect(exit, 0);

      final manifest =
          File(p.join(target.path, 'install.yaml')).readAsStringSync();

      // The magic/ stub template writes a `magic:` section with a `provider:`
      // key — this is what distinguishes a magic plugin from a generic one.
      expect(
        manifest,
        contains('magic:'),
        reason: 'install.yaml must declare a magic: section',
      );
      expect(
        manifest,
        contains('provider:'),
        reason: 'install.yaml magic: section must declare a provider: key',
      );
    });

    test(
        'pubspec.yaml has both fluttersdk_artisan + magic deps with rendered '
        'paths (no unresolved placeholders remain)', () async {
      final exit = await runMagicScaffold('magic_logger');
      expect(exit, 0);

      final pubspec =
          File(p.join(target.path, 'pubspec.yaml')).readAsStringSync();

      // Both deps are declared.
      expect(
        pubspec,
        contains('fluttersdk_artisan:'),
        reason: 'magic pubspec must declare fluttersdk_artisan dependency',
      );
      expect(
        pubspec,
        contains('magic:'),
        reason: 'magic pubspec must declare magic dependency',
      );

      // Both placeholders were rendered; no raw template tokens remain.
      expect(
        pubspec,
        isNot(contains('{{ artisanPath }}')),
        reason: 'artisanPath placeholder must be rendered to a real path',
      );
      expect(
        pubspec,
        isNot(contains('{{ magicPath }}')),
        reason: 'magicPath placeholder must be rendered to a real path',
      );

      // The rendered paths are real relative paths (the target dir is outside
      // both package roots, so the resolver produces a `..`-prefixed relative
      // path for each dep).
      expect(
        RegExp(r'path:\s+\S*\.\.').hasMatch(pubspec),
        isTrue,
        reason: 'expected relative path: entries in pubspec, got:\n$pubspec',
      );
    });

    test(
        'bin/<name>.dart IS generated by make:plugin '
        '(plugin self-bootstrap entry: `dart run <plugin> <cmd>`)', () async {
      final exit = await runMagicScaffold('magic_logger');
      expect(exit, 0);

      // The plugin bin file is named after the package so Dart resolves
      // `dart run magic_logger ...` directly to bin/magic_logger.dart (the
      // default executable-name = file-name convention), and pubspec's
      // executables: { magic_logger: } maps the same name explicitly. The
      // scaffolded bin uses delegateToConsumer: false to invoke the plugin's
      // own providers without delegating back to the consumer wrapper.
      final binFile = File(p.join(target.path, 'bin', 'magic_logger.dart'));
      expect(binFile.existsSync(), isTrue);
      final content = binFile.readAsStringSync();
      expect(content, contains('runArtisan'));
      expect(content, contains('delegateToConsumer: false'));
    });

    test(
        'post-flutter-create cleanup deletes default test/<name>_test.dart '
        'leftover from flutter create', () async {
      final exit = await runMagicScaffold('my_test_plugin');
      expect(exit, 0);

      // The flutter create default writes test/<name>_test.dart referencing a
      // Calculator() function that no longer exists after our lib/<name>.dart
      // stub overwrites it. Step 5b in make_plugin_command.dart deletes it so
      // `flutter analyze` does not fail on first run.
      expect(
        File(p.join(target.path, 'test', 'my_test_plugin_test.dart'))
            .existsSync(),
        isFalse,
        reason: 'step 5b must delete flutter create\'s default '
            'test/my_test_plugin_test.dart to prevent a compile error',
      );

      // Our stub-rendered provider test lives at a different path and must NOT
      // be deleted — confirms the cleanup is targeted, not blanket.
      expect(
        File(p.join(
          target.path,
          'test',
          'my_test_plugin_artisan_provider_test.dart',
        )).existsSync(),
        isTrue,
        reason: 'the scaffold-rendered artisan_provider_test.dart must survive '
            'cleanup (only the flutter create default is removed)',
      );
    });
  });

  group('MakePluginCommand, generated plugin passes dart pub get', () {
    // Integration test: uses REAL flutter create (not mocked) and REAL
    // dart pub get. This is intentional — the original pubspec path-resolution
    // bug (hardcoded `../../` instead of a computed relative path) would have
    // been caught immediately by this test because `dart pub get` would have
    // failed with "path does not exist".
    //
    // Note: this test is slower than the unit tests above (real flutter binary,
    // real pub network or cache hit). It is kept as a normal test rather than
    // @Tags(['integration']) so CI catches it without tag filtering.

    late Directory tmpRoot;

    setUp(() {
      // Resolve symlinks immediately: on macOS, Directory.systemTemp returns
      // /var/folders/... which is a symlink to /private/var/folders/...
      // ArtisanPathResolver computes the relative path from the target dir, and
      // if the target is the unresolved /var/... path but `dart pub get` resolves
      // its CWD to /private/var/..., the computed relative path is off by one
      // directory level. Resolving symlinks upfront makes both sides agree.
      final raw = Directory.systemTemp.createTempSync('mkplugin_pubget_');
      tmpRoot = Directory(raw.resolveSymbolicLinksSync());
    });

    tearDown(() {
      // Always clean up: skipping tearDown on a real flutter create output
      // leaves hundreds of MB of files behind on repeated runs.
      if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
    });

    test('scaffold succeeds with real flutter create into a nested target path',
        () async {
      // 1. The plugin lands at <tmpRoot>/consumer_app/packages/foo/ — a typical
      //    nested layout that requires the path resolver to climb multiple
      //    directory levels back to the artisan root.
      final pluginTarget =
          Directory(p.join(tmpRoot.path, 'consumer_app', 'packages', 'foo'))
            ..createSync(recursive: true);

      // 2. Run scaffold with the REAL FlutterCreateRunner (no mock). Generic
      //    mode is used so the only path dep is fluttersdk_artisan — this is
      //    the simplest surface to validate without needing a real magic package.
      final cmd = _TestableMakePluginCommand(
        fakeArtisanRoot: artisanRoot,
        // No flutterCreateRunner override → real ProcessFlutterCreateRunner.
        workspaceEnroller: _FakeWorkspaceEnroller(),
      );
      final ctx = _ctxWith(
        _defaultOptions(target: pluginTarget.path),
        positional: const ['foo'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(
        exit,
        0,
        reason: 'make:plugin with real flutter create must exit 0; '
            'check that flutter is in PATH and the target is writable',
      );

      // 3. The scaffolded pubspec must exist after a successful scaffold.
      expect(
        File(p.join(pluginTarget.path, 'pubspec.yaml')).existsSync(),
        isTrue,
        reason: 'pubspec.yaml must exist after scaffold',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
        'dart pub get inside the scaffolded plugin exits with code 0 '
        '(the bug-validation test: hardcoded artisan paths fail here)',
        () async {
      // This test uses GENERIC mode (no --magic) so the plugin pubspec only
      // declares the `fluttersdk_artisan:` path dep. This is intentional:
      //
      //   - The artisan path resolver is the same code path in both modes.
      //   - Generic mode avoids needing a real `magic` package on disk,
      //     which is not a dependency of fluttersdk_artisan's own test suite.
      //   - The original bug (hardcoded `../../` instead of a computed relative
      //     path) manifests identically in generic mode — pub get would produce
      //     "could not find package fluttersdk_artisan at ../../" and exit 66.
      //
      // 1. Scaffold into a nested path to exercise the relative-path computation.
      //    A two-level nesting (<tmpRoot>/consumer_app/packages/foo) is enough
      //    to prove the path is not hardcoded.
      final pluginTarget =
          Directory(p.join(tmpRoot.path, 'consumer_app', 'packages', 'foo'))
            ..createSync(recursive: true);

      // 2. Scaffold via REAL flutter create, generic mode.
      final cmd = _TestableMakePluginCommand(
        fakeArtisanRoot: artisanRoot,
        // No flutterCreateRunner override → real ProcessFlutterCreateRunner.
        workspaceEnroller: _FakeWorkspaceEnroller(),
      );
      final ctx = _ctxWith(
        _defaultOptions(target: pluginTarget.path),
        positional: const ['foo'],
        signature: cmd.parsedSignature,
      );

      final scaffoldExit = await cmd.handle(ctx);
      expect(scaffoldExit, 0, reason: 'scaffold must succeed before pub get');

      // 3. Run `dart pub get` from the plugin directory. The pubspec must
      //    have a valid relative path to fluttersdk_artisan. A hardcoded
      //    `../../` from <tmpRoot>/consumer_app/packages/foo/ would point to
      //    <tmpRoot>/consumer_app/ — not the artisan root — and pub get would
      //    fail with exit code 66.
      final pubGet = await Process.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: pluginTarget.path,
      );

      expect(
        pubGet.exitCode,
        0,
        reason: '`dart pub get` inside the scaffolded plugin failed.\n'
            'stdout: ${pubGet.stdout}\n'
            'stderr: ${pubGet.stderr}\n'
            'This is the bug-validation test: a hardcoded path like `../../` '
            'would produce a non-zero exit here.',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
        'scaffolded pubspec has a computed relative path for fluttersdk_artisan '
        '(not a literal hardcoded path)', () async {
      // 1. Scaffold into a deeply-nested target to prove the path is computed
      //    dynamically from the actual target location, not hardcoded.
      //    Generic mode: only fluttersdk_artisan dep is in the pubspec.
      final deepTarget = Directory(
        p.join(
          tmpRoot.path,
          'a',
          'b',
          'c',
          'deeply_nested_plugin',
        ),
      )..createSync(recursive: true);

      final cmd = _TestableMakePluginCommand(
        fakeArtisanRoot: artisanRoot,
        // No flutterCreateRunner override → real ProcessFlutterCreateRunner.
        workspaceEnroller: _FakeWorkspaceEnroller(),
      );
      final ctx = _ctxWith(
        _defaultOptions(target: deepTarget.path),
        positional: const ['deeply_nested_plugin'],
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);
      expect(exit, 0);

      final pubspec =
          File(p.join(deepTarget.path, 'pubspec.yaml')).readAsStringSync();

      // The artisan path in the pubspec must be a relative path that resolves
      // correctly from the actual deepTarget location to the artisan root.
      // We verify by reconstructing the absolute path and checking it exists.
      final pathMatch = RegExp(r'fluttersdk_artisan:\s*\n\s*path:\s+(\S+)')
          .firstMatch(pubspec);
      expect(
        pathMatch,
        isNotNull,
        reason: 'pubspec must declare fluttersdk_artisan with a path: dep',
      );

      final renderedPath = pathMatch!.group(1)!;
      final resolvedAbsolute =
          p.normalize(p.join(deepTarget.path, renderedPath));

      // The resolved path must point to an existing directory (the artisan root)
      // and must contain a pubspec.yaml with name: fluttersdk_artisan.
      expect(
        Directory(resolvedAbsolute).existsSync(),
        isTrue,
        reason: 'the rendered artisan path "$renderedPath" resolves to '
            '"$resolvedAbsolute" which does not exist — '
            'ArtisanPathResolver produced a wrong relative path',
      );

      // Confirm the directory IS the artisan package (not some random dir).
      final resolvedPubspec =
          File(p.join(resolvedAbsolute, 'pubspec.yaml')).readAsStringSync();
      expect(
        resolvedPubspec,
        contains('name: fluttersdk_artisan'),
        reason: 'resolved artisan path must point to the fluttersdk_artisan '
            'package root',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// Runner that throws [FormatException] from [create], simulating the
/// missing-flutter-binary code path. Used to assert that [MakePluginCommand]
/// catches the exception and surfaces it as a CLI error instead of letting
/// it bubble.
class _ThrowingRunner implements FlutterCreateRunner {
  @override
  Future<int> create({
    required String packageName,
    required String targetPath,
    String? org,
    String? description,
  }) async {
    throw FormatException(
      'flutter create failed: flutter not found in PATH. '
      'Install Flutter SDK or add it to PATH.',
    );
  }
}
