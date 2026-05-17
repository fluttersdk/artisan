import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/console/string_helper.dart';

void main() {
  group('StringHelper', () {
    test('toPascalCase converts correctly', () {
      expect(StringHelper.toPascalCase('user_profile'), 'UserProfile');
      expect(StringHelper.toPascalCase('UserProfile'), 'UserProfile');
      expect(StringHelper.toPascalCase('userProfile'), 'UserProfile');
      expect(StringHelper.toPascalCase('User_Profile'), 'UserProfile');
    });

    test('toSnakeCase converts correctly', () {
      expect(StringHelper.toSnakeCase('UserProfile'), 'user_profile');
      expect(StringHelper.toSnakeCase('userProfile'), 'user_profile');
      expect(StringHelper.toSnakeCase('user_profile'), 'user_profile');
    });

    test('toCamelCase converts correctly', () {
      expect(StringHelper.toCamelCase('user_profile'), 'userProfile');
      expect(StringHelper.toCamelCase('UserProfile'), 'userProfile');
      expect(StringHelper.toCamelCase('userProfile'), 'userProfile');
    });

    test('toPlural converts correctly', () {
      expect(StringHelper.toPlural('category'), 'categories');
      expect(StringHelper.toPlural('user'), 'users');
      expect(StringHelper.toPlural('bus'), 'buses');
      expect(StringHelper.toPlural('fox'), 'foxes');
      expect(StringHelper.toPlural('watch'), 'watches');
      expect(StringHelper.toPlural('dish'), 'dishes');
      expect(StringHelper.toPlural('person'), 'people');
      expect(StringHelper.toPlural('child'), 'children');
      expect(StringHelper.toPlural('man'), 'men');
      expect(StringHelper.toPlural('woman'), 'women');
    });

    test('parseName handles nested paths', () {
      final nested = StringHelper.parseName('Admin/UserController');
      expect(nested.directory, 'admin');
      expect(nested.className, 'UserController');
      expect(nested.fileName, 'user_controller');

      final simple = StringHelper.parseName('UserController');
      expect(simple.directory, '');
      expect(simple.className, 'UserController');
      expect(simple.fileName, 'user_controller');

      final deep = StringHelper.parseName('Api/V1/Admin/UserController');
      expect(deep.directory, 'api/v1/admin');
      expect(deep.className, 'UserController');
      expect(deep.fileName, 'user_controller');
    });
  });
}
