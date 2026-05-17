import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:magic_cli/src/helpers/config_editor.dart';
import 'package:magic_cli/src/helpers/file_helper.dart';

/// Minimal valid pubspec.yaml content for use in tests.
const String _kMinimalPubspec = '''
name: test_project
description: A test project.

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
''';

/// Pubspec without a dependencies section.
const String _kNoDependenciesPubspec = '''
name: test_project
description: A test project.

environment:
  sdk: ">=3.4.0 <4.0.0"
''';

/// Safety-net tests for [ConfigEditor] public API.
///
/// All file-system operations use isolated temp directories that are
/// removed in tearDown.
void main() {
  group('ConfigEditor.addDependencyToPubspec()', () {
    late Directory tempDir;
    late String pubspecPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_add_dep_');
      pubspecPath = path.join(tempDir.path, 'pubspec.yaml');
      File(pubspecPath).writeAsStringSync(_kMinimalPubspec);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('adds a new version dependency', () {
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'http',
        version: '^1.0.0',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('http'));
      expect(content, contains('^1.0.0'));
    });

    test('updates an existing dependency version', () {
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'http',
        version: '^0.9.0',
      );
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'http',
        version: '^1.1.0',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('^1.1.0'));
      expect(content, isNot(contains('^0.9.0')));
    });

    // NOTE: addDependencyToPubspec does NOT handle the case where the
    // 'dependencies' key is completely absent in the YAML — it throws a
    // PathError from yaml_edit. This is a known limitation. The path-based
    // variant (addPathDependencyToPubspec) handles this correctly via try/catch.
    test('throws when dependencies section does not exist', () {
      File(pubspecPath).writeAsStringSync(_kNoDependenciesPubspec);
      expect(
        () => ConfigEditor.addDependencyToPubspec(
          pubspecPath: pubspecPath,
          name: 'yaml',
          version: '^3.0.0',
        ),
        throwsA(anything),
      );
    });

    test('adds multiple different dependencies', () {
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'package_a',
        version: '^1.0.0',
      );
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'package_b',
        version: '^2.0.0',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('package_a'));
      expect(content, contains('package_b'));
    });
  });

  group('ConfigEditor.addPathDependencyToPubspec()', () {
    late Directory tempDir;
    late String pubspecPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_path_dep_');
      pubspecPath = path.join(tempDir.path, 'pubspec.yaml');
      File(pubspecPath).writeAsStringSync(_kMinimalPubspec);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('adds a path-based dependency', () {
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'my_plugin',
        path: './plugins/my_plugin',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('my_plugin'));
      expect(content, contains('./plugins/my_plugin'));
    });

    test('adds a path dependency when dependencies section is absent', () {
      File(pubspecPath).writeAsStringSync(_kNoDependenciesPubspec);
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'local_lib',
        path: '../local_lib',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('local_lib'));
      expect(content, contains('../local_lib'));
    });

    test('updates existing path dependency', () {
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'my_plugin',
        path: './old_path',
      );
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'my_plugin',
        path: './new_path',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('./new_path'));
    });
  });

  group('ConfigEditor.removeDependencyFromPubspec()', () {
    late Directory tempDir;
    late String pubspecPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_remove_dep_');
      pubspecPath = path.join(tempDir.path, 'pubspec.yaml');
      File(pubspecPath).writeAsStringSync(_kMinimalPubspec);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('removes an existing dependency', () {
      // 1. Add a dependency first.
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'http',
        version: '^1.0.0',
      );

      // 2. Remove it.
      ConfigEditor.removeDependencyFromPubspec(
        pubspecPath: pubspecPath,
        name: 'http',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, isNot(contains('http: ^1.0.0')));
    });

    test('does nothing when dependency does not exist', () {
      final before = File(pubspecPath).readAsStringSync();
      ConfigEditor.removeDependencyFromPubspec(
        pubspecPath: pubspecPath,
        name: 'nonexistent_pkg',
      );
      final after = File(pubspecPath).readAsStringSync();
      expect(after, equals(before));
    });

    test('does nothing when dependencies section does not exist', () {
      File(pubspecPath).writeAsStringSync(_kNoDependenciesPubspec);
      expect(
        () => ConfigEditor.removeDependencyFromPubspec(
          pubspecPath: pubspecPath,
          name: 'http',
        ),
        returnsNormally,
      );
    });
  });

  group('ConfigEditor.updatePubspecValue()', () {
    late Directory tempDir;
    late String pubspecPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_update_val_');
      pubspecPath = path.join(tempDir.path, 'pubspec.yaml');
      File(pubspecPath).writeAsStringSync(_kMinimalPubspec);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('updates a top-level key', () {
      ConfigEditor.updatePubspecValue(
        pubspecPath: pubspecPath,
        keyPath: ['version'],
        value: '2.0.0',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('version'));
      expect(content, contains('2.0.0'));
    });

    test('updates a nested key path', () {
      ConfigEditor.updatePubspecValue(
        pubspecPath: pubspecPath,
        keyPath: ['environment', 'sdk'],
        value: '>=3.5.0 <4.0.0',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('>=3.5.0 <4.0.0'));
    });

    test('creates missing nested keys', () {
      ConfigEditor.updatePubspecValue(
        pubspecPath: pubspecPath,
        keyPath: ['new_section', 'new_key'],
        value: 'new_value',
      );
      final content = File(pubspecPath).readAsStringSync();
      expect(content, contains('new_section'));
      expect(content, contains('new_key'));
      expect(content, contains('new_value'));
    });
  });

  group('ConfigEditor.addImportToFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_add_import_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('adds an import to a file with no existing imports', () {
      final filePath = path.join(tempDir.path, 'main.dart');
      File(filePath).writeAsStringSync("void main() {}\n");
      ConfigEditor.addImportToFile(
        filePath: filePath,
        importStatement: "import 'dart:io';",
      );
      final content = File(filePath).readAsStringSync();
      expect(content, contains("import 'dart:io';"));
    });

    test('adds an import after existing imports', () {
      final filePath = path.join(tempDir.path, 'widget.dart');
      File(filePath).writeAsStringSync(
        "import 'package:flutter/material.dart';\n\nvoid main() {}\n",
      );
      ConfigEditor.addImportToFile(
        filePath: filePath,
        importStatement: "import 'dart:io';",
      );
      final content = File(filePath).readAsStringSync();
      expect(content, contains("import 'dart:io';"));
      expect(content, contains("import 'package:flutter/material.dart';"));
    });

    test('does not add duplicate import', () {
      final filePath = path.join(tempDir.path, 'no_dup.dart');
      File(filePath).writeAsStringSync(
        "import 'dart:io';\n\nvoid main() {}\n",
      );
      ConfigEditor.addImportToFile(
        filePath: filePath,
        importStatement: "import 'dart:io';",
      );
      final content = File(filePath).readAsStringSync();
      final occurrences = "import 'dart:io';".allMatches(content).length;
      expect(occurrences, equals(1));
    });

    test('automatically adds missing semicolon to import statement', () {
      final filePath = path.join(tempDir.path, 'semi.dart');
      File(filePath).writeAsStringSync("void main() {}\n");
      ConfigEditor.addImportToFile(
        filePath: filePath,
        importStatement: "import 'dart:io'",
      );
      final content = File(filePath).readAsStringSync();
      expect(content, contains("import 'dart:io';"));
    });
  });

  group('ConfigEditor.insertCodeBeforePattern()', () {
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('magic_test_before_pattern_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('inserts code before the matched string pattern', () {
      final filePath = path.join(tempDir.path, 'code.dart');
      File(filePath).writeAsStringSync('runApp(MyApp());\n');
      ConfigEditor.insertCodeBeforePattern(
        filePath: filePath,
        pattern: 'runApp',
        code: 'initializeApp();\n',
      );
      final content = File(filePath).readAsStringSync();
      expect(content.indexOf('initializeApp'),
          lessThan(content.indexOf('runApp')));
    });

    test('inserts code before a RegExp pattern', () {
      final filePath = path.join(tempDir.path, 'regex.dart');
      File(filePath).writeAsStringSync('void main() {\n  runApp();\n}\n');
      ConfigEditor.insertCodeBeforePattern(
        filePath: filePath,
        pattern: RegExp(r'runApp\(\)'),
        code: '// before runApp\n  ',
      );
      final content = File(filePath).readAsStringSync();
      expect(
        content.indexOf('// before runApp'),
        lessThan(content.indexOf('runApp()')),
      );
    });

    test('does nothing when pattern is not found', () {
      final filePath = path.join(tempDir.path, 'no_match.dart');
      const original = 'void main() {}\n';
      File(filePath).writeAsStringSync(original);
      ConfigEditor.insertCodeBeforePattern(
        filePath: filePath,
        pattern: 'nonExistentToken',
        code: 'INSERTED',
      );
      expect(File(filePath).readAsStringSync(), equals(original));
    });
  });

  group('ConfigEditor.insertCodeAfterPattern()', () {
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('magic_test_after_pattern_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('inserts code after the matched string pattern', () {
      final filePath = path.join(tempDir.path, 'after.dart');
      File(filePath).writeAsStringSync('final x = setup();\nrunApp();\n');
      ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: 'setup()',
        code: '\n  configure();',
      );
      final content = File(filePath).readAsStringSync();
      expect(
        content.indexOf('configure()'),
        greaterThan(content.indexOf('setup()')),
      );
    });

    test('inserts code after a RegExp pattern', () {
      final filePath = path.join(tempDir.path, 'after_regex.dart');
      File(filePath).writeAsStringSync('void init() {\n  start();\n}\n');
      ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: RegExp(r'void init\(\)'),
        code: ' // initialized',
      );
      final content = File(filePath).readAsStringSync();
      expect(
        content.indexOf('// initialized'),
        greaterThan(content.indexOf('void init()')),
      );
    });

    test('does nothing when pattern is not found', () {
      final filePath = path.join(tempDir.path, 'no_match_after.dart');
      const original = 'void main() {}\n';
      File(filePath).writeAsStringSync(original);
      ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: 'missingToken',
        code: 'INSERTED',
      );
      expect(File(filePath).readAsStringSync(), equals(original));
    });
  });

  group('ConfigEditor.createConfigFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_create_cfg_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('creates file with given content', () {
      final filePath = path.join(tempDir.path, 'app.dart');
      const content = "final appConfig = {'name': 'MyApp'};";
      ConfigEditor.createConfigFile(path: filePath, content: content);
      expect(FileHelper.fileExists(filePath), isTrue);
      expect(File(filePath).readAsStringSync(), equals(content));
    });

    test('overwrites existing file', () {
      final filePath = path.join(tempDir.path, 'existing.dart');
      File(filePath).writeAsStringSync('old content');
      ConfigEditor.createConfigFile(
        path: filePath,
        content: 'new content',
      );
      expect(File(filePath).readAsStringSync(), equals('new content'));
    });

    test('creates parent directories if they do not exist', () {
      final filePath = path.join(tempDir.path, 'lib', 'config', 'app.dart');
      ConfigEditor.createConfigFile(
        path: filePath,
        content: '// generated',
      );
      expect(File(filePath).existsSync(), isTrue);
      expect(File(filePath).readAsStringSync(), equals('// generated'));
    });

    test('creates file with empty content', () {
      final filePath = path.join(tempDir.path, 'empty.dart');
      ConfigEditor.createConfigFile(path: filePath, content: '');
      expect(File(filePath).existsSync(), isTrue);
      expect(File(filePath).readAsStringSync(), equals(''));
    });
  });
}
