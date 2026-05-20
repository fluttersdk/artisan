import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Constant warning message emitted when a stale `.mcp.json` entry is found.
const _staleMcpWarning =
    'WARN: Stale MCP entry detected. Pre-upgrade .mcp.json points at the '
    'removed fluttersdk_mcp package. Run: dart run fluttersdk_artisan:artisan '
    'mcp:install';

void main() {
  group('DoctorCommand', () {
    test('metadata: name=doctor, boot=none', () {
      final command = DoctorCommand();

      expect(command.name, 'doctor');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('handle runs preflight checks and returns 0 or 1', () async {
      final command = DoctorCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      // Cannot assert pass/fail in arbitrary CI; only that the contract holds.
      expect(code, anyOf(0, 1));
      expect(output.content, contains('flutter --version'));
      expect(output.content, contains('dart --version'));
      expect(output.content, contains('port 3100'));
    });

    test('output lines start with checkmark or cross', () async {
      final command = DoctorCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      final lines = output.content.trim().split('\n');
      expect(lines, hasLength(4));
      for (final line in lines) {
        expect(line.trim(), anyOf(startsWith('✓'), startsWith('✗')));
      }
    });

    test('runs end-to-end without throwing', () async {
      final command = DoctorCommand();
      final ctx = ArtisanContext.bare(MapInput(const {}), BufferedOutput());

      await expectLater(command.handle(ctx), completes);
    });

    // -------------------------------------------------------------------------
    // Stale .mcp.json detection
    // -------------------------------------------------------------------------

    group('stale .mcp.json detection', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('doctor_command_test_');
      });

      tearDown(() async {
        await tempDir.delete(recursive: true);
      });

      test(
          '.mcp.json with fluttersdk_mcp:server in args emits stale entry warning',
          () async {
        // Seed a .mcp.json that references the old fluttersdk_mcp:server entry.
        final mcpJson = File('${tempDir.path}/.mcp.json');
        await mcpJson.writeAsString('''
{
  "mcpServers": {
    "artisan": {
      "command": "dart",
      "args": ["run", "fluttersdk_mcp:server"]
    }
  }
}
''');

        final command = DoctorCommand(workingDir: tempDir.path);
        final output = BufferedOutput();
        final ctx = ArtisanContext.bare(MapInput(const {}), output);

        await command.handle(ctx);

        expect(output.content, contains(_staleMcpWarning));
      });

      test(
          '.mcp.json with new fluttersdk_artisan:mcp entry does NOT emit warning',
          () async {
        // Seed a .mcp.json that already references the new package entry.
        final mcpJson = File('${tempDir.path}/.mcp.json');
        await mcpJson.writeAsString('''
{
  "mcpServers": {
    "artisan": {
      "command": "dart",
      "args": ["run", "fluttersdk_artisan:mcp"]
    }
  }
}
''');

        final command = DoctorCommand(workingDir: tempDir.path);
        final output = BufferedOutput();
        final ctx = ArtisanContext.bare(MapInput(const {}), output);

        await command.handle(ctx);

        expect(output.content, isNot(contains(_staleMcpWarning)));
      });

      test('no .mcp.json at workingDir emits no stale warning', () async {
        // tempDir has no .mcp.json file.
        final command = DoctorCommand(workingDir: tempDir.path);
        final output = BufferedOutput();
        final ctx = ArtisanContext.bare(MapInput(const {}), output);

        await command.handle(ctx);

        expect(output.content, isNot(contains(_staleMcpWarning)));
      });

      test('stale .mcp.json does not change doctor exit code', () async {
        // Doctor exit code must not be affected by the advisory warning alone.
        // We run two instances: one without stale entry, one with stale entry,
        // both pointing at an empty dir (same hard-check environment). Their
        // exit codes must match.
        final mcpJson = File('${tempDir.path}/.mcp.json');
        await mcpJson.writeAsString('''
{
  "mcpServers": {
    "artisan": {
      "command": "dart",
      "args": ["run", "fluttersdk_mcp:server"]
    }
  }
}
''');

        final withStale = DoctorCommand(workingDir: tempDir.path);
        final withoutStale = DoctorCommand(workingDir: tempDir.path);

        // Remove the file between runs to test clean vs stale.
        final codeWithStale = await withStale.handle(
          ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
        );
        await mcpJson.delete();
        final codeWithoutStale = await withoutStale.handle(
          ArtisanContext.bare(MapInput(const {}), BufferedOutput()),
        );

        expect(codeWithStale, equals(codeWithoutStale));
      });
    });

    // -------------------------------------------------------------------------
    // Flutter SDK version check
    // -------------------------------------------------------------------------

    group('_checkFlutterSdkVersion', () {
      /// Builds a fake [ProcessResult] with the given frameworkVersion in JSON.
      ProcessResult fakeVersionResult(String version) => ProcessResult(
            0,
            0,
            jsonEncode({'frameworkVersion': version}),
            '',
          );

      setUp(() {
        // Reset to real runner after each test.
        addTearDown(
          () => DoctorCommand.doctorFlutterRunner =
              (exe, args) => Process.run(exe, args),
        );
      });

      test('version 3.30.0 returns true (exactly at minimum)', () async {
        DoctorCommand.doctorFlutterRunner =
            (_, __) async => fakeVersionResult('3.30.0');

        final result = await DoctorCommand.checkFlutterSdkVersionForTest();

        expect(result, isTrue);
      });

      test('version 3.29.0 returns false (below minimum)', () async {
        DoctorCommand.doctorFlutterRunner =
            (_, __) async => fakeVersionResult('3.29.0');

        final result = await DoctorCommand.checkFlutterSdkVersionForTest();

        expect(result, isFalse);
      });

      test('version 4.0.0 returns true (above minimum)', () async {
        DoctorCommand.doctorFlutterRunner =
            (_, __) async => fakeVersionResult('4.0.0');

        final result = await DoctorCommand.checkFlutterSdkVersionForTest();

        expect(result, isTrue);
      });

      test('malformed JSON output returns false (graceful parse failure)',
          () async {
        DoctorCommand.doctorFlutterRunner =
            (_, __) async => ProcessResult(0, 0, 'not-json-at-all', '');

        final result = await DoctorCommand.checkFlutterSdkVersionForTest();

        expect(result, isFalse);
      });

      test('flutter binary missing (exception thrown) returns false', () async {
        DoctorCommand.doctorFlutterRunner = (_, __) async =>
            throw ProcessException('flutter', ['--version', '--machine'],
                'No such file or directory', 2);

        final result = await DoctorCommand.checkFlutterSdkVersionForTest();

        expect(result, isFalse);
      });

      test(
          'when SDK check fails, doctor exit code is 1 and upgrade warning is emitted',
          () async {
        // Inject a runner that pretends flutter version is below minimum.
        DoctorCommand.doctorFlutterRunner =
            (_, __) async => fakeVersionResult('3.10.0');

        final output = BufferedOutput();
        final ctx = ArtisanContext.bare(MapInput(const {}), output);
        final command = DoctorCommand(workingDir: Directory.systemTemp.path);

        final code = await command.handle(ctx);

        expect(code, equals(1));
        expect(
            output.content, contains(DoctorCommand.cdpUpgradeWarningForTest));
      });

      test('when SDK check passes, no upgrade warning is emitted', () async {
        DoctorCommand.doctorFlutterRunner =
            (_, __) async => fakeVersionResult('3.30.0');

        final output = BufferedOutput();
        final ctx = ArtisanContext.bare(MapInput(const {}), output);
        final command = DoctorCommand(workingDir: Directory.systemTemp.path);

        await command.handle(ctx);

        expect(
          output.content,
          isNot(contains(DoctorCommand.cdpUpgradeWarningForTest)),
        );
      });
    });
  });
}
