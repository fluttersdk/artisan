import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_policy_command.dart';

void main() {
  group('MakePolicyCommand', () {
    late Directory tempDir;
    late MakePolicyCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_policy_');
      cmd = MakePolicyCommand(testRoot: tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('creates policy file with correct path for simple name', () async {
      final results = parser.parse(['Monitor']);
      cmd.arguments = results;

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('auto-appends Policy suffix when not present', () async {
      final results = parser.parse(['Monitor']);
      cmd.arguments = results;

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      );
      final content = file.readAsStringSync();
      expect(content, contains('class MonitorPolicy'));
    });

    test('does not double-append Policy when already present', () async {
      final results = parser.parse(['MonitorPolicy']);
      cmd.arguments = results;

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      );
      final content = file.readAsStringSync();
      expect(content, contains('class MonitorPolicy'));
      expect(content, isNot(contains('class MonitorPolicyPolicy')));
    });

    test('generated file extends Policy and defines Gate abilities', () async {
      final results = parser.parse(['Monitor']);
      cmd.arguments = results;

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      ).readAsStringSync();

      expect(content, contains('extends Policy'));
      expect(content, contains('Gate.define'));
    });

    test('--model option replaces modelClass placeholder', () async {
      final results = parser.parse(['Monitor', '--model=Monitor']);
      cmd.arguments = results;

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      ).readAsStringSync();

      expect(content, contains('Monitor'));
      expect(content, isNot(contains('{{ modelClass }}')));
    });

    test('uses dynamic when --model not provided', () async {
      final results = parser.parse(['Monitor']);
      cmd.arguments = results;

      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      ).readAsStringSync();

      expect(content, isNot(contains('{{ modelClass }}')));
    });

    test('supports nested path Admin/Dashboard', () async {
      final results = parser.parse(['Admin/Dashboard']);
      cmd.arguments = results;

      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/policies/admin/dashboard_policy.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('aborts with error when file already exists without --force',
        () async {
      // Create the file first.
      var results = parser.parse(['Monitor']);
      cmd.arguments = results;
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      // Second run — should abort.
      results = parser.parse(['Monitor']);
      cmd.arguments = results;
      await cmd.handle();

      expect(file.readAsStringSync(), 'ORIGINAL');
    });

    test('overwrites existing file when --force is passed', () async {
      // Create the file first.
      var results = parser.parse(['Monitor']);
      cmd.arguments = results;
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/policies/monitor_policy.dart',
      );
      file.writeAsStringSync('ORIGINAL');

      // Second run with --force.
      results = parser.parse(['Monitor', '--force']);
      cmd.arguments = results;
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('ORIGINAL'));
      expect(file.readAsStringSync(), contains('class MonitorPolicy'));
    });
  });
}
