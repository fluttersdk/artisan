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

class _SilentStubDriver implements StubDriver {
  @override
  String load(String name, {List<String>? searchPaths}) => '';

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) => '';
}

/// Builds an [InstallContext] backed by a real temp dir so dispatcher arms
/// that delegate to dart:io-backed helpers (ConfigEditor / JsonEditor /
/// MainDartEditor) can exercise their real side effects under
/// `projectRoot = tempDir.path`.
InstallContext _ctxFor(Directory tempDir, {VirtualFs? fs}) {
  return InstallContext.test(
    fs: fs ?? const RealFs(),
    prompt: _SilentPromptDriver(),
    stubs: _SilentStubDriver(),
    projectRoot: tempDir.path,
  );
}

void main() {
  group('PluginInstaller — pubspec chain methods (enqueue)', () {
    test('addDependency enqueues AddDependency and returns this', () {
      final tempDir = Directory.systemTemp.createTempSync('plinst_pub_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo');
      final chained = installer.addDependency('intl', '^0.20.0');

      expect(chained, same(installer));
      expect(installer.pendingCount, 1);
      final op = installer.pendingOps.single as AddDependency;
      expect(op.name, 'intl');
      expect(op.version, '^0.20.0');
      expect(op.isDev, isFalse);
    });

    test('addDevDependency enqueues AddDependency with isDev=true', () {
      final tempDir = Directory.systemTemp.createTempSync('plinst_pub_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addDevDependency('build_runner', '^2.4.0');

      final op = installer.pendingOps.single as AddDependency;
      expect(op.isDev, isTrue);
      expect(op.name, 'build_runner');
      expect(op.version, '^2.4.0');
    });

    test('addPathDependency enqueues AddPathDependency', () {
      final tempDir = Directory.systemTemp.createTempSync('plinst_pub_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addPathDependency('local_pkg', '../local_pkg');

      final op = installer.pendingOps.single as AddPathDependency;
      expect(op.name, 'local_pkg');
      expect(op.path, '../local_pkg');
    });

    test('removeDependency enqueues RemoveDependency', () {
      final tempDir = Directory.systemTemp.createTempSync('plinst_pub_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .removeDependency('legacy_pkg');

      final op = installer.pendingOps.single as RemoveDependency;
      expect(op.name, 'legacy_pkg');
    });

    test('addPubspecAsset enqueues AddPubspecAsset', () {
      final tempDir = Directory.systemTemp.createTempSync('plinst_pub_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addPubspecAsset('assets/config.json');

      final op = installer.pendingOps.single as AddPubspecAsset;
      expect(op.assetPath, 'assets/config.json');
    });

    test('pending ops respect insertion order across chained methods', () {
      final tempDir = Directory.systemTemp.createTempSync('plinst_pub_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addDependency('a', '^1.0.0')
          .removeDependency('b')
          .addPubspecAsset('assets/c.json');

      expect(installer.pendingCount, 3);
      expect(installer.pendingOps[0], isA<AddDependency>());
      expect(installer.pendingOps[1], isA<RemoveDependency>());
      expect(installer.pendingOps[2], isA<AddPubspecAsset>());
    });
  });

  group('PluginInstaller — pubspec dispatcher applies ops to real pubspec', () {
    late Directory tempDir;
    late String pubspecPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_pub_disp_');
      pubspecPath = p.join(tempDir.path, 'pubspec.yaml');
      File(pubspecPath).writeAsStringSync(
        'name: host_app\n'
        'version: 1.0.0\n'
        '\n'
        'dependencies:\n'
        '  meta: ^1.0.0\n'
        '\n'
        'flutter:\n'
        '  uses-material-design: true\n'
        '  assets:\n'
        '    - assets/existing.json\n',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('commit applies AddDependency through ConfigEditor', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addDependency('intl', '^0.20.0');

      final result = await installer.commit();

      expect(result, isA<Success>());
      final pubspec = File(pubspecPath).readAsStringSync();
      expect(pubspec, contains('intl: ^0.20.0'));
      expect(pubspec, contains('meta: ^1.0.0'),
          reason: 'existing dependency must be preserved');
    });

    test('commit applies addDevDependency under dev_dependencies', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addDevDependency('build_runner', '^2.4.0');

      final result = await installer.commit();

      expect(result, isA<Success>());
      final pubspec = File(pubspecPath).readAsStringSync();
      expect(pubspec, contains('dev_dependencies:'));
      expect(pubspec, contains('build_runner: ^2.4.0'));
    });

    test('commit applies addPathDependency in path-style', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addPathDependency('local', '../local');

      final result = await installer.commit();

      expect(result, isA<Success>());
      final pubspec = File(pubspecPath).readAsStringSync();
      expect(pubspec, contains('local:'));
      expect(pubspec, contains('path: ../local'));
    });

    test('commit applies removeDependency without touching other entries',
        () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .removeDependency('meta');

      final result = await installer.commit();

      expect(result, isA<Success>());
      final pubspec = File(pubspecPath).readAsStringSync();
      expect(pubspec, isNot(contains('meta: ^1.0.0')));
      expect(pubspec, contains('flutter:'));
    });

    test('commit applies addPubspecAsset by APPENDING — not replacing',
        () async {
      // Regression: ensures the dispatcher uses appendPubspecListEntry, NOT
      // updatePubspecValue (which would wipe the existing entry).
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addPubspecAsset('assets/new.json');

      final result = await installer.commit();

      expect(result, isA<Success>());
      final pubspec = File(pubspecPath).readAsStringSync();
      expect(pubspec, contains('assets/existing.json'),
          reason: 'the original asset must survive the append');
      expect(pubspec, contains('assets/new.json'));
    });

    test('addPubspecAsset is idempotent across two commits on duplicate path',
        () async {
      // Two separate installers (one-shot semantics) writing the same asset.
      await PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addPubspecAsset('assets/dup.json')
          .commit();
      await PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addPubspecAsset('assets/dup.json')
          .commit();

      final pubspec = File(pubspecPath).readAsStringSync();
      final occurrences = 'assets/dup.json'.allMatches(pubspec).length;
      expect(occurrences, 1);
    });
  });
}
