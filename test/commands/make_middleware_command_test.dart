import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_middleware_command.dart';

/// Testable subclass — injects temp project root to avoid hitting real filesystem.
class _TestMakeMiddlewareCommand extends MakeMiddlewareCommand {
  _TestMakeMiddlewareCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeMiddlewareCommand', () {
    late Directory tempDir;
    late _TestMakeMiddlewareCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_middleware_');
      cmd = _TestMakeMiddlewareCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // ---------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------

    test('name is make:middleware', () {
      expect(cmd.name, 'make:middleware');
    });

    test('description is not empty', () {
      expect(cmd.description, isNotEmpty);
    });

    // ---------------------------------------------------------------------------
    // Simple generation — EnsureAuthenticated
    // ---------------------------------------------------------------------------

    test('creates file at correct path for simple name', () async {
      cmd.arguments = parser.parse(['EnsureAuthenticated']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/middleware/ensure_authenticated.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('generated class extends MagicMiddleware', () async {
      cmd.arguments = parser.parse(['EnsureAuthenticated']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/middleware/ensure_authenticated.dart',
      ).readAsStringSync();

      expect(content,
          contains('class EnsureAuthenticated extends MagicMiddleware'));
    });

    test('generated file contains snakeName placeholder replaced', () async {
      cmd.arguments = parser.parse(['EnsureAuthenticated']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/middleware/ensure_authenticated.dart',
      ).readAsStringSync();

      // The stub uses {{ snakeName }} in the registration example.
      expect(content, contains('ensure_authenticated'));
    });

    // ---------------------------------------------------------------------------
    // Nested path — Admin/RoleCheck
    // ---------------------------------------------------------------------------

    test('creates nested file at correct path', () async {
      cmd.arguments = parser.parse(['Admin/RoleCheck']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/middleware/admin/role_check.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('nested class name is last segment only', () async {
      cmd.arguments = parser.parse(['Admin/RoleCheck']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/middleware/admin/role_check.dart',
      ).readAsStringSync();

      expect(content, contains('class RoleCheck extends MagicMiddleware'));
    });

    // ---------------------------------------------------------------------------
    // Abort / force semantics
    // ---------------------------------------------------------------------------

    test('aborts without --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['EnsureAuthenticated']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/middleware/ensure_authenticated.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — no --force.
      cmd.arguments = parser.parse(['EnsureAuthenticated']);
      await cmd.handle();

      expect(file.readAsStringSync(), 'SENTINEL');
    });

    test('overwrites with --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['EnsureAuthenticated']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/middleware/ensure_authenticated.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — with --force.
      cmd.arguments = parser.parse(['EnsureAuthenticated', '--force']);
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('SENTINEL'));
      expect(file.readAsStringSync(), contains('MagicMiddleware'));
    });
  });
}
