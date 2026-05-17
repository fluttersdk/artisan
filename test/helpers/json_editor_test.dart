import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/helpers/json_editor.dart';

/// Tests for [JsonEditor] — JSON file manipulation.
///
/// All tests use a temporary directory that is cleaned up after each test.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_test_json_editor');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // readJson()
  // ---------------------------------------------------------------------------
  group('JsonEditor.readJson()', () {
    test('parses a JSON file into a Map', () {
      final file = File('${tempDir.path}/data.json');
      file.writeAsStringSync('{"name":"Magic","version":"1.0.0"}');

      final result = JsonEditor.readJson(file.path);

      expect(result['name'], equals('Magic'));
      expect(result['version'], equals('1.0.0'));
    });

    test('throws FileSystemException when file does not exist', () {
      expect(
        () => JsonEditor.readJson('${tempDir.path}/missing.json'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('throws FormatException for malformed JSON', () {
      final file = File('${tempDir.path}/bad.json');
      file.writeAsStringSync('{bad json}');

      expect(
        () => JsonEditor.readJson(file.path),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // writeJson()
  // ---------------------------------------------------------------------------
  group('JsonEditor.writeJson()', () {
    test('writes a map to a JSON file with default 2-space indent', () {
      final filePath = '${tempDir.path}/output.json';
      JsonEditor.writeJson(filePath, {'key': 'value', 'num': 42});

      final content = File(filePath).readAsStringSync();
      final decoded = jsonDecode(content) as Map<String, dynamic>;

      expect(decoded['key'], equals('value'));
      expect(decoded['num'], equals(42));
      // Default indent means the file is pretty-printed
      expect(content, contains('\n'));
    });

    test('respects custom indent parameter', () {
      final filePath = '${tempDir.path}/output4.json';
      JsonEditor.writeJson(filePath, {'a': 1}, indent: 4);

      final content = File(filePath).readAsStringSync();
      // 4-space indent means a key will be preceded by 4 spaces
      expect(content, contains('    "a"'));
    });

    test('creates parent directories if they do not exist', () {
      final filePath = '${tempDir.path}/nested/dir/file.json';
      JsonEditor.writeJson(filePath, {'ok': true});

      expect(File(filePath).existsSync(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // mergeKey()
  // ---------------------------------------------------------------------------
  group('JsonEditor.mergeKey()', () {
    test('adds a new key while preserving existing keys', () {
      final file = File('${tempDir.path}/manifest.json');
      file.writeAsStringSync('{"existing_key":"existing_value"}');

      JsonEditor.mergeKey(file.path, 'new_key', 'new_value');

      final result = JsonEditor.readJson(file.path);
      expect(result['existing_key'], equals('existing_value'));
      expect(result['new_key'], equals('new_value'));
    });

    test('overwrites an existing key with the new value', () {
      final file = File('${tempDir.path}/config.json');
      file.writeAsStringSync('{"version":"1.0"}');

      JsonEditor.mergeKey(file.path, 'version', '2.0');

      final result = JsonEditor.readJson(file.path);
      expect(result['version'], equals('2.0'));
    });

    test('works with non-string values (int, bool, list)', () {
      final file = File('${tempDir.path}/data.json');
      file.writeAsStringSync('{}');

      JsonEditor.mergeKey(file.path, 'count', 42);
      JsonEditor.mergeKey(file.path, 'active', true);
      JsonEditor.mergeKey(file.path, 'tags', ['flutter', 'dart']);

      final result = JsonEditor.readJson(file.path);
      expect(result['count'], equals(42));
      expect(result['active'], isTrue);
      expect(result['tags'], equals(['flutter', 'dart']));
    });

    test('writes valid JSON after merging', () {
      final file = File('${tempDir.path}/manifest.json');
      file.writeAsStringSync('{"gcm_sender_id":"482941778795"}');

      JsonEditor.mergeKey(file.path, 'short_name', 'MyApp');

      final content = file.readAsStringSync();
      // Must be parseable
      expect(() => jsonDecode(content), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // hasKey()
  // ---------------------------------------------------------------------------
  group('JsonEditor.hasKey()', () {
    test('returns true when the key exists in the JSON file', () {
      final file = File('${tempDir.path}/data.json');
      file.writeAsStringSync('{"gcm_sender_id":"482941778795"}');

      expect(JsonEditor.hasKey(file.path, 'gcm_sender_id'), isTrue);
    });

    test('returns false when the key does not exist', () {
      final file = File('${tempDir.path}/data.json');
      file.writeAsStringSync('{"name":"App"}');

      expect(JsonEditor.hasKey(file.path, 'gcm_sender_id'), isFalse);
    });

    test('returns false for a non-existent file (graceful)', () {
      expect(
        JsonEditor.hasKey('${tempDir.path}/gone.json', 'key'),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // deepMerge()
  // ---------------------------------------------------------------------------
  group('JsonEditor.deepMerge()', () {
    test('merges flat maps with source taking precedence', () {
      final target = <String, dynamic>{
        'name': 'App',
        'version': '1.0',
      };
      final source = <String, dynamic>{
        'version': '2.0',
        'author': 'Anilcan',
      };

      final result = JsonEditor.deepMerge(target, source);

      expect(result['name'], equals('App'));
      expect(result['version'], equals('2.0'));
      expect(result['author'], equals('Anilcan'));
    });

    test('recursively merges nested maps', () {
      final target = <String, dynamic>{
        'auth': {
          'login': 'Login',
          'logout': 'Logout',
        },
      };
      final source = <String, dynamic>{
        'auth': {
          'login': 'Sign In',
          'register': 'Sign Up',
        },
      };

      final result = JsonEditor.deepMerge(target, source);
      final auth = result['auth'] as Map<String, dynamic>;

      expect(auth['login'], equals('Sign In'));
      expect(auth['logout'], equals('Logout'));
      expect(auth['register'], equals('Sign Up'));
    });

    test('handles deeply nested structures (3+ levels)', () {
      final target = <String, dynamic>{
        'level1': {
          'level2': {
            'existing': 'kept',
            'overwritten': 'old',
          },
        },
      };
      final source = <String, dynamic>{
        'level1': {
          'level2': {
            'overwritten': 'new',
            'added': 'fresh',
          },
        },
      };

      final result = JsonEditor.deepMerge(target, source);
      final level2 = (result['level1'] as Map<String, dynamic>)['level2']
          as Map<String, dynamic>;

      expect(level2['existing'], equals('kept'));
      expect(level2['overwritten'], equals('new'));
      expect(level2['added'], equals('fresh'));
    });

    test('source overwrites target when types differ (map vs scalar)', () {
      final target = <String, dynamic>{
        'auth': {
          'login': 'Login',
        },
      };
      final source = <String, dynamic>{
        'auth': 'disabled',
      };

      final result = JsonEditor.deepMerge(target, source);

      expect(result['auth'], equals('disabled'));
    });

    test('does not mutate input maps', () {
      final target = <String, dynamic>{
        'key': 'original',
        'nested': {'a': 1},
      };
      final source = <String, dynamic>{
        'key': 'changed',
        'nested': {'b': 2},
      };

      JsonEditor.deepMerge(target, source);

      expect(target['key'], equals('original'));
      expect(
        (target['nested'] as Map<String, dynamic>).containsKey('b'),
        isFalse,
      );
    });

    test('returns empty map when both inputs are empty', () {
      final result = JsonEditor.deepMerge(
        <String, dynamic>{},
        <String, dynamic>{},
      );

      expect(result, isEmpty);
    });

    test('returns source content when target is empty', () {
      final source = <String, dynamic>{
        'auth': {
          'login': 'Login',
        },
      };

      final result = JsonEditor.deepMerge(<String, dynamic>{}, source);

      expect(result['auth'], isNotNull);
      expect(
        (result['auth'] as Map<String, dynamic>)['login'],
        equals('Login'),
      );
    });

    test('additive mode preserves existing leaf values', () {
      final target = <String, dynamic>{
        'app': {'name': 'UPTIZM'},
        'auth': {
          'login_title': 'Welcome to Uptizm',
          'logout': 'Logout',
        },
      };
      final source = <String, dynamic>{
        'app': {'name': 'My App'},
        'auth': {
          'login_title': 'Sign In',
          'register_title': 'Create Account',
        },
      };

      final result = JsonEditor.deepMerge(
        target,
        source,
        additive: true,
      );

      // 1. Existing leaf values preserved (target wins).
      expect(
        (result['app'] as Map<String, dynamic>)['name'],
        equals('UPTIZM'),
      );
      expect(
        (result['auth'] as Map<String, dynamic>)['login_title'],
        equals('Welcome to Uptizm'),
      );
      // 2. Existing keys not in source still present.
      expect(
        (result['auth'] as Map<String, dynamic>)['logout'],
        equals('Logout'),
      );
      // 3. New keys from source added.
      expect(
        (result['auth'] as Map<String, dynamic>)['register_title'],
        equals('Create Account'),
      );
    });

    test('additive mode recurses into nested maps', () {
      final target = <String, dynamic>{
        'level1': {
          'level2': {
            'existing': 'kept',
            'customised': 'user value',
          },
        },
      };
      final source = <String, dynamic>{
        'level1': {
          'level2': {
            'customised': 'default value',
            'added': 'new',
          },
        },
      };

      final result = JsonEditor.deepMerge(
        target,
        source,
        additive: true,
      );
      final level2 = (result['level1'] as Map<String, dynamic>)['level2']
          as Map<String, dynamic>;

      expect(level2['existing'], equals('kept'));
      expect(level2['customised'], equals('user value'));
      expect(level2['added'], equals('new'));
    });

    test('additive mode adds top-level keys missing from target', () {
      final target = <String, dynamic>{
        'auth': {'login': 'Login'},
      };
      final source = <String, dynamic>{
        'auth': {'login': 'Sign In'},
        'errors': {'unexpected': 'Oops'},
      };

      final result = JsonEditor.deepMerge(
        target,
        source,
        additive: true,
      );

      // Existing leaf preserved.
      expect(
        (result['auth'] as Map<String, dynamic>)['login'],
        equals('Login'),
      );
      // New top-level key added.
      expect(
        (result['errors'] as Map<String, dynamic>)['unexpected'],
        equals('Oops'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // mergeJsonFile()
  // ---------------------------------------------------------------------------
  group('JsonEditor.mergeJsonFile()', () {
    test('writes source as-is when target does not exist', () {
      final sourcePath = '${tempDir.path}/source.json';
      final targetPath = '${tempDir.path}/target.json';

      JsonEditor.writeJson(sourcePath, {
        'auth': {'login': 'Sign In'},
      });

      JsonEditor.mergeJsonFile(targetPath, sourcePath);

      final result = JsonEditor.readJson(targetPath);
      expect(
        (result['auth'] as Map<String, dynamic>)['login'],
        equals('Sign In'),
      );
    });

    test('additive deep-merges preserving existing values', () {
      final sourcePath = '${tempDir.path}/source.json';
      final targetPath = '${tempDir.path}/target.json';

      // Target has customised login text + extra key.
      JsonEditor.writeJson(targetPath, {
        'auth': {
          'login': 'My Custom Login',
          'custom_key': 'user value',
        },
      });

      // Source has default login + new register key.
      JsonEditor.writeJson(sourcePath, {
        'auth': {
          'login': 'Sign In',
          'register': 'Sign Up',
        },
      });

      // Default additive mode — target wins on existing leaves.
      JsonEditor.mergeJsonFile(targetPath, sourcePath);

      final result = JsonEditor.readJson(targetPath);
      final auth = result['auth'] as Map<String, dynamic>;

      // Target wins — customised value preserved.
      expect(auth['login'], equals('My Custom Login'));
      // Existing extra key preserved.
      expect(auth['custom_key'], equals('user value'));
      // New key added from source.
      expect(auth['register'], equals('Sign Up'));
    });

    test('non-additive merge overwrites existing leaf values', () {
      final sourcePath = '${tempDir.path}/source.json';
      final targetPath = '${tempDir.path}/target.json';

      JsonEditor.writeJson(targetPath, {
        'auth': {
          'login': 'My Custom Login',
          'custom_key': 'user value',
        },
      });

      JsonEditor.writeJson(sourcePath, {
        'auth': {
          'login': 'Sign In',
          'register': 'Sign Up',
        },
      });

      JsonEditor.mergeJsonFile(
        targetPath,
        sourcePath,
        additive: false,
      );

      final result = JsonEditor.readJson(targetPath);
      final auth = result['auth'] as Map<String, dynamic>;

      // Source wins on conflict (non-additive).
      expect(auth['login'], equals('Sign In'));
      // Existing extra key preserved.
      expect(auth['custom_key'], equals('user value'));
      // New key added.
      expect(auth['register'], equals('Sign Up'));
    });

    test('force mode overwrites target entirely', () {
      final sourcePath = '${tempDir.path}/source.json';
      final targetPath = '${tempDir.path}/target.json';

      JsonEditor.writeJson(targetPath, {
        'auth': {'login': 'Custom'},
        'extra': 'preserved normally',
      });

      JsonEditor.writeJson(sourcePath, {
        'auth': {'login': 'Sign In'},
      });

      JsonEditor.mergeJsonFile(targetPath, sourcePath, force: true);

      final result = JsonEditor.readJson(targetPath);

      expect(
        (result['auth'] as Map<String, dynamic>)['login'],
        equals('Sign In'),
      );
      // Extra key is gone — force overwrites entirely.
      expect(result.containsKey('extra'), isFalse);
    });

    test('throws when source file does not exist', () {
      expect(
        () => JsonEditor.mergeJsonFile(
          '${tempDir.path}/target.json',
          '${tempDir.path}/missing_source.json',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('is idempotent — running twice produces same result', () {
      final sourcePath = '${tempDir.path}/source.json';
      final targetPath = '${tempDir.path}/target.json';

      JsonEditor.writeJson(targetPath, {
        'existing': 'value',
      });

      JsonEditor.writeJson(sourcePath, {
        'existing': 'value',
        'new_key': 'added',
      });

      JsonEditor.mergeJsonFile(targetPath, sourcePath);
      final firstRun = JsonEditor.readJson(targetPath);

      JsonEditor.mergeJsonFile(targetPath, sourcePath);
      final secondRun = JsonEditor.readJson(targetPath);

      expect(
        jsonEncode(firstRun),
        equals(jsonEncode(secondRun)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // mergeJsonData()
  // ---------------------------------------------------------------------------
  group('JsonEditor.mergeJsonData()', () {
    test('writes data as-is when target does not exist', () {
      final targetPath = '${tempDir.path}/new_target.json';

      JsonEditor.mergeJsonData(targetPath, {
        'key': 'value',
      });

      final result = JsonEditor.readJson(targetPath);
      expect(result['key'], equals('value'));
    });

    test('additive deep-merges preserving existing values', () {
      final targetPath = '${tempDir.path}/target.json';

      JsonEditor.writeJson(targetPath, {
        'auth': {
          'login': 'Custom Login',
          'extra': 'kept',
        },
      });

      // Default additive mode — target wins on existing leaves.
      JsonEditor.mergeJsonData(targetPath, {
        'auth': {
          'login': 'Sign In',
          'register': 'Sign Up',
        },
      });

      final result = JsonEditor.readJson(targetPath);
      final auth = result['auth'] as Map<String, dynamic>;

      // Target wins — customised value preserved.
      expect(auth['login'], equals('Custom Login'));
      expect(auth['extra'], equals('kept'));
      // New key added from source.
      expect(auth['register'], equals('Sign Up'));
    });

    test('non-additive merge overwrites existing leaf values', () {
      final targetPath = '${tempDir.path}/target.json';

      JsonEditor.writeJson(targetPath, {
        'auth': {
          'login': 'Custom Login',
          'extra': 'kept',
        },
      });

      JsonEditor.mergeJsonData(
        targetPath,
        {
          'auth': {
            'login': 'Sign In',
            'register': 'Sign Up',
          },
        },
        additive: false,
      );

      final result = JsonEditor.readJson(targetPath);
      final auth = result['auth'] as Map<String, dynamic>;

      // Source wins on conflict (non-additive).
      expect(auth['login'], equals('Sign In'));
      expect(auth['extra'], equals('kept'));
      expect(auth['register'], equals('Sign Up'));
    });

    test('force mode overwrites target entirely', () {
      final targetPath = '${tempDir.path}/target.json';

      JsonEditor.writeJson(targetPath, {
        'old': 'data',
      });

      JsonEditor.mergeJsonData(
        targetPath,
        {'new': 'data'},
        force: true,
      );

      final result = JsonEditor.readJson(targetPath);

      expect(result.containsKey('old'), isFalse);
      expect(result['new'], equals('data'));
    });
  });
}
