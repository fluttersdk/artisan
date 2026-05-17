import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('JsonEditor', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_json_editor_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('writeJson + readJson round-trip', () {
      final filePath = p.join(tempDir.path, 'a.json');

      JsonEditor.writeJson(filePath, <String, dynamic>{'k': 'v'});

      expect(JsonEditor.readJson(filePath), <String, dynamic>{'k': 'v'});
    });

    test('readJson throws when file missing', () {
      expect(
        () => JsonEditor.readJson(p.join(tempDir.path, 'absent.json')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('readJson throws FormatException on malformed JSON', () {
      final filePath = p.join(tempDir.path, 'bad.json');
      File(filePath).writeAsStringSync('not json');

      expect(() => JsonEditor.readJson(filePath), throwsFormatException);
    });

    test('mergeKey adds or updates a single key', () {
      final filePath = p.join(tempDir.path, 'a.json');
      JsonEditor.writeJson(filePath, <String, dynamic>{'a': 1});

      JsonEditor.mergeKey(filePath, 'b', 2);
      JsonEditor.mergeKey(filePath, 'a', 99);

      expect(JsonEditor.readJson(filePath), <String, dynamic>{'a': 99, 'b': 2});
    });

    test('deepMerge source-wins (default) on leaf conflicts', () {
      final result = JsonEditor.deepMerge(
        <String, dynamic>{
          'auth': <String, dynamic>{'login': 'Login', 'logout': 'Logout'},
        },
        <String, dynamic>{
          'auth': <String, dynamic>{'login': 'Sign In', 'register': 'Sign Up'},
        },
      );

      expect(
        result,
        <String, dynamic>{
          'auth': <String, dynamic>{
            'login': 'Sign In',
            'logout': 'Logout',
            'register': 'Sign Up',
          },
        },
      );
    });

    test('deepMerge additive=true preserves existing leaf values', () {
      final result = JsonEditor.deepMerge(
        <String, dynamic>{
          'auth': <String, dynamic>{'login': 'Login'},
        },
        <String, dynamic>{
          'auth': <String, dynamic>{'login': 'Sign In', 'register': 'Sign Up'},
        },
        additive: true,
      );

      expect(
        result,
        <String, dynamic>{
          'auth': <String, dynamic>{
            'login': 'Login',
            'register': 'Sign Up',
          },
        },
      );
    });

    test('mergeJsonFile writes source verbatim when target absent', () {
      final src = p.join(tempDir.path, 'src.json');
      final dst = p.join(tempDir.path, 'dst.json');
      File(src).writeAsStringSync('{"k":"v"}');

      JsonEditor.mergeJsonFile(dst, src);

      expect(JsonEditor.readJson(dst), <String, dynamic>{'k': 'v'});
    });

    test('mergeJsonFile force=true skips merge and overwrites', () {
      final src = p.join(tempDir.path, 'src.json');
      final dst = p.join(tempDir.path, 'dst.json');
      File(src).writeAsStringSync(jsonEncode(<String, dynamic>{'a': 'src'}));
      File(dst).writeAsStringSync(jsonEncode(<String, dynamic>{'a': 'dst'}));

      JsonEditor.mergeJsonFile(dst, src, force: true);

      expect(JsonEditor.readJson(dst), <String, dynamic>{'a': 'src'});
    });

    test('mergeJsonData merges in-memory source into file', () {
      final dst = p.join(tempDir.path, 'dst.json');
      JsonEditor.writeJson(dst, <String, dynamic>{'a': 1});

      JsonEditor.mergeJsonData(dst, <String, dynamic>{'b': 2});

      expect(JsonEditor.readJson(dst), <String, dynamic>{'a': 1, 'b': 2});
    });

    test('hasKey returns true / false / false-on-missing', () {
      final filePath = p.join(tempDir.path, 'a.json');
      JsonEditor.writeJson(filePath, <String, dynamic>{'present': 1});

      expect(JsonEditor.hasKey(filePath, 'present'), isTrue);
      expect(JsonEditor.hasKey(filePath, 'absent'), isFalse);
      expect(JsonEditor.hasKey(p.join(tempDir.path, 'no_file'), 'x'), isFalse);
    });
  });
}
