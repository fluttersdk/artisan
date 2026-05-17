import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_event_command.dart';

/// Testable subclass — injects temp project root to avoid hitting real filesystem.
class _TestMakeEventCommand extends MakeEventCommand {
  _TestMakeEventCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeEventCommand', () {
    late Directory tempDir;
    late _TestMakeEventCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_event_');
      cmd = _TestMakeEventCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Metadata
    // -----------------------------------------------------------------------

    test('name is make:event', () {
      expect(cmd.name, 'make:event');
    });

    test('description is not empty', () {
      expect(cmd.description, isNotEmpty);
    });

    // -----------------------------------------------------------------------
    // Simple generation — UserLoggedIn
    // -----------------------------------------------------------------------

    test('creates file at correct path for simple name', () async {
      cmd.arguments = parser.parse(['UserLoggedIn']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/events/user_logged_in.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('generated class extends MagicEvent', () async {
      cmd.arguments = parser.parse(['UserLoggedIn']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/events/user_logged_in.dart',
      ).readAsStringSync();

      expect(content, contains('class UserLoggedIn extends MagicEvent'));
    });

    test('generated file has correct class name', () async {
      cmd.arguments = parser.parse(['UserLoggedIn']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/events/user_logged_in.dart',
      ).readAsStringSync();

      expect(content, contains('UserLoggedIn'));
    });

    test('no raw placeholders remain in generated file', () async {
      cmd.arguments = parser.parse(['UserLoggedIn']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/events/user_logged_in.dart',
      ).readAsStringSync();

      expect(content, isNot(contains('{{ className }}')));
      expect(content, isNot(contains('{{ snakeName }}')));
    });

    // -----------------------------------------------------------------------
    // Nested path — Auth/TokenRefreshed
    // -----------------------------------------------------------------------

    test('creates nested file at correct path', () async {
      cmd.arguments = parser.parse(['Auth/TokenRefreshed']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/events/auth/token_refreshed.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('nested class name is last segment only', () async {
      cmd.arguments = parser.parse(['Auth/TokenRefreshed']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/events/auth/token_refreshed.dart',
      ).readAsStringSync();

      expect(content, contains('class TokenRefreshed extends MagicEvent'));
    });

    // -----------------------------------------------------------------------
    // Abort / force semantics
    // -----------------------------------------------------------------------

    test('aborts without --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['UserLoggedIn']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/events/user_logged_in.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — no --force.
      cmd.arguments = parser.parse(['UserLoggedIn']);
      await cmd.handle();

      expect(file.readAsStringSync(), 'SENTINEL');
    });

    test('overwrites with --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['UserLoggedIn']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/events/user_logged_in.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — with --force.
      cmd.arguments = parser.parse(['UserLoggedIn', '--force']);
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('SENTINEL'));
      expect(file.readAsStringSync(), contains('MagicEvent'));
    });
  });
}
