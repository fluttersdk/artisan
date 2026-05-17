import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_request_command.dart';

void main() {
  group('MakeRequestCommand', () {
    late Directory tempDir;
    late MakeRequestCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_request_');
      cmd = MakeRequestCommand(testRoot: tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('creates request file with correct path for simple name', () async {
      final results = parser.parse(['StoreMonitor']);
      cmd.arguments = results;

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/validation/requests/store_monitor_request.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('auto-appends Request suffix when not present', () async {
      final results = parser.parse(['StoreMonitor']);
      cmd.arguments = results;

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/validation/requests/store_monitor_request.dart',
      ).readAsStringSync();

      expect(content, contains('class StoreMonitorRequest'));
    });

    test('does not double-append Request when already present', () async {
      final results = parser.parse(['StoreMonitorRequest']);
      cmd.arguments = results;

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/validation/requests/store_monitor_request.dart',
      );
      final content = file.readAsStringSync();
      expect(content, contains('class StoreMonitorRequest'));
      expect(content, isNot(contains('class StoreMonitorRequestRequest')));
    });

    test('generated file has rules() method', () async {
      final results = parser.parse(['StoreMonitor']);
      cmd.arguments = results;

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/validation/requests/store_monitor_request.dart',
      ).readAsStringSync();

      expect(content, contains('rules()'));
    });

    test('all placeholders are replaced in output', () async {
      final results = parser.parse(['StoreMonitor']);
      cmd.arguments = results;

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/validation/requests/store_monitor_request.dart',
      ).readAsStringSync();

      expect(content, isNot(contains('{{ className }}')));
      expect(content, isNot(contains('{{ snakeName }}')));
    });

    test('aborts with error when file already exists without --force',
        () async {
      // Create the file first.
      var results = parser.parse(['StoreMonitor']);
      cmd.arguments = results;
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/validation/requests/store_monitor_request.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      // Second run — should abort.
      results = parser.parse(['StoreMonitor']);
      cmd.arguments = results;
      await cmd.handle();

      expect(file.readAsStringSync(), 'ORIGINAL');
    });

    test('overwrites existing file when --force is passed', () async {
      // Create the file first.
      var results = parser.parse(['StoreMonitor']);
      cmd.arguments = results;
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/validation/requests/store_monitor_request.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      // Second run with --force.
      results = parser.parse(['StoreMonitor', '--force']);
      cmd.arguments = results;
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('ORIGINAL'));
      expect(file.readAsStringSync(), contains('class StoreMonitorRequest'));
    });
  });
}
