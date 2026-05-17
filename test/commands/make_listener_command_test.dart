import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_listener_command.dart';

/// Testable subclass — injects temp project root to avoid hitting real filesystem.
class _TestMakeListenerCommand extends MakeListenerCommand {
  _TestMakeListenerCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeListenerCommand', () {
    late Directory tempDir;
    late _TestMakeListenerCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_listener_');
      cmd = _TestMakeListenerCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Metadata
    // -----------------------------------------------------------------------

    test('name is make:listener', () {
      expect(cmd.name, 'make:listener');
    });

    test('description is not empty', () {
      expect(cmd.description, isNotEmpty);
    });

    // -----------------------------------------------------------------------
    // Generation with --event option — AuthRestore
    // -----------------------------------------------------------------------

    test('creates file at correct path for simple name', () async {
      cmd.arguments =
          parser.parse(['AuthRestore', '--event=UserLoggedInEvent']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('generated class extends MagicListener with specified event type',
        () async {
      cmd.arguments =
          parser.parse(['AuthRestore', '--event=UserLoggedInEvent']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      ).readAsStringSync();

      expect(
        content,
        contains('class AuthRestore extends MagicListener<UserLoggedInEvent>'),
      );
    });

    test('handle method uses specified event type', () async {
      cmd.arguments =
          parser.parse(['AuthRestore', '--event=UserLoggedInEvent']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      ).readAsStringSync();

      expect(content, contains('Future<void> handle(UserLoggedInEvent event)'));
    });

    // -----------------------------------------------------------------------
    // Generation without --event — falls back to MagicEvent
    // -----------------------------------------------------------------------

    test('uses MagicEvent as default when --event is not provided', () async {
      cmd.arguments = parser.parse(['AuthRestore']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      ).readAsStringSync();

      expect(
        content,
        contains('class AuthRestore extends MagicListener<MagicEvent>'),
      );
    });

    test('handle method uses MagicEvent when no --event provided', () async {
      cmd.arguments = parser.parse(['AuthRestore']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      ).readAsStringSync();

      expect(content, contains('Future<void> handle(MagicEvent event)'));
    });

    test('no raw placeholders remain in generated file', () async {
      cmd.arguments =
          parser.parse(['AuthRestore', '--event=UserLoggedInEvent']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      ).readAsStringSync();

      expect(content, isNot(contains('{{ className }}')));
      expect(content, isNot(contains('{{ snakeName }}')));
      expect(content, isNot(contains('{{ eventClass }}')));
    });

    // -----------------------------------------------------------------------
    // Nested path — Auth/RestoreSession
    // -----------------------------------------------------------------------

    test('creates nested file at correct path', () async {
      cmd.arguments = parser.parse(['Auth/RestoreSession']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/listeners/auth/restore_session.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('nested class name is last segment only', () async {
      cmd.arguments =
          parser.parse(['Auth/RestoreSession', '--event=UserLoggedInEvent']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/listeners/auth/restore_session.dart',
      ).readAsStringSync();

      expect(
        content,
        contains(
            'class RestoreSession extends MagicListener<UserLoggedInEvent>'),
      );
    });

    // -----------------------------------------------------------------------
    // Abort / force semantics
    // -----------------------------------------------------------------------

    test('aborts without --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['AuthRestore']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — no --force.
      cmd.arguments = parser.parse(['AuthRestore']);
      await cmd.handle();

      expect(file.readAsStringSync(), 'SENTINEL');
    });

    test('overwrites with --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['AuthRestore']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/listeners/auth_restore.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — with --force.
      cmd.arguments = parser.parse(['AuthRestore', '--force']);
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('SENTINEL'));
      expect(file.readAsStringSync(), contains('MagicListener'));
    });
  });
}
