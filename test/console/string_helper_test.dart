import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StringHelper.toPascalCase', () {
    test('returns empty string for empty input', () {
      expect(StringHelper.toPascalCase(''), '');
    });

    test('converts snake_case to PascalCase', () {
      expect(StringHelper.toPascalCase('user_profile'), 'UserProfile');
    });

    test('converts camelCase to PascalCase', () {
      expect(StringHelper.toPascalCase('userProfile'), 'UserProfile');
    });

    test('converts kebab-case to PascalCase', () {
      expect(StringHelper.toPascalCase('user-profile'), 'UserProfile');
    });

    test('handles single words', () {
      expect(StringHelper.toPascalCase('user'), 'User');
    });
  });

  group('StringHelper.toSnakeCase', () {
    test('returns empty string for empty input', () {
      expect(StringHelper.toSnakeCase(''), '');
    });

    test('converts PascalCase to snake_case', () {
      expect(StringHelper.toSnakeCase('UserProfile'), 'user_profile');
    });

    test('converts camelCase to snake_case', () {
      expect(StringHelper.toSnakeCase('userProfile'), 'user_profile');
    });

    test('converts kebab and spaces to underscores', () {
      expect(StringHelper.toSnakeCase('user-profile'), 'user_profile');
      expect(StringHelper.toSnakeCase('user profile'), 'user_profile');
    });
  });

  group('StringHelper.toCamelCase', () {
    test('returns empty string for empty input', () {
      expect(StringHelper.toCamelCase(''), '');
    });

    test('converts snake_case to camelCase', () {
      expect(StringHelper.toCamelCase('user_profile'), 'userProfile');
    });

    test('converts PascalCase to camelCase', () {
      expect(StringHelper.toCamelCase('UserProfile'), 'userProfile');
    });
  });

  group('StringHelper.toPlural', () {
    test('returns empty string for empty input', () {
      expect(StringHelper.toPlural(''), '');
    });

    test('handles irregular nouns', () {
      expect(StringHelper.toPlural('person'), 'people');
      expect(StringHelper.toPlural('child'), 'children');
      expect(StringHelper.toPlural('man'), 'men');
      expect(StringHelper.toPlural('woman'), 'women');
    });

    test('y-ending consonant -> ies', () {
      expect(StringHelper.toPlural('city'), 'cities');
    });

    test('y-ending vowel -> ys', () {
      expect(StringHelper.toPlural('boy'), 'boys');
    });

    test('s/x/z/ch/sh -> es', () {
      expect(StringHelper.toPlural('bus'), 'buses');
      expect(StringHelper.toPlural('box'), 'boxes');
      expect(StringHelper.toPlural('buzz'), 'buzzes');
      expect(StringHelper.toPlural('match'), 'matches');
      expect(StringHelper.toPlural('dish'), 'dishes');
    });

    test('regular noun -> s', () {
      expect(StringHelper.toPlural('user'), 'users');
    });
  });

  group('StringHelper.parseName', () {
    test('empty input returns empty triple', () {
      final parsed = StringHelper.parseName('');

      expect(parsed.directory, '');
      expect(parsed.className, '');
      expect(parsed.fileName, '');
    });

    test('single class name has empty directory', () {
      final parsed = StringHelper.parseName('UserController');

      expect(parsed.directory, '');
      expect(parsed.className, 'UserController');
      expect(parsed.fileName, 'user_controller');
    });

    test('nested name extracts directory and snake_cases each segment', () {
      final parsed = StringHelper.parseName('Admin/UserController');

      expect(parsed.directory, 'admin');
      expect(parsed.className, 'UserController');
      expect(parsed.fileName, 'user_controller');
    });

    test('deeply nested name preserves slash separator', () {
      final parsed = StringHelper.parseName('Api/V1/UserController');

      expect(parsed.directory, 'api/v1');
      expect(parsed.className, 'UserController');
      expect(parsed.fileName, 'user_controller');
    });
  });
}
