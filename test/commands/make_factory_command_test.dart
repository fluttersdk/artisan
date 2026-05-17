import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_factory_command.dart';

/// Testable subclass that overrides [getProjectRoot] to use a temp directory.
class _TestMakeFactoryCommand extends MakeFactoryCommand {
  _TestMakeFactoryCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeFactoryCommand', () {
    late Directory tempDir;
    late _TestMakeFactoryCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_factory_');
      cmd = _TestMakeFactoryCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('name and description are correct', () {
      expect(cmd.name, 'make:factory');
      expect(cmd.description, isNotEmpty);
    });

    test('creates factory file with Factory suffix auto-appended', () async {
      final results = parser.parse(['User']);
      cmd.arguments = results;

      await cmd.handle();

      final factoryFile = File(
        '${tempDir.path}/lib/database/factories/user_factory.dart',
      );
      expect(factoryFile.existsSync(), isTrue);

      final content = factoryFile.readAsStringSync();
      expect(content, contains('UserFactory'));
    });

    test('does not double-append Factory suffix', () async {
      final results = parser.parse(['UserFactory']);
      cmd.arguments = results;

      await cmd.handle();

      final factoryFile = File(
        '${tempDir.path}/lib/database/factories/user_factory.dart',
      );
      expect(factoryFile.existsSync(), isTrue);

      final content = factoryFile.readAsStringSync();
      // Class name must be UserFactory, NOT UserFactoryFactory
      expect(content, contains('UserFactory'));
      expect(content, isNot(contains('UserFactoryFactory')));
    });

    test('file is placed in lib/database/factories/', () async {
      final results = parser.parse(['Post']);
      cmd.arguments = results;

      await cmd.handle();

      final dir = Directory('${tempDir.path}/lib/database/factories');
      expect(dir.existsSync(), isTrue);

      final file = File('${dir.path}/post_factory.dart');
      expect(file.existsSync(), isTrue);
    });

    test('aborts if file exists without --force', () async {
      final results = parser.parse(['Tag']);
      cmd.arguments = results;
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/database/factories/tag_factory.dart',
      );
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
        '${tempDir.path}/lib/database/factories/category_factory.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      results = parser.parse(['Category', '--force']);
      cmd.arguments = results;
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('ORIGINAL'));
      expect(file.readAsStringSync(), contains('CategoryFactory'));
    });
  });
}
