import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_provider_command.dart';

/// Testable subclass — injects temp project root to avoid hitting real filesystem.
class _TestMakeProviderCommand extends MakeProviderCommand {
  _TestMakeProviderCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

void main() {
  group('MakeProviderCommand', () {
    late Directory tempDir;
    late _TestMakeProviderCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_provider_');
      cmd = _TestMakeProviderCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // ---------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------

    test('name is make:provider', () {
      expect(cmd.name, 'make:provider');
    });

    test('description is not empty', () {
      expect(cmd.description, isNotEmpty);
    });

    // ---------------------------------------------------------------------------
    // Auto-appending ServiceProvider suffix
    // ---------------------------------------------------------------------------

    test('auto-appends ServiceProvider suffix when not present', () async {
      cmd.arguments = parser.parse(['App']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/providers/app_service_provider.dart',
      );
      expect(file.existsSync(), isTrue);
    });

    test('generated class name includes ServiceProvider suffix', () async {
      cmd.arguments = parser.parse(['App']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/providers/app_service_provider.dart',
      ).readAsStringSync();

      expect(content,
          contains('class AppServiceProvider extends ServiceProvider'));
    });

    test('does not double-append ServiceProvider when already present',
        () async {
      cmd.arguments = parser.parse(['AppServiceProvider']);
      await cmd.handle();

      // Should be app_service_provider.dart — not app_service_provider_service_provider.dart
      final file = File(
        '${tempDir.path}/lib/app/providers/app_service_provider.dart',
      );
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content,
          contains('class AppServiceProvider extends ServiceProvider'));
    });

    test('generated file contains register() and boot() methods', () async {
      cmd.arguments = parser.parse(['App']);
      await cmd.handle();

      final content = File(
        '${tempDir.path}/lib/app/providers/app_service_provider.dart',
      ).readAsStringSync();

      expect(content, contains('void register()'));
      expect(content, contains('Future<void> boot()'));
    });

    // ---------------------------------------------------------------------------
    // Abort / force semantics
    // ---------------------------------------------------------------------------

    test('aborts without --force when file already exists', () async {
      cmd.arguments = parser.parse(['App']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/providers/app_service_provider.dart',
      );
      file.writeAsStringSync('SENTINEL');

      cmd.arguments = parser.parse(['App']);
      await cmd.handle();

      expect(file.readAsStringSync(), 'SENTINEL');
    });

    test('overwrites with --force when file already exists', () async {
      cmd.arguments = parser.parse(['App']);
      await cmd.handle();

      final file = File(
        '${tempDir.path}/lib/app/providers/app_service_provider.dart',
      );
      file.writeAsStringSync('SENTINEL');

      cmd.arguments = parser.parse(['App', '--force']);
      await cmd.handle();

      expect(file.readAsStringSync(), isNot('SENTINEL'));
      expect(file.readAsStringSync(), contains('ServiceProvider'));
    });
  });
}
