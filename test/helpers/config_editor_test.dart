import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ConfigEditor', () {
    late Directory tempDir;
    late String pubspecPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_cfg_editor_');
      pubspecPath = p.join(tempDir.path, 'pubspec.yaml');
      File(pubspecPath).writeAsStringSync(
        'name: host_app\nversion: 1.0.0\n\ndependencies:\n  meta: ^1.0.0\n',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('addDependencyToPubspec adds a new dependency', () {
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'http',
        version: '^1.0.0',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('http: ^1.0.0'));
    });

    test('addDependencyToPubspec updates an existing dependency', () {
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'meta',
        version: '^1.16.0',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('meta: ^1.16.0'));
    });

    test('addPathDependencyToPubspec writes the path-style dependency', () {
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'local_plugin',
        path: './plugins/local_plugin',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('local_plugin'));
      expect(content, contains('./plugins/local_plugin'));
    });

    test('removeDependencyFromPubspec deletes the entry', () {
      ConfigEditor.removeDependencyFromPubspec(
        pubspecPath: pubspecPath,
        name: 'meta',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, isNot(contains('meta:')));
    });

    test('removeDependencyFromPubspec is a no-op for unknown dependency', () {
      final before = File(pubspecPath).readAsStringSync();

      ConfigEditor.removeDependencyFromPubspec(
        pubspecPath: pubspecPath,
        name: 'not_present',
      );

      expect(File(pubspecPath).readAsStringSync(), before);
    });

    test('updatePubspecValue creates nested keys when missing', () {
      ConfigEditor.updatePubspecValue(
        pubspecPath: pubspecPath,
        keyPath: <String>['environment', 'sdk'],
        value: '>=3.4.0 <4.0.0',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('environment:'));
      expect(content, contains('sdk:'));
    });

    test('addImportToFile injects after existing imports, idempotent', () {
      final dartPath = p.join(tempDir.path, 'main.dart');
      File(dartPath).writeAsStringSync(
        "import 'package:meta/meta.dart';\n\nvoid main() {}\n",
      );

      ConfigEditor.addImportToFile(
        filePath: dartPath,
        importStatement: "import 'package:http/http.dart'",
      );

      var content = File(dartPath).readAsStringSync();
      expect(content, contains("import 'package:http/http.dart';"));

      // Second call is a no-op.
      ConfigEditor.addImportToFile(
        filePath: dartPath,
        importStatement: "import 'package:http/http.dart';",
      );

      content = File(dartPath).readAsStringSync();
      final count = 'http/http.dart'.allMatches(content).length;
      expect(count, 1);
    });

    test('insertCodeBeforePattern / insertCodeAfterPattern', () {
      final filePath = p.join(tempDir.path, 'snippet.dart');
      File(filePath).writeAsStringSync('A\nMARK\nC\n');

      ConfigEditor.insertCodeBeforePattern(
        filePath: filePath,
        pattern: 'MARK',
        code: 'B-before\n',
      );
      ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: 'MARK',
        code: '\nB-after',
      );

      final content = File(filePath).readAsStringSync();
      expect(content, contains('B-before'));
      expect(content, contains('B-after'));
    });

    test('createConfigFile writes content (creating parent dirs)', () {
      final newPath = p.join(tempDir.path, 'nested', 'config.json');

      ConfigEditor.createConfigFile(path: newPath, content: '{"k":1}');

      expect(File(newPath).readAsStringSync(), '{"k":1}');
    });

    test('addDevDependencyToPubspec inserts under dev_dependencies', () {
      ConfigEditor.addDevDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'build_runner',
        version: '^2.4.0',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('dev_dependencies:'));
      expect(content, contains('build_runner: ^2.4.0'));
      // The runtime dependency stays put.
      expect(content, contains('meta: ^1.0.0'));
    });

    test('addDevDependencyToPubspec updates existing entry', () {
      ConfigEditor.addDevDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'build_runner',
        version: '^2.4.0',
      );
      ConfigEditor.addDevDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'build_runner',
        version: '^2.5.0',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('build_runner: ^2.5.0'));
      expect(content, isNot(contains('build_runner: ^2.4.0')));
    });

    test('appendPubspecListEntry creates flutter.assets list when absent', () {
      ConfigEditor.appendPubspecListEntry(
        pubspecPath: pubspecPath,
        keyPath: <String>['flutter', 'assets'],
        value: 'assets/config.json',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('flutter:'));
      expect(content, contains('assets:'));
      expect(content, contains('assets/config.json'));
    });

    test('appendPubspecListEntry preserves existing assets list', () {
      // Pre-populate flutter.assets with one entry. This is the regression
      // test that proves the helper does NOT clobber via updatePubspecValue.
      File(pubspecPath).writeAsStringSync(
        'name: host_app\n'
        'version: 1.0.0\n'
        '\n'
        'flutter:\n'
        '  assets:\n'
        '    - assets/old.json\n',
      );

      ConfigEditor.appendPubspecListEntry(
        pubspecPath: pubspecPath,
        keyPath: <String>['flutter', 'assets'],
        value: 'assets/new.json',
      );

      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('assets/old.json'));
      expect(content, contains('assets/new.json'));
    });

    test('appendPubspecListEntry is idempotent on duplicate value', () {
      File(pubspecPath).writeAsStringSync(
        'name: host_app\n'
        'flutter:\n'
        '  assets:\n'
        '    - assets/x.json\n',
      );
      final before = File(pubspecPath).readAsStringSync();

      ConfigEditor.appendPubspecListEntry(
        pubspecPath: pubspecPath,
        keyPath: <String>['flutter', 'assets'],
        value: 'assets/x.json',
      );

      expect(File(pubspecPath).readAsStringSync(), before);
    });

    test('appendPubspecListEntry throws when target is a non-list scalar', () {
      File(pubspecPath).writeAsStringSync(
        'name: host_app\n'
        'flutter:\n'
        '  assets: not_a_list\n',
      );

      expect(
        () => ConfigEditor.appendPubspecListEntry(
          pubspecPath: pubspecPath,
          keyPath: <String>['flutter', 'assets'],
          value: 'assets/x.json',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
