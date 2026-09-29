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
      StopCommand.stopProcessRunner = _noProcessRunner;
      StopCommand.stopPortProbe = _alwaysFreePort;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      StopCommand.stopKillFunction = Process.killPid;
      StopCommand.stopIsAlive = StopCommand.defaultIsAlive;
      StopCommand.stopGracePeriod = const Duration(seconds: 5);
      StopCommand.stopProcessRunner = Process.run;
      StopCommand.stopPortProbe = StartCommand.defaultPortProbe;
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

    test('finishes with a pid-only SIGTERM when ps cannot run', () async {
      final List<(int, ProcessSignal)> signals = <(int, ProcessSignal)>[];
      StopCommand.stopKillFunction = (int pid, ProcessSignal signal) {
        signals.add((pid, signal));
        return true;
      };
      StopCommand.stopProcessRunner = (String executable, List<String> args) =>
          throw ProcessException(executable, args, 'not found', 2);
      await StateFile.write(<String, dynamic>{
        'pid': 4242,
        'projectRoot': Directory.current.path,
      });
      final BufferedOutput output = BufferedOutput();

      final int code = await StopCommand().handle(
        ArtisanContext.bare(MapInput(const {}), output),
      );

      expect(code, 0, reason: output.content);
      expect(signals, <(int, ProcessSignal)>[(4242, ProcessSignal.sigterm)]);
      expect(output.content, contains('sent SIGTERM to pid=4242 only'));
      expect(await StateFile.read(), isNull);
    });

    test('with state file: emits SIGTERM warning + removes state', () async {
      // Use a high PID very unlikely to be alive; Process.killPid will return
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

  group('StopCommand reaps the process group of the flutter tool', () {
    late Directory tempHome;
    late _FakeAppGroup app;
    late List<int> portProbes;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_stop_group_');
      StateFile.debugHomeOverride = tempHome.path;
      StopCommand.stopGracePeriod = const Duration(milliseconds: 300);
      StopCommand.stopPortProbe = _alwaysFreePort;
      portProbes = <int>[];
    });

    tearDown(() {
      StateFile.debugHomeOverride = null;
      StopCommand.stopKillFunction = Process.killPid;
      StopCommand.stopIsAlive = StopCommand.defaultIsAlive;
      StopCommand.stopGracePeriod = const Duration(seconds: 5);
      StopCommand.stopProcessRunner = Process.run;
      StopCommand.stopPortProbe = StartCommand.defaultPortProbe;
      if (tempHome.existsSync()) tempHome.deleteSync(recursive: true);
    });

    void useApp(_FakeAppGroup fake) {
      app = fake;
      StopCommand.stopKillFunction = fake.kill;
      StopCommand.stopIsAlive = fake.isAlive;
      StopCommand.stopProcessRunner = fake.run;
    }

    Future<(int, BufferedOutput)> stop({
      String device = 'macos',
      int webPort = 3187,
      DateTime? startedAt,
    }) async {
      await StateFile.write(<String, dynamic>{
        if (startedAt != null) 'startedAt': startedAt.toUtc().toIso8601String(),
        'pid': _FakeAppGroup.toolPid,
        'stdinHolderPid': _FakeAppGroup.holderPid,
        'webPort': webPort,
        'device': device,
        'projectRoot': Directory.current.path,
      });
      final BufferedOutput output = BufferedOutput();
      final int code = await StopCommand().handle(
        ArtisanContext.bare(MapInput(const {}), output),
      );
      return (code, output);
    }

    test('SIGTERMs the group, so frontend_server is not orphaned', () async {
      useApp(_FakeAppGroup());

      final (int code, BufferedOutput output) = await stop();

      expect(code, 0, reason: output.content);
      expect(app.signals.first, (-_FakeAppGroup.pgid, ProcessSignal.sigterm));
      expect(app.members, isEmpty);
      expect(output.content, contains('process group ${_FakeAppGroup.pgid}'));
    });

    test('stops the group of a session recorded after its tool started',
        () async {
      useApp(_FakeAppGroup(ageSeconds: 90));

      final (int code, BufferedOutput output) = await stop(
        startedAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );

      expect(code, 0, reason: output.content);
      expect(app.signals.first, (-_FakeAppGroup.pgid, ProcessSignal.sigterm));
      expect(app.members, isEmpty);
    });

    test('leaves alone a pid that now belongs to a newer process', () async {
      // The session went stale (a reboot, a crash) and its numbers were
      // handed out again. Signalling them SIGKILLed an unrelated group, or
      // wedged every later stop on a group it had no right to signal.
      useApp(_FakeAppGroup(ageSeconds: 5));

      final (int code, BufferedOutput output) = await stop(
        startedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(code, 0, reason: output.content);
      expect(
        app.signals.where(((int, ProcessSignal) s) => s.$1 < 0),
        isEmpty,
      );
      expect(
        app.signals.map(((int, ProcessSignal) s) => s.$1),
        isNot(contains(_FakeAppGroup.toolPid)),
      );
      expect(output.content, contains('started after this session'));
      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('finds the group through the holder when the tool is already gone',
        () async {
      // The tool crashed and its frontend_server lives on in the group; the
      // tool pid has no group left to read.
      useApp(
        _FakeAppGroup(
          members: <int>{
            _FakeAppGroup.holderPid,
            _FakeAppGroup.frontendServerPid,
          },
        ),
      );

      final (int code, BufferedOutput output) = await stop();

      expect(code, 0, reason: output.content);
      expect(app.signals.first, (-_FakeAppGroup.pgid, ProcessSignal.sigterm));
      expect(app.members, isEmpty);
    });

    test('deletes the session only after the whole group has exited', () async {
      // The group needs a few polls to exit. Returning straight after the
      // signal let `restart` start on a port the old tool still held.
      useApp(_FakeAppGroup(pollsToExit: 3));

      final (int code, BufferedOutput output) = await stop();

      expect(code, 0, reason: output.content);
      expect(app.members, isEmpty);
      expect(app.stateExistedAtExit, isTrue);
      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('SIGKILLs the group when SIGTERM is ignored, and says so', () async {
      useApp(_FakeAppGroup(ignoresTerm: true));

      final (int code, BufferedOutput output) = await stop();

      expect(code, 0, reason: output.content);
      expect(
        app.signals.take(2),
        <(int, ProcessSignal)>[
          (-_FakeAppGroup.pgid, ProcessSignal.sigterm),
          (-_FakeAppGroup.pgid, ProcessSignal.sigkill),
        ],
      );
      expect(app.members, isEmpty);
      expect(output.content, contains('SIGKILL'));
    });

    test('keeps the session and fails when the group outlives SIGKILL',
        () async {
      // Deleting it would leave a live app nothing can find, and `restart`
      // would start on top of it.
      useApp(_FakeAppGroup(survives: true));

      final (int code, BufferedOutput output) = await stop();

      expect(code, 1);
      expect(output.content, contains('still alive'));
      expect(File(StateFile.path).existsSync(), isTrue);
    });

    test('waits for the web port of a browser session to come free', () async {
      useApp(_FakeAppGroup());
      StopCommand.stopPortProbe = (int port) async {
        portProbes.add(port);
        return portProbes.length > 2;
      };

      final (int code, BufferedOutput output) = await stop(device: 'chrome');

      expect(code, 0, reason: output.content);
      expect(portProbes, <int>[3187, 3187, 3187]);
      expect(output.content, isNot(contains('still bound')));
    });

    test('warns when the web port stays bound after the group is gone',
        () async {
      useApp(_FakeAppGroup());
      StopCommand.stopPortProbe = (int port) async => false;

      final (int code, BufferedOutput output) =
          await stop(device: 'web-server');

      expect(code, 0, reason: output.content);
      expect(output.content, contains('Port 3187 is still bound'));
      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('does not wait on the web port of a device session', () async {
      useApp(_FakeAppGroup());
      StopCommand.stopPortProbe = (int port) async {
        portProbes.add(port);
        return false;
      };

      await stop(device: 'emulator-5554');

      expect(portProbes, isEmpty);
    });

    test('reaps Chrome as a group and waits for its CDP port', () async {
      // Chrome is spawned detached too, so its helpers share its group; a
      // restart on the same --cdp-port probes that port before launching.
      useApp(_FakeAppGroup());
      StopCommand.stopPortProbe = (int port) async {
        portProbes.add(port);
        return portProbes.where((int p) => p == port).length > 1;
      };
      await StateFile.write(<String, dynamic>{
        'chromePid': _FakeAppGroup.toolPid,
        'cdpPort': 9333,
        'projectRoot': Directory.current.path,
      });

      final BufferedOutput output = BufferedOutput();
      final int code = await StopCommand().handle(
        ArtisanContext.bare(MapInput(const {}), output),
      );

      expect(code, 0, reason: output.content);
      expect(app.signals.first, (-_FakeAppGroup.pgid, ProcessSignal.sigterm));
      expect(portProbes, <int>[9333, 9333]);
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
      StopCommand.stopIsAlive = _alwaysDeadProbe;
      adbCalls = <List<String>>[];
      StopCommand.stopProcessRunner = (String executable, List<String> args) {
        // The reaper's `ps` probes are not what these cases are about.
        if (executable == 'ps') return _noProcessRunner(executable, args);
        adbCalls.add(<String>[executable, ...args]);
        return Future<ProcessResult>.value(ProcessResult(0, 0, '', ''));
      };
    });

    tearDown(() {
      StateFile.pathOverride = null;
      StopCommand.stopKillFunction = Process.killPid;
      StopCommand.stopIsAlive = StopCommand.defaultIsAlive;
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
      StopCommand.stopProcessRunner =
          (String executable, List<String> args) => executable == 'ps'
              ? _noProcessRunner(executable, args)
              : Future<ProcessResult>.value(
                  ProcessResult(0, 1, '', 'no devices'),
                );

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
        'edge',
        'web-server',
        'macos',
        '00008110-001A2B3C4D5E601E',
        '4B2C9F0E-7D31-4A5B-9C8E-1F2A3B4C5D6E',
        // The 40-hex UDID of a pre-2018 iPhone.
        'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
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

/// Answers every `ps` probe as "no such process".
Future<ProcessResult> _noProcessRunner(String executable, List<String> args) =>
    Future<ProcessResult>.value(ProcessResult(0, 1, '', ''));

Future<bool> _alwaysFreePort(int port) async => true;

/// The recorded app as a process group: the flutter tool, its FIFO holder and
/// a `frontend_server`, all in [pgid], as a detached spawn leaves them.
///
/// A member exits [pollsToExit] `ps` polls after the first fatal signal
/// reaches it. SIGTERM is fatal unless [ignoresTerm]; nothing is when
/// [survives].
final class _FakeAppGroup {
  _FakeAppGroup({
    this.pollsToExit = 0,
    this.ignoresTerm = false,
    this.survives = false,
    this.ageSeconds = 60,
    Set<int>? members,
  }) : members = members ??
            <int>{
              toolPid,
              holderPid,
              frontendServerPid,
            };

  static const int pgid = 4240;
  static const int toolPid = 4242;
  static const int holderPid = 4243;
  static const int frontendServerPid = 4250;

  final int pollsToExit;
  final bool ignoresTerm;
  final bool survives;

  /// How long ago every member started, as `ps -o etime=` reports it.
  final int ageSeconds;

  final Set<int> members;
  final List<(int, ProcessSignal)> signals = <(int, ProcessSignal)>[];
  final Map<int, int> _countdown = <int, int>{};

  /// Whether the session file still existed when the last member exited.
  bool? stateExistedAtExit;

  bool kill(int target, ProcessSignal signal) {
    signals.add((target, signal));
    final Iterable<int> hit =
        target == -pgid ? members : members.where((int pid) => pid == target);
    if (hit.isEmpty) return false;
    final bool fatal =
        !survives && (signal == ProcessSignal.sigkill || !ignoresTerm);
    if (fatal) {
      for (final int pid in hit) {
        _countdown.putIfAbsent(pid, () => pollsToExit);
      }
      _tick(0);
    }
    return true;
  }

  Future<ProcessResult> run(String executable, List<String> args) async {
    if (executable != 'ps') return ProcessResult(0, 0, '', '');
    _tick(1);
    final String argv = args.join(' ');
    if (argv == '-A -o pgid=,stat=') {
      return ProcessResult(
          0, 0, members.map((int _) => '$pgid S').join('\n'), '');
    }
    // The caller's own group, which the reaper must never signal.
    if (argv == '-o pgid= -p $pid') return ProcessResult(0, 0, '50', '');
    final int target = int.parse(args.last);
    if (!members.contains(target)) return ProcessResult(0, 1, '', '');
    if (argv.startsWith('-o pgid= -p ')) {
      return ProcessResult(0, 0, ' $pgid', '');
    }
    if (argv.startsWith('-o etime= -p ')) {
      final int minutes = ageSeconds ~/ 60;
      final int seconds = ageSeconds % 60;
      return ProcessResult(0, 0, '$minutes:${'$seconds'.padLeft(2, '0')}', '');
    }
    return ProcessResult(0, 1, '', '');
  }

  bool isAlive(int pid) => members.contains(pid);

  void _tick(int step) {
    for (final int pid in _countdown.keys.toList()) {
      final int left = _countdown[pid]! - step;
      _countdown[pid] = left;
      if (left <= 0 && members.remove(pid) && members.isEmpty) {
        stateExistedAtExit = File(StateFile.path).existsSync();
      }
    }
  }
}
