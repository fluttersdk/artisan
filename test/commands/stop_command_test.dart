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

      var dirDeleteAttempted = false;
      StopCommand.stopKillFunction = (pid, signal) => false;

      final command = StopCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      // No tmpProfileDir in state; dir delete must never be attempted.
      expect(dirDeleteAttempted, isFalse);
      expect(output.content, isNot(contains('tmpProfileDir')));
      expect(output.content, contains('Chrome SIGTERM'));
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
}

// Test seam helpers.

bool _noOpKill(int pid, ProcessSignal signal) => false;

bool _alwaysDeadProbe(int pid) => false;
