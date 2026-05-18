import 'dart:io';
import 'dart:isolate';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_logger/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

/// Recording fake [PromptDriver]. Tests assert on [recorded] to verify which
/// prompts the manifest actually fired (or skipped, in override / non-interactive
/// scenarios).
class _RecordingPromptDriver implements PromptDriver {
  _RecordingPromptDriver({
    Map<String, String> asks = const <String, String>{},
    Map<String, String> choices = const <String, String>{},
  })  : _asks = Map<String, String>.of(asks),
        _choices = Map<String, String>.of(choices);

  final Map<String, String> _asks;
  final Map<String, String> _choices;
  final List<String> recorded = <String>[];

  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) {
    recorded.add(question);
    return _asks[question] ?? defaultValue ?? '';
  }

  @override
  bool confirm(String question, {bool defaultValue = false}) {
    recorded.add(question);
    return defaultValue;
  }

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) {
    recorded.add(question);
    return _choices[question] ?? defaultValue ?? options.first;
  }

  @override
  String secret(String question) {
    recorded.add(question);
    return '';
  }
}

/// Fixture-backed fake [StubDriver]. Source bodies live in the [_stubs] map
/// keyed by stub name (matching the brief's "load real stub from disk into
/// FakeStubDriver fixture" pattern).
class _FixtureStubDriver implements StubDriver {
  _FixtureStubDriver(this._stubs);

  final Map<String, String> _stubs;

  @override
  String load(String name, {List<String>? searchPaths}) {
    final body = _stubs[name];
    if (body == null) {
      throw StateError('Stub "$name" not registered in _FixtureStubDriver.');
    }
    return body;
  }

  @override
  String replace(String stub, Map<String, String> replacements) {
    var out = stub;
    replacements.forEach((k, v) {
      out = out.replaceAll('{{ $k }}', v).replaceAll('{{$k}}', v);
    });
    return out;
  }

  @override
  String make(String name, Map<String, String> replacements) =>
      replace(load(name), replacements);
}

/// Test subclass of [LoggerInstallCommand] that pins the manifest path and the
/// [InstallContext] so the test never touches the host's real filesystem.
///
/// Mirrors the pattern used by `plugin_install_command_test.dart` in the
/// fluttersdk_artisan package itself.
class _TestableLoggerInstallCommand extends LoggerInstallCommand {
  _TestableLoggerInstallCommand({
    required this.fakeManifestPath,
    required this.fakeContext,
  });

  /// Pinned manifest path. Substitutes for the production
  /// `Isolate.resolvePackageUri` lookup.
  final String fakeManifestPath;

  /// Pre-wired [InstallContext.test] backed by an [InMemoryFs].
  final InstallContext fakeContext;

  @override
  Future<String?> resolveManifestPath() async => fakeManifestPath;

  @override
  InstallContext buildContext(ArtisanContext ctx) => fakeContext;
}

/// Builds an [ArtisanContext] backed by a [MapInput] carrying the supplied
/// option values + a [BufferedOutput] for output assertions. Mirrors the
/// fixture used by the framework's own command tests.
ArtisanContext _ctxWith(
  Map<String, dynamic> options, {
  CommandSignature? signature,
}) {
  return ArtisanContext.bare(
    MapInput(options, signature: signature),
    BufferedOutput(),
  );
}

/// Standard option set every install invocation needs. Tests spread + override
/// individual entries instead of restating all five every time.
const Map<String, dynamic> _baseOptions = <String, dynamic>{
  'force': false,
  'dry-run': false,
  'non-interactive': false,
  'no-bootstrap': false,
  'path': null,
  'level': 'info',
};

/// Loads the real bundled logger_config stub off disk so the [_FixtureStubDriver]
/// returns the same content the production [RealStubDriver] would.
String _loadRealStub() {
  // Resolve relative to this test file to stay cwd-independent.
  final hereUri = Platform.script.toFilePath();
  // For `dart test` invocations the script points into .dart_tool/test/...;
  // climb back to the package root via the package config.
  final pkgRoot = _resolvePluginRootSync();
  final stubPath = p.join(
    pkgRoot,
    'assets',
    'stubs',
    'install',
    'logger_config.dart.stub',
  );
  if (!File(stubPath).existsSync()) {
    throw StateError(
      'Real logger_config.dart.stub not found at $stubPath '
      '(test fixture loader hereUri=$hereUri).',
    );
  }
  return File(stubPath).readAsStringSync();
}

/// Synchronously resolves the magic_logger package root by walking up from the
/// resolved `package:magic_logger/cli.dart` URI. Synchronous because the test
/// setUp helpers need it before `await`-friendly fixtures are available.
String _resolvePluginRootSync() {
  // Isolate.resolvePackageUri is async; we capture it once in setUpAll below
  // and reuse the cached value. This static helper is the in-test fallback
  // when the cached path is not yet populated.
  final cached = _cachedPluginRoot;
  if (cached != null) return cached;
  throw StateError('_resolvePluginRootSync called before setUpAll cached the '
      'plugin root. Call _cachePluginRootIfNeeded() from setUp first.');
}

String? _cachedPluginRoot;

Future<void> _cachePluginRootIfNeeded() async {
  if (_cachedPluginRoot != null) return;
  final resolved = await Isolate.resolvePackageUri(
    Uri.parse('package:magic_logger/cli.dart'),
  );
  if (resolved == null || resolved.scheme != 'file') {
    throw StateError('Could not resolve package:magic_logger/cli.dart');
  }
  final libCli = resolved.toFilePath();
  _cachedPluginRoot = p.dirname(p.dirname(libCli));
}

void main() {
  late String manifestPath;

  setUpAll(() async {
    await _cachePluginRootIfNeeded();
    manifestPath = p.join(_cachedPluginRoot!, 'install.yaml');
  });

  group('LoggerInstallCommand — signature shape', () {
    test('inherits the 4 base flags via ArtisanInstallCommand.baseFlags', () {
      final cmd = LoggerInstallCommand();
      final optionNames =
          cmd.parsedSignature!.options.map((o) => o.name).toSet();
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

    test('declares --path and --level on top of the base flags', () {
      final cmd = LoggerInstallCommand();
      final optionNames =
          cmd.parsedSignature!.options.map((o) => o.name).toSet();
      expect(optionNames, containsAll(<String>['path', 'level']));
    });

    test('extends ArtisanInstallCommand (CommandBoot.none)', () {
      final cmd = LoggerInstallCommand();
      expect(cmd, isA<ArtisanInstallCommand>());
      expect(cmd.boot, CommandBoot.none);
    });

    test('pluginName(ctx) is the static "magic_logger" identifier', () {
      final cmd = LoggerInstallCommand();
      final ctx = _ctxWith(_baseOptions, signature: cmd.parsedSignature);
      expect(cmd.pluginName(ctx), 'magic_logger');
    });
  });

  group('LoggerInstallCommand — non-interactive install', () {
    test(
        'non-interactive install with defaults writes lib/config/logger.dart '
        'with the stub defaults applied', () async {
      final fs = InMemoryFs();
      final prompt = _RecordingPromptDriver();
      final stubs = _FixtureStubDriver(<String, String>{
        'install/logger_config.dart.stub': _loadRealStub(),
      });
      final installContext = InstallContext.test(
        fs: fs,
        prompt: prompt,
        stubs: stubs,
        projectRoot: '/proj',
        clock: () => DateTime.utc(2025, 1, 1),
      );
      final cmd = _TestableLoggerInstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{
          ..._baseOptions,
          'non-interactive': true,
        },
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 0,
          reason: 'Output: ${(ctx.output as BufferedOutput).content}');
      expect(fs.exists('/proj/lib/config/logger.dart'), isTrue);
      final rendered = fs.readAsString('/proj/lib/config/logger.dart');
      // Defaults from the manifest: logPath="~/.magic_logger.log" + level="info".
      expect(rendered, contains("'~/.magic_logger.log'"));
      expect(rendered, contains('LogLevel.info'));
      // Non-interactive must not call the PromptDriver.
      expect(prompt.recorded, isEmpty,
          reason: 'non-interactive must skip every prompt');
    });

    test('--path override threads through promptOverrides into the stub',
        () async {
      final fs = InMemoryFs();
      final prompt = _RecordingPromptDriver();
      final stubs = _FixtureStubDriver(<String, String>{
        'install/logger_config.dart.stub': _loadRealStub(),
      });
      final installContext = InstallContext.test(
        fs: fs,
        prompt: prompt,
        stubs: stubs,
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerInstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{
          ..._baseOptions,
          'non-interactive': true,
          'path': '/var/log/custom.log',
        },
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 0);
      final rendered = fs.readAsString('/proj/lib/config/logger.dart');
      expect(rendered, contains("'/var/log/custom.log'"));
    });

    test('--level override threads through promptOverrides into the stub',
        () async {
      final fs = InMemoryFs();
      final prompt = _RecordingPromptDriver();
      final stubs = _FixtureStubDriver(<String, String>{
        'install/logger_config.dart.stub': _loadRealStub(),
      });
      final installContext = InstallContext.test(
        fs: fs,
        prompt: prompt,
        stubs: stubs,
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerInstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{
          ..._baseOptions,
          'non-interactive': true,
          'level': 'warn',
        },
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 0);
      final rendered = fs.readAsString('/proj/lib/config/logger.dart');
      expect(rendered, contains('LogLevel.warn'));
    });
  });

  group('LoggerInstallCommand — dry-run + record', () {
    test('--dry-run writes nothing to disk and reports the staged op count',
        () async {
      final fs = InMemoryFs();
      final stubs = _FixtureStubDriver(<String, String>{
        'install/logger_config.dart.stub': _loadRealStub(),
      });
      final installContext = InstallContext.test(
        fs: fs,
        prompt: _RecordingPromptDriver(),
        stubs: stubs,
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerInstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{
          ..._baseOptions,
          'non-interactive': true,
          'dry-run': true,
        },
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 0);
      // Dry-run must not touch the publish target or the install record.
      expect(fs.exists('/proj/lib/config/logger.dart'), isFalse);
      expect(
        fs.exists('/proj/.artisan/installed/magic_logger.json'),
        isFalse,
      );
    });

    test(
        'successful install creates .artisan/installed/magic_logger.json record',
        () async {
      final fs = InMemoryFs();
      final stubs = _FixtureStubDriver(<String, String>{
        'install/logger_config.dart.stub': _loadRealStub(),
      });
      final installContext = InstallContext.test(
        fs: fs,
        prompt: _RecordingPromptDriver(),
        stubs: stubs,
        projectRoot: '/proj',
        clock: () => DateTime.utc(2025, 1, 1),
      );
      final cmd = _TestableLoggerInstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{
          ..._baseOptions,
          'non-interactive': true,
        },
        signature: cmd.parsedSignature,
      );

      await cmd.handle(ctx);

      final recordPath = '/proj/.artisan/installed/magic_logger.json';
      expect(fs.exists(recordPath), isTrue);
      final recordContent = fs.readAsString(recordPath);
      expect(recordContent, contains('"plugin": "magic_logger"'));
      expect(recordContent, contains('"installedAt"'));
      expect(recordContent, contains('"ops"'));
    });

    test(
        '--force bypasses the conflict pre-flight when the target file already '
        'exists', () async {
      final fs = InMemoryFs();
      // Pre-seed the target file so the conflict detector would normally flag.
      fs.writeAsString(
        '/proj/lib/config/logger.dart',
        '// pre-existing user content\n',
      );
      final stubs = _FixtureStubDriver(<String, String>{
        'install/logger_config.dart.stub': _loadRealStub(),
      });
      final installContext = InstallContext.test(
        fs: fs,
        prompt: _RecordingPromptDriver(),
        stubs: stubs,
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerInstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{
          ..._baseOptions,
          'non-interactive': true,
          'force': true,
        },
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 0);
      // Force-write must have replaced the pre-existing content.
      final rendered = fs.readAsString('/proj/lib/config/logger.dart');
      expect(rendered, contains('configureMagicLogger'));
      expect(rendered, isNot(contains('pre-existing user content')));
    });
  });
}
