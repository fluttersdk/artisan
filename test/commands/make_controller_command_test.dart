import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_controller_command.dart';

void main() {
  group('MakeControllerCommand', () {
    late Directory tempDir;
    late MakeControllerCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_ctrl_');
      cmd = MakeControllerCommand(testRoot: tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Basic scaffolding
    // -----------------------------------------------------------------------

    test('generates monitor_controller.dart from "Monitor" input', () async {
      cmd.arguments = parser.parse(['Monitor']);

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test(
        'generated file contains MonitorController class extending MagicController',
        () async {
      cmd.arguments = parser.parse(['Monitor']);

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      ).readAsStringSync();
      expect(
          content, contains('class MonitorController extends MagicController'));
    });

    test('auto-appends Controller suffix when not present', () async {
      cmd.arguments = parser.parse(['Monitor']);

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('does not double-append Controller when already present', () async {
      cmd.arguments = parser.parse(['MonitorController']);

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      );
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(
          content, contains('class MonitorController extends MagicController'));
      expect(content, isNot(contains('MonitorControllerController')));
    });

    // -----------------------------------------------------------------------
    // Nested paths
    // -----------------------------------------------------------------------

    test('nested path creates correct directory structure', () async {
      cmd.arguments = parser.parse(['Admin/Dashboard']);

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/controllers/admin/dashboard_controller.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('nested path file contains DashboardController class', () async {
      cmd.arguments = parser.parse(['Admin/Dashboard']);

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/controllers/admin/dashboard_controller.dart',
      ).readAsStringSync();
      expect(content,
          contains('class DashboardController extends MagicController'));
    });

    // -----------------------------------------------------------------------
    // Resource stub
    // -----------------------------------------------------------------------

    test('--resource flag uses resource stub with CRUD methods', () async {
      cmd.arguments = parser.parse(['Monitor', '--resource']);

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      ).readAsStringSync();
      // Resource stub has index, create, show, edit, destroy methods
      expect(content, contains('Widget index()'));
      expect(content, contains('Widget create()'));
      expect(content, contains('Widget show('));
      expect(content, contains('Widget edit('));
      expect(content, contains('Future<void> destroy('));
    });

    test('basic stub does not have destroy method', () async {
      cmd.arguments = parser.parse(['Monitor']);

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      ).readAsStringSync();
      expect(content, isNot(contains('Future<void> destroy(')));
    });

    // -----------------------------------------------------------------------
    // --force flag
    // -----------------------------------------------------------------------

    test('returns error when file already exists without --force', () async {
      // First create
      cmd.arguments = parser.parse(['Monitor']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      // Second attempt — should NOT overwrite
      final cmd2 = MakeControllerCommand(testRoot: tempDir.path);
      cmd2.arguments = parser.parse(['Monitor']);
      await cmd2.handle();

      expect(file.readAsStringSync(), equals('ORIGINAL'));
    });

    test('overwrites existing file with --force flag', () async {
      // First create
      cmd.arguments = parser.parse(['Monitor']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/controllers/monitor_controller.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      // Second attempt with --force
      final cmd2 = MakeControllerCommand(testRoot: tempDir.path);
      final parser2 = ArgParser();
      cmd2.configure(parser2);
      cmd2.arguments = parser2.parse(['Monitor', '--force']);
      await cmd2.handle();

      expect(file.readAsStringSync(), isNot(equals('ORIGINAL')));
      expect(file.readAsStringSync(), contains('MonitorController'));
    });

    // -----------------------------------------------------------------------
    // Missing argument
    // -----------------------------------------------------------------------

    test('returns early when no name argument provided', () async {
      cmd.arguments = parser.parse([]);

      // Should not throw — just print error
      expect(() async => cmd.handle(), returnsNormally);
    });
  });
}
