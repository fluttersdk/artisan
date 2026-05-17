import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:magic_cli/src/commands/key_generate_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late KeyGenerateCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_test_');
    Directory.current = tempDir;

    // Create a dummy pubspec.yaml to satisfy FileHelper.findProjectRoot()
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('name: test_app');

    command = KeyGenerateCommand();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('KeyGenerateCommand', () {
    test('it generates .env file with APP_KEY if it does not exist', () async {
      // 1. Prepare command with mock arguments
      final parser = ArgParser();
      command.configure(parser);
      command.arguments = parser.parse([]);

      // 2. Run command
      await command.handle();

      // 3. Verify .env exists and has APP_KEY
      final envFile = File('${tempDir.path}/.env');
      expect(envFile.existsSync(), isTrue);

      final content = envFile.readAsStringSync();
      expect(content, contains('APP_KEY=base64:'));

      // 4. Verify key format (32 bytes base64 encoded)
      final keyPart = content.split('APP_KEY=base64:')[1].trim();
      final bytes = base64.decode(keyPart);
      expect(bytes.length, 32);
    });

    test('it updates existing APP_KEY in .env', () async {
      // 1. Create existing .env
      final envFile = File('${tempDir.path}/.env');
      envFile.writeAsStringSync('APP_KEY=base64:oldkey\nOTHER_VAR=value');

      // 2. Run command
      final parser = ArgParser();
      command.configure(parser);
      command.arguments = parser.parse([]);
      await command.handle();

      // 3. Verify .env updated
      final content = envFile.readAsStringSync();
      expect(content, contains('APP_KEY=base64:'));
      expect(content, isNot(contains('oldkey')));
      expect(content, contains('OTHER_VAR=value'));

      // Ensure it didn't duplicate the line
      final lines =
          content.split('\n').where((l) => l.startsWith('APP_KEY=')).toList();
      expect(lines.length, 1);
    });

    test(
        'it shows the key without writing to .env when --show flag is provided',
        () async {
      // 1. Run command with --show
      final parser = ArgParser();
      command.configure(parser);
      command.arguments = parser.parse(['--show']);

      await command.handle();

      // 2. Verify .env does NOT exist
      final envFile = File('${tempDir.path}/.env');
      expect(envFile.existsSync(), isFalse);
    });
  });
}
