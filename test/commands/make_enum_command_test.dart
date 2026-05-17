import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_enum_command.dart';

/// Testable subclass — injects temp project root to avoid hitting real filesystem.
class _TestMakeEnumCommand extends MakeEnumCommand {
  _TestMakeEnumCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeEnumCommand', () {
    late Directory tempDir;
    late _TestMakeEnumCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_enum_');
      cmd = _TestMakeEnumCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Metadata
    // -----------------------------------------------------------------------

    test('name is make:enum', () {
      expect(cmd.name, 'make:enum');
    });

    test('description is not empty', () {
      expect(cmd.description, isNotEmpty);
    });

    // -----------------------------------------------------------------------
    // Simple generation — MonitorType
    // -----------------------------------------------------------------------

    test('creates file at correct path for simple name', () async {
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/enums/monitor_type.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('generated class has correct enum name', () async {
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/enums/monitor_type.dart',
      ).readAsStringSync();

      expect(content, contains('enum MonitorType'));
    });

    test('generated enum has value and label fields', () async {
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/enums/monitor_type.dart',
      ).readAsStringSync();

      expect(content, contains('final String value'));
      expect(content, contains('final String label'));
    });

    test('generated enum has fromValue static method', () async {
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/enums/monitor_type.dart',
      ).readAsStringSync();

      expect(content, contains('fromValue'));
    });

    test('snakeName placeholder is replaced with snake_case', () async {
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/enums/monitor_type.dart',
      ).readAsStringSync();

      // Should not contain raw placeholder
      expect(content, isNot(contains('{{ snakeName }}')));
    });

    // -----------------------------------------------------------------------
    // Nested path — Status/OrderStatus
    // -----------------------------------------------------------------------

    test('creates nested file at correct path', () async {
      cmd.arguments = parser.parse(['Status/OrderStatus']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/enums/status/order_status.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('nested class name is last segment only', () async {
      cmd.arguments = parser.parse(['Status/OrderStatus']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/enums/status/order_status.dart',
      ).readAsStringSync();

      expect(content, contains('enum OrderStatus'));
    });

    // -----------------------------------------------------------------------
    // Abort / force semantics
    // -----------------------------------------------------------------------

    test('aborts without --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/enums/monitor_type.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — no --force.
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      expect(file.readAsStringSync(), 'SENTINEL');
    });

    test('overwrites with --force when file already exists', () async {
      // First creation.
      cmd.arguments = parser.parse(['MonitorType']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/enums/monitor_type.dart',
      );
      file.writeAsStringSync('SENTINEL');

      // Second attempt — with --force.
      cmd.arguments = parser.parse(['MonitorType', '--force']);
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('SENTINEL'));
      expect(file.readAsStringSync(), contains('enum MonitorType'));
    });
  });
}
