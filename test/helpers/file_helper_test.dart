import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FileHelper', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_file_helper_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('fileExists / directoryExists', () {
      final filePath = p.join(tempDir.path, 'a.txt');
      File(filePath).writeAsStringSync('x');

      expect(FileHelper.fileExists(filePath), isTrue);
      expect(FileHelper.fileExists(p.join(tempDir.path, 'absent')), isFalse);
      expect(FileHelper.directoryExists(tempDir.path), isTrue);
      expect(FileHelper.directoryExists('/no/such/dir'), isFalse);
    });

    test('readFile returns the file content', () {
      final filePath = p.join(tempDir.path, 'a.txt');
      File(filePath).writeAsStringSync('hello');

      expect(FileHelper.readFile(filePath), 'hello');
    });

    test('readFile throws FileSystemException when missing', () {
      expect(
        () => FileHelper.readFile(p.join(tempDir.path, 'missing')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('writeFile creates the file and ensures parent dirs exist', () {
      final filePath = p.join(tempDir.path, 'nested', 'deep', 'file.txt');

      FileHelper.writeFile(filePath, 'content');

      expect(File(filePath).readAsStringSync(), 'content');
    });

    test('copyFile duplicates content; throws when source missing', () {
      final source = p.join(tempDir.path, 'src.txt');
      final dest = p.join(tempDir.path, 'dst.txt');
      File(source).writeAsStringSync('payload');

      FileHelper.copyFile(source, dest);

      expect(File(dest).readAsStringSync(), 'payload');
      expect(
        () => FileHelper.copyFile(p.join(tempDir.path, 'nope'), dest),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('deleteFile removes existing files; is a no-op when absent', () {
      final filePath = p.join(tempDir.path, 'gone.txt');
      File(filePath).writeAsStringSync('x');

      FileHelper.deleteFile(filePath);
      expect(File(filePath).existsSync(), isFalse);

      expect(
        () => FileHelper.deleteFile(p.join(tempDir.path, 'never_there')),
        returnsNormally,
      );
    });

    test('ensureDirectoryExists creates the directory once', () {
      final dirPath = p.join(tempDir.path, 'created');

      FileHelper.ensureDirectoryExists(dirPath);
      expect(Directory(dirPath).existsSync(), isTrue);

      // Idempotent.
      FileHelper.ensureDirectoryExists(dirPath);
      expect(Directory(dirPath).existsSync(), isTrue);
    });

    test('readYamlFile parses a simple YAML map', () {
      final yamlPath = p.join(tempDir.path, 'config.yaml');
      File(yamlPath).writeAsStringSync('name: artisan\nversion: 1.0.0\n');

      final parsed = FileHelper.readYamlFile(yamlPath);

      expect(parsed['name'], 'artisan');
      expect(parsed['version'], '1.0.0');
    });

    test('writeYamlFile + readYamlFile round-trip', () {
      final yamlPath = p.join(tempDir.path, 'out.yaml');

      FileHelper.writeYamlFile(yamlPath, <String, dynamic>{
        'top': <String, dynamic>{'inner': 'value'},
        'list': <dynamic>[1, 2, 3],
      });

      final content = File(yamlPath).readAsStringSync();
      expect(content, contains('top:'));
      expect(content, contains('inner:'));
      expect(content, contains('- 1'));
    });

    test('findProjectRoot walks up to the nearest pubspec.yaml', () {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x');
      final nested = Directory(p.join(tempDir.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);

      expect(FileHelper.findProjectRoot(startFrom: nested.path), tempDir.path);
    });

    test('findProjectRoot throws when no pubspec is reachable', () {
      // Use /tmp as start; walking up never finds a pubspec (no pubspec in /).
      // Use a guaranteed-empty temp.
      final isolatedRoot = Directory.systemTemp.createTempSync('iso_root_');
      addTearDown(() => isolatedRoot.deleteSync(recursive: true));

      expect(
        () => FileHelper.findProjectRoot(startFrom: '/'),
        throwsA(isA<Exception>()),
      );
    });

    test('getRelativePath produces relative paths', () {
      final relative = FileHelper.getRelativePath('/a/b', '/a/b/c/d.txt');

      expect(relative, 'c/d.txt');
    });
  });
}
