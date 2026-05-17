import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_seeder_command.dart';

/// Testable subclass that overrides [getProjectRoot] to use a temp directory.
class _TestMakeSeederCommand extends MakeSeederCommand {
  _TestMakeSeederCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeSeederCommand', () {
    late Directory tempDir;
    late _TestMakeSeederCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_seeder_');
      cmd = _TestMakeSeederCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('name and description are correct', () {
      expect(cmd.name, 'make:seeder');
      expect(cmd.description, isNotEmpty);
    });

    test('creates seeder file with Seeder suffix auto-appended', () async {
      final results = parser.parse(['User']);
      cmd.arguments = results;

      await cmd.handle();

      final seederFile = File(
        '${tempDir.path}/lib/database/seeders/user_seeder.dart',
      );
      expect(seederFile.existsSync(), isTrue);

      final content = seederFile.readAsStringSync();
      expect(content, contains('UserSeeder'));
    });

    test('does not double-append Seeder suffix', () async {
      final results = parser.parse(['UserSeeder']);
      cmd.arguments = results;

      await cmd.handle();

      final seederFile = File(
        '${tempDir.path}/lib/database/seeders/user_seeder.dart',
      );
      expect(seederFile.existsSync(), isTrue);

      final content = seederFile.readAsStringSync();
      // Class name must be UserSeeder, NOT UserSeederSeeder
      expect(content, contains('UserSeeder'));
      expect(content, isNot(contains('UserSeederSeeder')));
    });

    test('file is placed in lib/database/seeders/', () async {
      final results = parser.parse(['Post']);
      cmd.arguments = results;

      await cmd.handle();

      final dir = Directory('${tempDir.path}/lib/database/seeders');
      expect(dir.existsSync(), isTrue);

      final file = File('${dir.path}/post_seeder.dart');
      expect(file.existsSync(), isTrue);
    });

    test('aborts if file exists without --force', () async {
      final results = parser.parse(['Tag']);
      cmd.arguments = results;
      await cmd.handle();

      final file = File('${tempDir.path}/lib/database/seeders/tag_seeder.dart');
      file.writeAsStringSync('ORIGINAL');

      cmd.arguments = parser.parse(['Tag']);
      await cmd.handle();

      expect(file.readAsStringSync(), 'ORIGINAL');
    });

    test('overwrites existing file with --force', () async {
      var results = parser.parse(['Category']);
      cmd.arguments = results;
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/database/seeders/category_seeder.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      results = parser.parse(['Category', '--force']);
      cmd.arguments = results;
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('ORIGINAL'));
      expect(file.readAsStringSync(), contains('CategorySeeder'));
    });
  });
}
