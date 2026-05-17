import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_lang_command.dart';

/// Testable subclass — injects temp project root to avoid hitting real filesystem.
class _TestMakeLangCommand extends MakeLangCommand {
  _TestMakeLangCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeLangCommand', () {
    late Directory tempDir;
    late _TestMakeLangCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_lang_');
      cmd = _TestMakeLangCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // ---------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------

    test('name is make:lang', () {
      expect(cmd.name, 'make:lang');
    });

    test('description is not empty', () {
      expect(cmd.description, isNotEmpty);
    });

    // ---------------------------------------------------------------------------
    // JSON file generation
    // ---------------------------------------------------------------------------

    test('creates a .json file at assets/lang/{code}.json', () async {
      cmd.arguments = parser.parse(['tr']);
      await cmd.handle();

      final file = File('${tempDir.path}/assets/lang/tr.json');
      expect(file.existsSync(), isTrue);
    });

    test('generated file has .json extension — not .dart', () async {
      cmd.arguments = parser.parse(['en']);
      await cmd.handle();

      final dartFile = File('${tempDir.path}/assets/lang/en.dart');
      expect(dartFile.existsSync(), isFalse);

      final jsonFile = File('${tempDir.path}/assets/lang/en.json');
      expect(jsonFile.existsSync(), isTrue);
    });

    test('generated file content is "{}"', () async {
      cmd.arguments = parser.parse(['tr']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/assets/lang/tr.json',
      ).readAsStringSync().trim();

      expect(content, '{}');
    });

    // ---------------------------------------------------------------------------
    // Abort / force semantics
    // ---------------------------------------------------------------------------

    test('aborts without --force when file already exists', () async {
      cmd.arguments = parser.parse(['tr']);
      await cmd.handle();

      final file = File('${tempDir.path}/assets/lang/tr.json');
      file.writeAsStringSync('SENTINEL');

      cmd.arguments = parser.parse(['tr']);
      await cmd.handle();

      expect(file.readAsStringSync(), 'SENTINEL');
    });

    test('overwrites with --force when file already exists', () async {
      cmd.arguments = parser.parse(['tr']);
      await cmd.handle();

      final file = File('${tempDir.path}/assets/lang/tr.json');
      file.writeAsStringSync('SENTINEL');

      cmd.arguments = parser.parse(['tr', '--force']);
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('SENTINEL'));
      expect(file.readAsStringSync().trim(), '{}');
    });
  });
}
