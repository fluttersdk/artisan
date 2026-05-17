import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:magic_cli/src/helpers/file_helper.dart';

/// Safety-net tests for [FileHelper] public API.
///
/// All file-system operations are isolated to a per-group temp directory
/// that is removed in tearDown.
void main() {
  group('FileHelper.fileExists()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_file_exists_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns true for an existing file', () {
      final filePath = path.join(tempDir.path, 'exists.txt');
      File(filePath).writeAsStringSync('hello');
      expect(FileHelper.fileExists(filePath), isTrue);
    });

    test('returns false for a non-existent file', () {
      final filePath = path.join(tempDir.path, 'does_not_exist.txt');
      expect(FileHelper.fileExists(filePath), isFalse);
    });

    test('returns false for a directory path', () {
      expect(FileHelper.fileExists(tempDir.path), isFalse);
    });
  });

  group('FileHelper.directoryExists()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_dir_exists_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns true for an existing directory', () {
      expect(FileHelper.directoryExists(tempDir.path), isTrue);
    });

    test('returns false for a non-existent directory', () {
      final dirPath = path.join(tempDir.path, 'ghost_dir');
      expect(FileHelper.directoryExists(dirPath), isFalse);
    });

    test('returns false for a file path', () {
      final filePath = path.join(tempDir.path, 'file.txt');
      File(filePath).writeAsStringSync('content');
      expect(FileHelper.directoryExists(filePath), isFalse);
    });
  });

  group('FileHelper.readFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_read_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('reads and returns file content as string', () {
      final filePath = path.join(tempDir.path, 'hello.txt');
      File(filePath).writeAsStringSync('Hello, World!');
      expect(FileHelper.readFile(filePath), equals('Hello, World!'));
    });

    test('reads multi-line file content', () {
      final filePath = path.join(tempDir.path, 'multi.txt');
      File(filePath).writeAsStringSync('line1\nline2\nline3');
      expect(FileHelper.readFile(filePath), equals('line1\nline2\nline3'));
    });

    test('throws FileSystemException for non-existent file', () {
      final filePath = path.join(tempDir.path, 'missing.txt');
      expect(
        () => FileHelper.readFile(filePath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('returns empty string for empty file', () {
      final filePath = path.join(tempDir.path, 'empty.txt');
      File(filePath).writeAsStringSync('');
      expect(FileHelper.readFile(filePath), equals(''));
    });
  });

  group('FileHelper.writeFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_write_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('creates file with given content', () {
      final filePath = path.join(tempDir.path, 'new.txt');
      FileHelper.writeFile(filePath, 'new content');
      expect(File(filePath).readAsStringSync(), equals('new content'));
    });

    test('overwrites existing file content', () {
      final filePath = path.join(tempDir.path, 'existing.txt');
      File(filePath).writeAsStringSync('old content');
      FileHelper.writeFile(filePath, 'updated content');
      expect(File(filePath).readAsStringSync(), equals('updated content'));
    });

    test('creates parent directories automatically', () {
      final nested = path.join(tempDir.path, 'a', 'b', 'c', 'file.txt');
      FileHelper.writeFile(nested, 'deep content');
      expect(File(nested).readAsStringSync(), equals('deep content'));
    });

    test('writes empty string correctly', () {
      final filePath = path.join(tempDir.path, 'empty.txt');
      FileHelper.writeFile(filePath, '');
      expect(File(filePath).readAsStringSync(), equals(''));
    });
  });

  group('FileHelper.copyFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_copy_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('copies file content to destination', () {
      final source = path.join(tempDir.path, 'source.txt');
      final dest = path.join(tempDir.path, 'dest.txt');
      File(source).writeAsStringSync('copy me');
      FileHelper.copyFile(source, dest);
      expect(File(dest).readAsStringSync(), equals('copy me'));
    });

    test('source file still exists after copy', () {
      final source = path.join(tempDir.path, 'original.txt');
      final dest = path.join(tempDir.path, 'copy.txt');
      File(source).writeAsStringSync('data');
      FileHelper.copyFile(source, dest);
      expect(File(source).existsSync(), isTrue);
    });

    test('throws FileSystemException for non-existent source', () {
      final source = path.join(tempDir.path, 'ghost.txt');
      final dest = path.join(tempDir.path, 'dest.txt');
      expect(
        () => FileHelper.copyFile(source, dest),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('FileHelper.deleteFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_delete_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('deletes an existing file', () {
      final filePath = path.join(tempDir.path, 'to_delete.txt');
      File(filePath).writeAsStringSync('bye');
      FileHelper.deleteFile(filePath);
      expect(File(filePath).existsSync(), isFalse);
    });

    test('does not throw when file does not exist (safe delete)', () {
      final filePath = path.join(tempDir.path, 'ghost.txt');
      expect(() => FileHelper.deleteFile(filePath), returnsNormally);
    });
  });

  group('FileHelper.ensureDirectoryExists()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_ensure_dir_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('creates a non-existent directory', () {
      final dirPath = path.join(tempDir.path, 'new_dir');
      FileHelper.ensureDirectoryExists(dirPath);
      expect(Directory(dirPath).existsSync(), isTrue);
    });

    test('creates nested directories recursively', () {
      final dirPath = path.join(tempDir.path, 'a', 'b', 'c');
      FileHelper.ensureDirectoryExists(dirPath);
      expect(Directory(dirPath).existsSync(), isTrue);
    });

    test('does not throw when directory already exists', () {
      expect(
        () => FileHelper.ensureDirectoryExists(tempDir.path),
        returnsNormally,
      );
    });
  });

  group('FileHelper.readYamlFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_yaml_read_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('parses a valid YAML file into a Map', () {
      final filePath = path.join(tempDir.path, 'config.yaml');
      File(filePath).writeAsStringSync('name: myapp\nversion: 1.0.0\n');
      final result = FileHelper.readYamlFile(filePath);
      expect(result, isA<Map<String, dynamic>>());
      expect(result['name'], equals('myapp'));
      expect(result['version'], equals('1.0.0'));
    });

    test('parses nested YAML structure', () {
      final filePath = path.join(tempDir.path, 'nested.yaml');
      File(filePath).writeAsStringSync(
        'environment:\n  sdk: ">=3.4.0 <4.0.0"\n',
      );
      final result = FileHelper.readYamlFile(filePath);
      final env = result['environment'] as Map;
      expect(env['sdk'], equals('>=3.4.0 <4.0.0'));
    });

    test('throws FileSystemException for missing file', () {
      final filePath = path.join(tempDir.path, 'missing.yaml');
      expect(
        () => FileHelper.readYamlFile(filePath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws Exception for non-map YAML root', () {
      final filePath = path.join(tempDir.path, 'list.yaml');
      File(filePath).writeAsStringSync('- a\n- b\n');
      expect(
        () => FileHelper.readYamlFile(filePath),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('FileHelper.writeYamlFile()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_yaml_write_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('writes map data and file can be read back', () {
      final filePath = path.join(tempDir.path, 'output.yaml');
      FileHelper.writeYamlFile(filePath, {
        'name': 'testapp',
        'version': '2.0.0',
      });
      expect(File(filePath).existsSync(), isTrue);
      final content = File(filePath).readAsStringSync();
      expect(content, contains('name:'));
      expect(content, contains('testapp'));
    });

    test('round-trips simple key-value map', () {
      final filePath = path.join(tempDir.path, 'roundtrip.yaml');
      final data = <String, dynamic>{
        'key': 'value',
        'number': 42,
      };
      FileHelper.writeYamlFile(filePath, data);
      // Verify file exists and contains our data
      final content = File(filePath).readAsStringSync();
      expect(content, contains('key:'));
      expect(content, contains('value'));
      expect(content, contains('42'));
    });

    test('creates parent directories if they do not exist', () {
      final filePath = path.join(tempDir.path, 'sub', 'config.yaml');
      FileHelper.writeYamlFile(filePath, {'a': 'b'});
      expect(File(filePath).existsSync(), isTrue);
    });
  });

  group('FileHelper.findProjectRoot()', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_root_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('finds the directory containing pubspec.yaml', () {
      // Create a pubspec.yaml in tempDir
      File(path.join(tempDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: testproject\n');

      final result = FileHelper.findProjectRoot(startFrom: tempDir.path);
      expect(result, equals(tempDir.path));
    });

    test('traverses up to find pubspec.yaml in parent', () {
      // pubspec.yaml in tempDir, start from nested subdir
      File(path.join(tempDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: testproject\n');
      final subDir = Directory(path.join(tempDir.path, 'lib'))..createSync();

      final result = FileHelper.findProjectRoot(startFrom: subDir.path);
      expect(result, equals(tempDir.path));
    });

    test('throws Exception when no pubspec.yaml is found', () {
      // Start from tempDir with no pubspec.yaml inside, and traversal will
      // eventually reach filesystem root where no pubspec.yaml exists either.
      // We use a path that has no pubspec.yaml anywhere above it.
      // The safest approach: use a fresh temp dir with no pubspec.yaml.
      final isolatedDir = Directory(
        path.join(tempDir.path, 'no_project'),
      )..createSync();

      expect(
        () => FileHelper.findProjectRoot(startFrom: isolatedDir.path),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('FileHelper.getRelativePath()', () {
    test('computes relative path between two absolute paths', () {
      final result = FileHelper.getRelativePath(
        '/home/user/project',
        '/home/user/project/lib/main.dart',
      );
      expect(result, equals('lib/main.dart'));
    });

    test('computes relative path going up directories', () {
      final result = FileHelper.getRelativePath(
        '/home/user/project/lib',
        '/home/user/project/test/helpers',
      );
      expect(result, equals('../test/helpers'));
    });

    test('same path returns empty or dot', () {
      final result = FileHelper.getRelativePath(
        '/home/user/project',
        '/home/user/project',
      );
      expect(result, equals('.'));
    });
  });
}
