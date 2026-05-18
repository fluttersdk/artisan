import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only driver fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

class _SilentPromptDriver implements PromptDriver {
  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) =>
      defaultValue ?? '';

  @override
  bool confirm(String question, {bool defaultValue = false}) => defaultValue;

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) =>
      defaultValue ?? options.first;

  @override
  String secret(String question) => '';
}

/// In-memory stub driver. Mirrors [StubLoader] behaviour for tests without
/// touching the real `assets/stubs/` directory.
class _MapStubDriver implements StubDriver {
  _MapStubDriver(this._stubs);

  final Map<String, String> _stubs;

  @override
  String load(String name, {List<String>? searchPaths}) {
    final content = _stubs[name];
    if (content == null) {
      throw FileSystemException('Stub not found', name);
    }
    return content;
  }

  @override
  String replace(String stub, Map<String, String> replacements) {
    var rendered = stub;
    replacements.forEach((key, value) {
      // Mirror StubLoader's `{{ key }}` placeholder shape with flexible
      // whitespace.
      rendered =
          rendered.replaceAll(RegExp(r'\{\{\s*' + key + r'\s*\}\}'), value);
    });
    return rendered;
  }

  @override
  String make(String name, Map<String, String> replacements) =>
      replace(load(name), replacements);
}

InstallContext _ctxFor(
  Directory tempDir, {
  Map<String, String> stubs = const <String, String>{},
}) {
  return InstallContext.test(
    fs: const RealFs(),
    prompt: _SilentPromptDriver(),
    stubs: _MapStubDriver(stubs),
    projectRoot: tempDir.path,
  );
}

void main() {
  group('PluginInstaller — file chain methods (enqueue)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_file_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('publishConfig enqueues PublishFile with replacements', () {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').publishConfig(
        stubName: 'install/logger.dart.stub',
        targetPath: 'lib/config/logger.dart',
        replacements: {'PROJECT_ID': 'my-app'},
      );

      final op = installer.pendingOps.single as PublishFile;
      expect(op.sourceStubName, 'install/logger.dart.stub');
      expect(op.targetPath, 'lib/config/logger.dart');
      expect(op.replacements, {'PROJECT_ID': 'my-app'});
    });

    test('writeFile enqueues WriteFile', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .writeFile(targetPath: 'lib/gen.dart', content: 'generated');

      final op = installer.pendingOps.single as WriteFile;
      expect(op.targetPath, 'lib/gen.dart');
      expect(op.content, 'generated');
    });

    test('deleteFile enqueues DeleteFile', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .deleteFile('lib/old.dart');

      final op = installer.pendingOps.single as DeleteFile;
      expect(op.targetPath, 'lib/old.dart');
    });

    test('copyFile enqueues CopyFile', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .copyFile(sourcePath: 'a.dart', targetPath: 'b.dart');

      final op = installer.pendingOps.single as CopyFile;
      expect(op.sourcePath, 'a.dart');
      expect(op.targetPath, 'b.dart');
    });

    test('mergeJson enqueues MergeJson with additive default', () {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').mergeJson(
        targetPath: 'assets/lang/en.json',
        sourceData: const {'auth': 'Login'},
      );

      final op = installer.pendingOps.single as MergeJson;
      expect(op.targetPath, 'assets/lang/en.json');
      expect(op.additive, isTrue);
      expect(op.sourceData, {'auth': 'Login'});
    });
  });

  group('PluginInstaller — file dispatcher applies ops', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_file_disp_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('publishConfig renders stub with replacements and writes target',
        () async {
      final ctx = _ctxFor(tempDir, stubs: {
        'install/cfg.stub': '// hello {{ name }}',
      });
      final installer = PluginInstaller(ctx, pluginName: 'demo').publishConfig(
        stubName: 'install/cfg.stub',
        targetPath: 'lib/config/out.dart',
        replacements: {'name': 'world'},
      );

      final result = await installer.commit();
      expect(result, isA<Success>());
      final out = File(p.join(tempDir.path, 'lib', 'config', 'out.dart'));
      expect(out.readAsStringSync(), '// hello world');
    });

    test('writeFile writes exact content', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .writeFile(targetPath: 'lib/x.dart', content: 'X-content');

      final result = await installer.commit();
      expect(result, isA<Success>());
      final out = File(p.join(tempDir.path, 'lib', 'x.dart'));
      expect(out.readAsStringSync(), 'X-content');
    });

    test('deleteFile removes existing target', () async {
      final target = File(p.join(tempDir.path, 'lib', 'doomed.dart'));
      target.createSync(recursive: true);
      target.writeAsStringSync('rip');

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .deleteFile('lib/doomed.dart');

      final result = await installer.commit();
      expect(result, isA<Success>());
      expect(target.existsSync(), isFalse);
    });

    test('deleteFile is idempotent on missing file', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .deleteFile('lib/never_existed.dart');

      final result = await installer.commit();
      expect(result, isA<Success>());
    });

    test('copyFile copies source to target', () async {
      final src = File(p.join(tempDir.path, 'a.txt'));
      src.writeAsStringSync('source');

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .copyFile(sourcePath: 'a.txt', targetPath: 'b.txt');

      final result = await installer.commit();
      expect(result, isA<Success>());
      final dst = File(p.join(tempDir.path, 'b.txt'));
      expect(dst.readAsStringSync(), 'source');
    });

    test('mergeJson (additive) preserves existing keys + adds new ones',
        () async {
      final target = File(p.join(tempDir.path, 'assets', 'lang', 'en.json'));
      target.createSync(recursive: true);
      target.writeAsStringSync('{"auth":{"login":"Login"}}');

      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').mergeJson(
        targetPath: 'assets/lang/en.json',
        sourceData: const {
          'auth': {'login': 'OVERRIDDEN', 'register': 'Sign up'},
        },
      );

      // Pre-existing target triggers ConflictDetector unmanaged-file; force
      // bypasses (matches plugin-install convention for translation merges).
      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final content = target.readAsStringSync();
      // additive = true → existing values WIN.
      expect(content, contains('"login": "Login"'));
      expect(content, contains('"register": "Sign up"'));
    });

    test('mergeJson (additive=false) overwrites conflicting keys', () async {
      final target = File(p.join(tempDir.path, 'cfg.json'));
      target.writeAsStringSync('{"x":1}');

      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').mergeJson(
        targetPath: 'cfg.json',
        sourceData: const {'x': 99},
        additive: false,
      );

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      expect(target.readAsStringSync(), contains('"x": 99'));
    });

    test('mergeJson creates the target when absent', () async {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').mergeJson(
        targetPath: 'fresh.json',
        sourceData: const {'k': 'v'},
      );

      final result = await installer.commit();
      expect(result, isA<Success>());
      final fresh = File(p.join(tempDir.path, 'fresh.json'));
      expect(fresh.readAsStringSync(), contains('"k": "v"'));
    });

    test('chain returns this through file methods', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo');
      final chained = installer
          .publishConfig(stubName: 'a', targetPath: 'b')
          .writeFile(targetPath: 'c', content: 'd')
          .deleteFile('e')
          .copyFile(sourcePath: 'f', targetPath: 'g')
          .mergeJson(targetPath: 'h', sourceData: const {});
      expect(chained, same(installer));
      expect(installer.pendingCount, 5);
    });
  });
}
