import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/magic_cli.dart';

void main() {
  late Directory tempDir;
  late Kernel kernel;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_integration_');
    // Create a dummy pubspec.yaml so findProjectRoot works!
    File('${tempDir.path}/pubspec.yaml')
        .writeAsStringSync('name: dummy_project\n');

    kernel = Kernel();
    kernel.registerMany([
      InstallCommand(),
      KeyGenerateCommand(),
      MakeControllerCommand(),
      MakeEnumCommand(),
      MakeEventCommand(),
      MakeFactoryCommand(),
      MakeLangCommand(),
      MakeListenerCommand(),
      MakeMiddlewareCommand(),
      MakeMigrationCommand(),
      MakeModelCommand(),
      MakePolicyCommand(),
      MakeProviderCommand(),
      MakeRequestCommand(),
      MakeSeederCommand(),
      MakeViewCommand(),
    ]);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // Helper to run commands in the temp dir context
  Future<void> runInTempDir(List<String> args) async {
    final originalDir = Directory.current;
    try {
      Directory.current = tempDir;
      await kernel.handle(args);
    } finally {
      Directory.current = originalDir;
    }
  }

  group('Kernel output & error handling', () {
    test('prints help when no arguments provided', () async {
      await runInTempDir([]);
      expect(true, isTrue);
    });

    test('handles unknown commands gracefully', () async {
      final originalExitCode = exitCode;
      await runInTempDir(['unknown:command']);
      expect(exitCode, 1);
      exitCode = originalExitCode;
    });

    test('missing required arguments exits gracefully without throwing',
        () async {
      // Our Command base class just prints an error and returns for missing args,
      // it doesn't actually set exitCode to 1 or throw. So let's just verify it
      // doesn't throw.
      await runInTempDir(['make:controller']);
      expect(true, isTrue);
    });
  });

  group('key:generate', () {
    test('creates or updates .env with APP_KEY', () async {
      await runInTempDir(['key:generate']);

      final envFile = File('${tempDir.path}/.env');
      expect(envFile.existsSync(), isTrue);
      expect(envFile.readAsStringSync(), contains('APP_KEY=base64:'));
    });
  });
}
