import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StopCommand', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_stop_');
      StateFile.debugHomeOverride = tempHome.path;
      // Reset CDP test seams to known defaults before every test.
      StopCommand.stopKillFunction = _noOpKill;
      StopCommand.stopIsAlive = _alwaysDeadProbe;
      StopCommand.stopGracePeriod = Duration.zero;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      StopCommand.stopKillFunction = Process.killPid;
      StopCommand.stopIsAlive = StopCommand.defaultIsAlive;
      StopCommand.stopGracePeriod = const Duration(seconds: 2);
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('metadata: name=stop, boot=none', () {
      final command = StopCommand();

      expect(command.name, 'stop');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('returns 0 with friendly message when no state file', () async {
      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      expect(output.content, contains('nothing to stop'));
    });

    test('with state file: emits SIGTERM warning + removes state', () async {
      // Use a high PID very unlikely to be alive — Process.killPid will return
      // false but won't throw, so the success branch fires.
      await StateFile.write(<String, dynamic>{
        'pid': 999999999,
        'stdinHolderPid': 999999998,
        'stdinPipe':
            '/tmp/fake_fifo_does_not_exist_${DateTime.now().microsecondsSinceEpoch}',
      });
      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      expect(output.content, contains('SIGTERM'));
      expect(output.content, contains('state.json removed'));
      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('handles state file without pid/holder/pipe entries', () async {
      await StateFile.write(<String, dynamic>{});
      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('deletes the FIFO file when present', () async {
      final fifoPath = '${tempHome.path}/fake.fifo';
      File(fifoPath).writeAsStringSync('');

      await StateFile.write(<String, dynamic>{
        'stdinPipe': fifoPath,
      });

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      expect(File(fifoPath).existsSync(), isFalse);
    });

    // CDP / Chrome cleanup tests (Step 13).

    test(
        'state without chromePid: existing behavior unchanged, no CDP output lines',
        () async {
      await StateFile.write(<String, dynamic>{
        'pid': 999999999,
      });
      final killLog = <int>[];
      StopCommand.stopKillFunction = (pid, signal) {
        killLog.add(pid);
        return false;
      };

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      // Chrome kill was only called for flutter PID (999999999), not a second
      // chromePid entry.
      expect(killLog, equals([999999999]));
      expect(output.content, isNot(contains('Chrome SIGTERM')));
      expect(output.content, isNot(contains('tmpProfileDir')));
    });

    test('state with chromePid: SIGTERM is sent to that PID via kill seam',
        () async {
      const chromePid = 12345;
      await StateFile.write(<String, dynamic>{
        'chromePid': chromePid,
      });

      final killLog = <({int pid, ProcessSignal signal})>[];
      StopCommand.stopKillFunction = (pid, signal) {
        killLog.add((pid: pid, signal: signal));
        return true;
      };

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      expect(
        killLog,
        contains(
          predicate<({int pid, ProcessSignal signal})>(
            (e) => e.pid == chromePid && e.signal == ProcessSignal.sigterm,
          ),
        ),
      );
      expect(output.content, contains('Chrome SIGTERM'));
      expect(output.content, contains('$chromePid'));
    });

    test(
        'state with chromePid + tmpProfileDir: profile dir is deleted after kill',
        () async {
      final profileDir = Directory(
          '${tempHome.path}/chrome_profile_${DateTime.now().microsecondsSinceEpoch}');
      profileDir.createSync(recursive: true);
      File('${profileDir.path}/prefs').writeAsStringSync('{}');

      await StateFile.write(<String, dynamic>{
        'chromePid': 12345,
        'tmpProfileDir': profileDir.path,
      });

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      expect(profileDir.existsSync(), isFalse);
      expect(output.content, contains('tmpProfileDir'));
      expect(output.content, contains(profileDir.path));
    });

    test(
        'state with chromePid but no tmpProfileDir: only kill, no dir delete attempt',
        () async {
      const chromePid = 22222;
      await StateFile.write(<String, dynamic>{
        'chromePid': chromePid,
      });

      StopCommand.stopKillFunction = (pid, signal) => false;

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      // No tmpProfileDir in state; the delete branch is gated on the field
      // being non-null + non-empty, so the success line for tmpProfileDir
      // is the observable proof that the branch did not execute.
      expect(output.content, isNot(contains('tmpProfileDir')));
      // killPid returned false; the cleanup branch surfaces a "not delivered"
      // warning instead of the success line so the operator sees that the
      // signal landed on no process. The phrase still mentions Chrome SIGTERM.
      expect(output.content,
          contains('Chrome SIGTERM not delivered to pid=22222'));
    });

    test('tmpProfileDir does not exist on disk: cleanup is a no-op, no error',
        () async {
      const nonExistentDir = '/tmp/artisan_test_non_existent_profile_dir_xyz';
      await StateFile.write(<String, dynamic>{
        'chromePid': 33333,
        'tmpProfileDir': nonExistentDir,
      });

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      // Must not throw.
      final code = await command.handle(ctx);

      expect(code, 0);
      // The success line for tmpProfileDir is NOT emitted when the dir
      // does not exist (cleanup was a no-op, no output is correct behavior
      // per the plan: only emit when dir.existsSync() is true).
    });

    test(
        'full cleanup: ctx.output emits Chrome SIGTERM success + tmpProfileDir cleaned',
        () async {
      final profileDir =
          Directory('${tempHome.path}/chrome_profile_full_cleanup');
      profileDir.createSync(recursive: true);

      await StateFile.write(<String, dynamic>{
        'chromePid': 44444,
        'tmpProfileDir': profileDir.path,
      });

      // Model the happy path: Process.killPid returns true when the signal
      // was delivered, which is the precondition for the "sent" success line.
      StopCommand.stopKillFunction = (pid, signal) => true;

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      expect(output.content, contains('Chrome SIGTERM sent to pid=44444'));
      expect(
        output.content,
        contains('tmpProfileDir ${profileDir.path} cleaned'),
      );
    });
  });

  group('StopCommand on an Android device', () {
    late Directory tempHome;
    late Directory project;
    late List<List<String>> adbCalls;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_stop_adb_');
      project = Directory('${tempHome.path}/app')..createSync();
      // An explicit session path is what lets the recorded projectRoot differ
      // from the working directory without tripping the ownership guard.
      StateFile.pathOverride = '${tempHome.path}/state.json';
      StopCommand.stopKillFunction = _noOpKill;
      adbCalls = <List<String>>[];
      StopCommand.stopProcessRunner = (String executable, List<String> args) {
        adbCalls.add(<String>[executable, ...args]);
        return Future<ProcessResult>.value(ProcessResult(0, 0, '', ''));
      };
    });

    tearDown(() {
      StateFile.pathOverride = null;
      StopCommand.stopKillFunction = Process.killPid;
      StopCommand.stopProcessRunner = Process.run;
      if (tempHome.existsSync()) tempHome.deleteSync(recursive: true);
    });

    void seedGradle(String fileName, String body) {
      File('${project.path}/android/app/$fileName')
        ..createSync(recursive: true)
        ..writeAsStringSync(body);
    }

    Future<BufferedOutput> stopDevice(String device) async {
      await StateFile.write(<String, dynamic>{
        'pid': 4242,
        'device': device,
        'projectRoot': project.path,
      });
      final BufferedOutput output = BufferedOutput();
      await StopCommand().handle(
        ArtisanContext.bare(MapInput(const {}), output),
      );
      return output;
    }

    test('force-stops the app the flutter tool leaves running', () async {
      seedGradle('build.gradle', '''
android {
    defaultConfig {
        applicationId "com.example.uptizm"
        applicationIdSuffix ".ignored"
    }
}
''');

      await stopDevice('emulator-5554');

      expect(adbCalls, <List<String>>[
        <String>[
          'adb',
          '-s',
          'emulator-5554',
          'shell',
          'am',
          'force-stop',
          'com.example.uptizm',
        ],
      ]);
    });

    test('reads the id from a Kotlin DSL build file', () async {
      seedGradle('build.gradle.kts', 'applicationId = "dev.fluttersdk.kts"');

      await stopDevice('emulator-5554');

      expect(adbCalls.single.last, 'dev.fluttersdk.kts');
    });

    test('warns and keeps going when adb answers non-zero', () async {
      seedGradle('build.gradle', 'applicationId "com.example.uptizm"');
      StopCommand.stopProcessRunner = (String executable, List<String> args) =>
          Future<ProcessResult>.value(ProcessResult(0, 1, '', 'no devices'));

      final BufferedOutput output = await stopDevice('emulator-5554');

      expect(output.content, contains('force-stop'));
      expect(output.content, contains('no devices'));
      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('warns instead of guessing when no application id is found', () async {
      final BufferedOutput output = await stopDevice('emulator-5554');

      expect(adbCalls, isEmpty);
      expect(output.content, contains('applicationId'));
      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('never reaches for adb on a web, desktop or iOS target', () async {
      seedGradle('build.gradle', 'applicationId "com.example.uptizm"');

      for (final String device in <String>[
        'chrome',
        'web-server',
        'macos',
        '00008110-001A2B3C4D5E601E',
        '4B2C9F0E-7D31-4A5B-9C8E-1F2A3B4C5D6E',
      ]) {
        await stopDevice(device);
      }

      expect(adbCalls, isEmpty);
    });
  });
}

// Test seam helpers.

bool _noOpKill(int pid, ProcessSignal signal) => false;

bool _alwaysDeadProbe(int pid) => false;
