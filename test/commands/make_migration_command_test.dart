import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_migration_command.dart';

/// Testable subclass that overrides [getProjectRoot] to use a temp directory.
class _TestMakeMigrationCommand extends MakeMigrationCommand {
  _TestMakeMigrationCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeMigrationCommand', () {
    late Directory tempDir;
    late _TestMakeMigrationCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_migration_');
      cmd = _TestMakeMigrationCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('name and description are correct', () {
      expect(cmd.name, 'make:migration');
      expect(cmd.description, isNotEmpty);
    });

    test('creates migration file with timestamp prefix', () async {
      final results = parser.parse(['create_users_table']);
      cmd.arguments = results;

      await cmd.handle();

      final migrationsDir =
          Directory('${tempDir.path}/lib/database/migrations');
      expect(migrationsDir.existsSync(), isTrue);

      final files = migrationsDir.listSync().whereType<File>().toList();
      expect(files.length, 1);

      // Filename must match pattern: m_YYYYMMDDHHMMSS_create_users_table.dart
      final fileName = files.first.path.split(Platform.pathSeparator).last;
      expect(
        fileName,
        matches(RegExp(r'^m_\d{14}_create_users_table\.dart$')),
      );
    });

    test('uses create stub when --create flag is set', () async {
      final results = parser.parse([
        'create_users_table',
        '--create=users',
      ]);
      cmd.arguments = results;

      await cmd.handle();

      final migrationsDir =
          Directory('${tempDir.path}/lib/database/migrations');
      final files = migrationsDir.listSync().whereType<File>().toList();
      expect(files.length, 1);

      final content = files.first.readAsStringSync();
      // Create stub contains Schema.create and Blueprint
      expect(content, contains('Schema.create'));
      expect(content, contains('Blueprint'));
      expect(content, contains("'users'"));
    });

    test('uses plain migration stub when no --create flag', () async {
      final results = parser.parse(['add_email_to_users']);
      cmd.arguments = results;

      await cmd.handle();

      final migrationsDir =
          Directory('${tempDir.path}/lib/database/migrations');
      final files = migrationsDir.listSync().whereType<File>().toList();
      final content = files.first.readAsStringSync();
      // Plain stub does NOT contain Schema.create
      expect(content, isNot(contains('Schema.create')));
    });

    test('uses plain stub with --table flag', () async {
      final results = parser.parse([
        'add_email_to_users',
        '--table=users',
      ]);
      cmd.arguments = results;

      await cmd.handle();

      final migrationsDir =
          Directory('${tempDir.path}/lib/database/migrations');
      final files = migrationsDir.listSync().whereType<File>().toList();
      final content = files.first.readAsStringSync();
      expect(content, isNot(contains('Schema.create')));
    });

    test('aborts if file exists without --force', () async {
      // 1. First run — creates the timestamped file.
      var results = parser.parse(['create_posts_table']);
      cmd.arguments = results;
      await cmd.handle();

      final migrationsDir =
          Directory('${tempDir.path}/lib/database/migrations');
      final filesAfterFirst =
          migrationsDir.listSync().whereType<File>().toList();
      expect(filesAfterFirst.length, 1);

      // 2. Tamper with the file to detect an accidental overwrite.
      filesAfterFirst.first.writeAsStringSync('ORIGINAL');

      // 3. Second run within the same second — path is identical so the
      //    GeneratorCommand guard must block the write.
      results = parser.parse(['create_posts_table']);
      cmd.arguments = results;
      await cmd.handle();

      // 4. The tampered file must still contain 'ORIGINAL'.
      expect(filesAfterFirst.first.readAsStringSync(), 'ORIGINAL');
    });

    test('overwrites existing file with --force', () async {
      // First run
      var results = parser.parse(['create_tags_table']);
      cmd.arguments = results;
      await cmd.handle();

      final migrationsDir =
          Directory('${tempDir.path}/lib/database/migrations');
      final file = migrationsDir.listSync().whereType<File>().first;
      file.writeAsStringSync('ORIGINAL');

      // Re-run with --force
      results = parser.parse(['create_tags_table', '--force']);
      cmd.arguments = results;
      await cmd.handle();

      // Content should be regenerated
      expect(file.readAsStringSync(), isNot('ORIGINAL'));
    });
  });
}
