import 'dart:convert';
import 'dart:isolate';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_logger/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

/// Recording fake [PromptDriver] for confirm-prompt assertions.
class _RecordingPromptDriver implements PromptDriver {
  _RecordingPromptDriver({bool confirmAnswer = false})
      : _confirmAnswer = confirmAnswer;

  final bool _confirmAnswer;
  final List<String> recorded = <String>[];

  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) {
    recorded.add(question);
    return defaultValue ?? '';
  }

  @override
  bool confirm(String question, {bool defaultValue = false}) {
    recorded.add(question);
    return _confirmAnswer;
  }

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) {
    recorded.add(question);
    return defaultValue ?? options.first;
  }

  @override
  String secret(String question) {
    recorded.add(question);
    return '';
  }
}

/// Bare empty stub fixture; uninstall does not call the stub driver, but the
/// [InstallContext.test] constructor still requires one.
class _EmptyStubDriver implements StubDriver {
  const _EmptyStubDriver();

  @override
  String load(String name, {List<String>? searchPaths}) =>
      throw StateError('Uninstall should not load any stub; got "$name".');

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) =>
      throw StateError('Uninstall should not make any stub; got "$name".');
}

/// Test subclass of [LoggerUninstallCommand] that pins the manifest path +
/// install context, mirroring the pattern from `install_command_test.dart`.
class _TestableLoggerUninstallCommand extends LoggerUninstallCommand {
  _TestableLoggerUninstallCommand({
    required this.fakeManifestPath,
    required this.fakeContext,
  });

  final String fakeManifestPath;
  final InstallContext fakeContext;

  @override
  Future<String?> resolveManifestPath() async => fakeManifestPath;

  @override
  InstallContext buildContext(ArtisanContext ctx) => fakeContext;
}

ArtisanContext _ctxWith(
  Map<String, dynamic> options, {
  CommandSignature? signature,
}) {
  return ArtisanContext.bare(
    MapInput(options, signature: signature),
    BufferedOutput(),
  );
}

const Map<String, dynamic> _baseOptions = <String, dynamic>{
  'force': false,
  'dry-run': false,
  'non-interactive': false,
  'no-bootstrap': false,
};

/// Pre-seeds an [InMemoryFs] with the typical post-install state: a published
/// `lib/config/logger.dart` and a matching `.artisan/installed/magic_logger.json`
/// record carrying a single WriteFile op pointing at that file.
void _seedInstalledState(
  InMemoryFs fs, {
  String projectRoot = '/proj',
  String publishedContent = '// rendered config',
}) {
  fs.writeAsString(
    p.join(projectRoot, 'lib', 'config', 'logger.dart'),
    publishedContent,
  );
  final record = <String, dynamic>{
    'plugin': 'magic_logger',
    'installedAt': '2025-01-01T00:00:00.000Z',
    'ops': <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'WriteFile',
        'targetPath': 'lib/config/logger.dart',
        'content': publishedContent,
      },
    ],
    'stubHashes': <String, String>{},
  };
  fs.writeAsString(
    p.join(projectRoot, '.artisan', 'installed', 'magic_logger.json'),
    const JsonEncoder.withIndent('  ').convert(record),
  );
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

  group('LoggerUninstallCommand — signature shape', () {
    test('inherits the 4 base flags via ArtisanInstallCommand.baseFlags', () {
      final cmd = LoggerUninstallCommand();
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

    test('extends ArtisanInstallCommand (CommandBoot.none)', () {
      final cmd = LoggerUninstallCommand();
      expect(cmd, isA<ArtisanInstallCommand>());
      expect(cmd.boot, CommandBoot.none);
    });

    test('pluginName(ctx) is the static "magic_logger" identifier', () {
      final cmd = LoggerUninstallCommand();
      final ctx = _ctxWith(_baseOptions, signature: cmd.parsedSignature);
      expect(cmd.pluginName(ctx), 'magic_logger');
    });
  });

  group('LoggerUninstallCommand — happy path', () {
    test('non-interactive uninstall removes published file + install record',
        () async {
      final fs = InMemoryFs();
      _seedInstalledState(fs);
      final installContext = InstallContext.test(
        fs: fs,
        prompt: _RecordingPromptDriver(),
        stubs: const _EmptyStubDriver(),
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerUninstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{..._baseOptions, 'non-interactive': true},
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 0,
          reason: 'Output: ${(ctx.output as BufferedOutput).content}');
      expect(fs.exists('/proj/lib/config/logger.dart'), isFalse,
          reason: 'Published file must be reversed.');
      expect(
        fs.exists('/proj/.artisan/installed/magic_logger.json'),
        isFalse,
        reason: 'Install record must be deleted on Success.',
      );
    });

    test('--force skips the confirm prompt and uninstalls', () async {
      final fs = InMemoryFs();
      _seedInstalledState(fs);
      final prompt = _RecordingPromptDriver();
      final installContext = InstallContext.test(
        fs: fs,
        prompt: prompt,
        stubs: const _EmptyStubDriver(),
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerUninstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{..._baseOptions, 'force': true},
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      expect(exit, 0);
      expect(prompt.recorded, isEmpty,
          reason: '--force must bypass the confirm prompt entirely.');
      expect(fs.exists('/proj/lib/config/logger.dart'), isFalse);
    });
  });

  group('LoggerUninstallCommand — guard rails', () {
    test('interactive run with "no" confirm exits 0 and leaves state intact',
        () async {
      final fs = InMemoryFs();
      _seedInstalledState(fs);
      final prompt = _RecordingPromptDriver(confirmAnswer: false);
      final installContext = InstallContext.test(
        fs: fs,
        prompt: prompt,
        stubs: const _EmptyStubDriver(),
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerUninstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(_baseOptions, signature: cmd.parsedSignature);

      final exit = await cmd.handle(ctx);

      expect(exit, 0);
      expect(prompt.recorded, hasLength(1),
          reason: 'Confirm prompt must fire exactly once on the interactive '
              'destructive path.');
      // State must remain untouched.
      expect(fs.exists('/proj/lib/config/logger.dart'), isTrue);
      expect(
        fs.exists('/proj/.artisan/installed/magic_logger.json'),
        isTrue,
      );
    });

    test('errors when no install record exists', () async {
      final fs = InMemoryFs();
      // Deliberately do NOT call _seedInstalledState — no record on disk.
      final installContext = InstallContext.test(
        fs: fs,
        prompt: _RecordingPromptDriver(),
        stubs: const _EmptyStubDriver(),
        projectRoot: '/proj',
      );
      final cmd = _TestableLoggerUninstallCommand(
        fakeManifestPath: manifestPath,
        fakeContext: installContext,
      );
      final ctx = _ctxWith(
        <String, dynamic>{..._baseOptions, 'force': true},
        signature: cmd.parsedSignature,
      );

      final exit = await cmd.handle(ctx);

      // ManifestInstaller.uninstall returns Error when the record is missing;
      // _renderResult maps Error → exit code 2.
      expect(exit, 2);
      final out = (ctx.output as BufferedOutput).content;
      expect(out, contains('[ERROR]'));
      expect(out, contains('install record'));
    });
  });
}
