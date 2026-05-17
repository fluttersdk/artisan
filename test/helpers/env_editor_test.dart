import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('EnvEditor', () {
    late Directory tempDir;
    late String envPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_env_editor_');
      envPath = p.join(tempDir.path, '.env');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // setKey
    // -------------------------------------------------------------------------

    test('setKey creates file with KEY=value when file is absent', () {
      EnvEditor.setKey(envPath, 'APP_NAME', 'MyApp');

      final content = File(envPath).readAsStringSync();
      expect(content, contains('APP_NAME=MyApp\n'));
    });

    test('setKey appends new key to populated file', () {
      File(envPath).writeAsStringSync('DEBUG=true\n');

      EnvEditor.setKey(envPath, 'LOG_LEVEL', 'info');

      final content = File(envPath).readAsStringSync();
      expect(content, contains('DEBUG=true'));
      expect(content, contains('LOG_LEVEL=info'));
    });

    test('setKey updates existing key value, preserves position and other keys',
        () {
      File(envPath).writeAsStringSync('DEBUG=true\nAPP_ENV=local\nLOG=info\n');

      EnvEditor.setKey(envPath, 'APP_ENV', 'production');

      final content = File(envPath).readAsStringSync();
      expect(content, contains('APP_ENV=production'));
      expect(content, isNot(contains('APP_ENV=local')));
      // Other keys preserved.
      expect(content, contains('DEBUG=true'));
      expect(content, contains('LOG=info'));
      // Position: APP_ENV should still be between DEBUG and LOG.
      final debugIdx = content.indexOf('DEBUG=true');
      final appEnvIdx = content.indexOf('APP_ENV=production');
      final logIdx = content.indexOf('LOG=info');
      expect(appEnvIdx, greaterThan(debugIdx));
      expect(logIdx, greaterThan(appEnvIdx));
    });

    test('setKey with comment prepends # comment line above the KEY= line', () {
      EnvEditor.setKey(envPath, 'DB_HOST', 'localhost',
          comment: 'Database connection');

      final content = File(envPath).readAsStringSync();
      expect(content, contains('# Database connection\n'));
      expect(content, contains('DB_HOST=localhost'));

      // Comment must appear immediately before the key line.
      final commentIdx = content.indexOf('# Database connection');
      final keyIdx = content.indexOf('DB_HOST=localhost');
      expect(keyIdx, greaterThan(commentIdx));
      // No content between comment and key line (just the newline ending the comment).
      final between = content.substring(commentIdx, keyIdx);
      expect(between.trim(), equals('# Database connection'));
    });

    test('setKey wraps value with spaces in double quotes', () {
      EnvEditor.setKey(envPath, 'APP_NAME', 'My Fancy App');

      final content = File(envPath).readAsStringSync();
      expect(content, contains('APP_NAME="My Fancy App"'));
    });

    test('setKey wraps value with hash in double quotes', () {
      EnvEditor.setKey(envPath, 'APP_COMMENT', 'hello#world');

      final content = File(envPath).readAsStringSync();
      expect(content, contains('APP_COMMENT="hello#world"'));
    });

    test('setKey wraps value with dollar sign in double quotes', () {
      EnvEditor.setKey(envPath, 'SECRET', r'pa$$word');

      final content = File(envPath).readAsStringSync();
      expect(content, contains(r'SECRET="pa$$word"'));
    });

    test(
        'setKey wraps value with single quote in double quotes, escaping inner double quotes',
        () {
      EnvEditor.setKey(envPath, 'GREETING', "it's alive");

      final content = File(envPath).readAsStringSync();
      expect(content, contains("GREETING=\"it's alive\""));
    });

    test(
        'setKey wraps value containing double quote and escapes inner double quotes',
        () {
      EnvEditor.setKey(envPath, 'LABEL', 'say "hi"');

      final content = File(envPath).readAsStringSync();
      // Inner double quotes escaped with backslash.
      expect(content, contains(r'LABEL="say \"hi\""'));
    });

    // -------------------------------------------------------------------------
    // getKey
    // -------------------------------------------------------------------------

    test('getKey returns value for present key', () {
      File(envPath).writeAsStringSync('FOO=bar\n');

      expect(EnvEditor.getKey(envPath, 'FOO'), equals('bar'));
    });

    test('getKey returns unquoted value for quoted line', () {
      File(envPath).writeAsStringSync('FOO="hello world"\n');

      expect(EnvEditor.getKey(envPath, 'FOO'), equals('hello world'));
    });

    test('getKey returns null for absent key', () {
      File(envPath).writeAsStringSync('FOO=bar\n');

      expect(EnvEditor.getKey(envPath, 'MISSING'), isNull);
    });

    test('getKey returns null when file does not exist', () {
      expect(EnvEditor.getKey(envPath, 'FOO'), isNull);
    });

    // -------------------------------------------------------------------------
    // removeKey
    // -------------------------------------------------------------------------

    test('removeKey deletes target line', () {
      File(envPath).writeAsStringSync('FOO=bar\nBAZ=qux\n');

      EnvEditor.removeKey(envPath, 'FOO');

      final content = File(envPath).readAsStringSync();
      expect(content, isNot(contains('FOO=')));
      expect(content, contains('BAZ=qux'));
    });

    test('removeKey also deletes the comment line immediately above the key',
        () {
      File(envPath).writeAsStringSync('# My comment\nFOO=bar\nBAZ=qux\n');

      EnvEditor.removeKey(envPath, 'FOO');

      final content = File(envPath).readAsStringSync();
      expect(content, isNot(contains('# My comment')));
      expect(content, isNot(contains('FOO=')));
      expect(content, contains('BAZ=qux'));
    });

    test('removeKey preserves unrelated comments above other keys', () {
      File(envPath)
          .writeAsStringSync('# Keep me\nBAR=1\n# Remove me\nFOO=bar\n');

      EnvEditor.removeKey(envPath, 'FOO');

      final content = File(envPath).readAsStringSync();
      expect(content, contains('# Keep me'));
      expect(content, isNot(contains('# Remove me')));
    });

    test('removeKey is a no-op for absent key (does not throw)', () {
      File(envPath).writeAsStringSync('FOO=bar\n');
      final before = File(envPath).readAsStringSync();

      expect(() => EnvEditor.removeKey(envPath, 'MISSING'), returnsNormally);
      expect(File(envPath).readAsStringSync(), equals(before));
    });

    test('removeKey is a no-op when file does not exist (does not throw)', () {
      expect(() => EnvEditor.removeKey(envPath, 'FOO'), returnsNormally);
    });

    // -------------------------------------------------------------------------
    // hasKey
    // -------------------------------------------------------------------------

    test('hasKey returns true when key is present', () {
      File(envPath).writeAsStringSync('FOO=bar\n');

      expect(EnvEditor.hasKey(envPath, 'FOO'), isTrue);
    });

    test('hasKey returns false when key is absent', () {
      File(envPath).writeAsStringSync('FOO=bar\n');

      expect(EnvEditor.hasKey(envPath, 'MISSING'), isFalse);
    });

    test('hasKey returns false when file does not exist', () {
      expect(EnvEditor.hasKey(envPath, 'FOO'), isFalse);
    });
  });
}
