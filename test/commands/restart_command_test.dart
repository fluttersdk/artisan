import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('RestartCommand', () {
    test('metadata: name=restart, boot=none', () {
      final command = RestartCommand();

      expect(command.name, 'restart');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('inherits from ArtisanCommand', () {
      final command = RestartCommand();

      expect(command, isA<ArtisanCommand>());
    });

    test('description mentions stop + start', () {
      final command = RestartCommand();

      expect(command.description.toLowerCase(), contains('stop'));
      expect(command.description.toLowerCase(), contains('start'));
    });

    test('configure declares --cdp-port so restart --cdp-port=N parses', () {
      final parser = ArgParser();
      RestartCommand().configure(parser);

      expect(parser.options.keys, contains('cdp-port'));
      // The parser accepts the flag the docblock promises wins on restart.
      expect(parser.parse(['--cdp-port=4444']).option('cdp-port'), '4444');
    });
  });

  // ---------------------------------------------------------------------------
  // D6: cdp-port preservation across restart.
  // RestartCommand must read cdpPort from state.json BEFORE StopCommand deletes
  // it, then forward that value into StartCommand.handle so restart preserves
  // CDP transparently. Explicit --cdp-port on the context always wins.
  // ---------------------------------------------------------------------------
  group('RestartCommand cdp-port forwarding', () {
    late Directory tempHome;
    late Directory tempProfileRoot;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('artisan_restart_cdp_');
      StateFile.debugHomeOverride = tempHome.path;
      tempProfileRoot =
          await Directory.systemTemp.createTemp('artisan_restart_cdp_profile_');
      // Reset seams.
      StopCommand.stopKillFunction = _noOpKill;
      StopCommand.stopIsAlive = _alwaysDead;
      StopCommand.stopGracePeriod = Duration.zero;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      StopCommand.stopKillFunction = Process.killPid;
      StopCommand.stopIsAlive = StopCommand.defaultIsAlive;
      StopCommand.stopGracePeriod = const Duration(seconds: 2);
      StartCommand.cdpProcessRunner = Process.run;
      StartCommand.cdpProcessStarter = (
        exec,
        args, {
        workingDirectory,
        mode,
      }) =>
          Process.start(
            exec,
            args,
            workingDirectory: workingDirectory,
            mode: mode ?? ProcessStartMode.normal,
          );
      StartCommand.cdpChromeBinaryResolver = StartCommand.defaultChromeBinary;
      StartCommand.cdpChromeProber = StartCommand.defaultChromeProbe;
      StartCommand.cdpChromeNavigator = StartCommand.defaultChromeNavigate;
      StartCommand.cdpVmServiceScraper = null;
      StartCommand.cdpTmpProfileDirRoot = null;
      StartCommand.cdpFifoMaker = null;
      StartCommand.cdpWebServerReadyWaiter = null;
      StartCommand.cdpPortProbe = StartCommand.defaultPortProbe;
      StartCommand.cdpKillPid = Process.killPid;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
      if (tempProfileRoot.existsSync()) {
        await tempProfileRoot.delete(recursive: true);
      }
    });

    // (a) Prior state has cdpPort=9333 and restart has no explicit flag:
    //     the forwarded value 9333 drives the CDP branch.
    test(
        '(a) restart with no --cdp-port flag forwards prior cdpPort=9333 to '
        'StartCommand CDP branch', () async {
      // Seed state.json with cdpPort=9333 (as written by a prior `start --cdp-port=9333`).
      await _writeFakeState(tempHome, cdpPort: 9333);

      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeFlutterVersionRunner('3.30.0');
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      int? launchedCdpPort;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          // Record which --remote-debugging-port was requested.
          final portArg = args.firstWhere(
            (a) => a.startsWith('--remote-debugging-port='),
            orElse: () => '',
          );
          if (portArg.isNotEmpty) {
            launchedCdpPort = int.tryParse(portArg.split('=').last);
          }
          return _SpyProcess(pid: 1111);
        }
        return _FakeFlutterProcess(holderPid: 10, flutterPid: 11);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      StartCommand.cdpChromeNavigator = (port, url) async {};
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8181/abc/ws';
      StartCommand.cdpWebServerReadyWaiter = (_) async {};
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      final command = RestartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          // 'cdp-port' absent: restart must forward from prior state.
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);
      expect(
        launchedCdpPort,
        9333,
        reason: 'restart must forward prior cdpPort=9333 into the CDP branch '
            'even when --cdp-port is absent on the context',
      );
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['cdpPort'], 9333);
    });

    // (b) Explicit --cdp-port=4444 on context wins over forwarded 9333.
    test('(b) explicit --cdp-port=4444 on restart overrides prior cdpPort=9333',
        () async {
      await _writeFakeState(tempHome, cdpPort: 9333);

      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeFlutterVersionRunner('3.30.0');
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      int? launchedCdpPort;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          final portArg = args.firstWhere(
            (a) => a.startsWith('--remote-debugging-port='),
            orElse: () => '',
          );
          if (portArg.isNotEmpty) {
            launchedCdpPort = int.tryParse(portArg.split('=').last);
          }
          return _SpyProcess(pid: 2222);
        }
        return _FakeFlutterProcess(holderPid: 20, flutterPid: 21);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      StartCommand.cdpChromeNavigator = (port, url) async {};
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8181/abc/ws';
      StartCommand.cdpWebServerReadyWaiter = (_) async {};
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      final command = RestartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': '4444', // explicit flag overrides the forwarded 9333.
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);
      expect(
        launchedCdpPort,
        4444,
        reason:
            'explicit --cdp-port=4444 must win over the forwarded prior value of 9333',
      );
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['cdpPort'], 4444);
    });

    // (d) Prior state has cdpPort:null (non-CDP session): restart resolves null.
    test(
        '(d) restart when prior state has cdpPort:null resolves cdpPort==null '
        '(non-CDP branch used)', () async {
      await _writeFakeState(tempHome, cdpPort: null);

      var chromeLaunched = false;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') chromeLaunched = true;
        return _FakeFlutterProcess(holderPid: 30, flutterPid: 31);
      };
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8181/abc/ws';
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      final command = RestartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          // no --cdp-port.
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);
      expect(
        chromeLaunched,
        isFalse,
        reason: 'CDP branch must not be entered when prior cdpPort is null',
      );
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['cdpPort'], isNull);
    });
  });

  // (c) Bare start (no flag, no forwarded param): cdpPort==null.
  // Tested in start_command_test.dart under 'without --cdp-port: existing flow
  // unchanged' which already asserts state cdpPort==null. Added here as a
  // smoke-check via the handle(ctx) direct signature.
  group('StartCommand handle() forwarded cdpPort parameter', () {
    late Directory tempHome;
    late Directory tempProfileRoot;

    setUp(() async {
      tempHome =
          await Directory.systemTemp.createTemp('artisan_start_fwd_cdp_');
      StateFile.debugHomeOverride = tempHome.path;
      tempProfileRoot = await Directory.systemTemp
          .createTemp('artisan_start_fwd_cdp_profile_');
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      StartCommand.cdpProcessRunner = Process.run;
      StartCommand.cdpProcessStarter = (
        exec,
        args, {
        workingDirectory,
        mode,
      }) =>
          Process.start(
            exec,
            args,
            workingDirectory: workingDirectory,
            mode: mode ?? ProcessStartMode.normal,
          );
      StartCommand.cdpChromeBinaryResolver = StartCommand.defaultChromeBinary;
      StartCommand.cdpChromeProber = StartCommand.defaultChromeProbe;
      StartCommand.cdpChromeNavigator = StartCommand.defaultChromeNavigate;
      StartCommand.cdpVmServiceScraper = null;
      StartCommand.cdpTmpProfileDirRoot = null;
      StartCommand.cdpFifoMaker = null;
      StartCommand.cdpWebServerReadyWaiter = null;
      StartCommand.cdpPortProbe = StartCommand.defaultPortProbe;
      StartCommand.cdpKillPid = Process.killPid;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
      if (tempProfileRoot.existsSync()) {
        await tempProfileRoot.delete(recursive: true);
      }
    });

    // (c) Bare start: no --cdp-port flag and no forwarded param => cdpPort==null.
    test(
        '(c) bare start with no flag and no forwarded cdpPort resolves '
        'cdpPort==null (non-CDP path)', () async {
      var chromeLaunched = false;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') chromeLaunched = true;
        return _FakeFlutterProcess(holderPid: 40, flutterPid: 41);
      };
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8181/abc/ws';
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          // no 'cdp-port' key.
        }),
        output,
      );

      // Call with no forwarded cdpPort (the default).
      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);
      expect(chromeLaunched, isFalse, reason: 'no Chrome for bare start');
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['cdpPort'], isNull);
    });

    // Forwarded cdpPort param drives the CDP branch when flag is absent.
    test(
        'forwarded cdpPort=9333 via parameter drives the CDP branch when '
        '--cdp-port flag is absent', () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeFlutterVersionRunner('3.30.0');
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      int? launchedCdpPort;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          final portArg = args.firstWhere(
            (a) => a.startsWith('--remote-debugging-port='),
            orElse: () => '',
          );
          if (portArg.isNotEmpty) {
            launchedCdpPort = int.tryParse(portArg.split('=').last);
          }
          return _SpyProcess(pid: 3333);
        }
        return _FakeFlutterProcess(holderPid: 50, flutterPid: 51);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      StartCommand.cdpChromeNavigator = (port, url) async {};
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8181/abc/ws';
      StartCommand.cdpWebServerReadyWaiter = (_) async {};
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          // no 'cdp-port' flag on context.
        }),
        output,
      );

      // Forward cdpPort=9333 directly (as RestartCommand does).
      final code = await command.handle(ctx, cdpPort: 9333);

      expect(code, 0, reason: output.content);
      expect(
        launchedCdpPort,
        9333,
        reason: 'forwarded cdpPort parameter must drive the CDP branch when '
            '--cdp-port flag is absent',
      );
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['cdpPort'], 9333);
    });

    // Explicit --cdp-port flag wins over forwarded cdpPort parameter.
    test(
        'explicit --cdp-port=4444 flag wins over forwarded cdpPort=9333 parameter',
        () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeFlutterVersionRunner('3.30.0');
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      int? launchedCdpPort;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          final portArg = args.firstWhere(
            (a) => a.startsWith('--remote-debugging-port='),
            orElse: () => '',
          );
          if (portArg.isNotEmpty) {
            launchedCdpPort = int.tryParse(portArg.split('=').last);
          }
          return _SpyProcess(pid: 4444);
        }
        return _FakeFlutterProcess(holderPid: 60, flutterPid: 61);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      StartCommand.cdpChromeNavigator = (port, url) async {};
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8181/abc/ws';
      StartCommand.cdpWebServerReadyWaiter = (_) async {};
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': '4444', // explicit flag.
        }),
        output,
      );

      // Forward cdpPort=9333 but the flag 4444 must win.
      final code = await command.handle(ctx, cdpPort: 9333);

      expect(code, 0, reason: output.content);
      expect(
        launchedCdpPort,
        4444,
        reason:
            'explicit --cdp-port=4444 flag must override the forwarded 9333',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// File-private helpers.
// ---------------------------------------------------------------------------

bool _noOpKill(int pid, ProcessSignal signal) => true;

bool _alwaysDead(int pid) => false;

/// Writes a minimal state.json to [tempHome]/.artisan/state.json.
Future<void> _writeFakeState(Directory tempHome,
    {required int? cdpPort}) async {
  final artisanDir = Directory('${tempHome.path}/.artisan');
  await artisanDir.create(recursive: true);
  final file = File('${artisanDir.path}/state.json');
  await file.writeAsString(jsonEncode(<String, dynamic>{
    'pid': 12345,
    'stdinPipe': '${artisanDir.path}/flutter-dev.fifo',
    'stdinHolderPid': 12346,
    'vmServiceUri': 'ws://127.0.0.1:8181/abc/ws',
    'webPort': 3100,
    'vmServicePort': 8181,
    'startedAt': '2026-06-16T00:00:00.000Z',
    'profile': 'debug',
    'projectRoot': '/fake/project',
    'device': 'chrome',
    'chromePid': null,
    'tmpProfileDir': null,
    'cdpPort': cdpPort,
  }));
}

CdpProcessRunner _fakeFlutterVersionRunner(String version) {
  return (
    String exec,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    if (exec == 'flutter' &&
        args.contains('--version') &&
        args.contains('--machine')) {
      return ProcessResult(0, 0, '{"frameworkVersion":"$version"}', '');
    }
    return ProcessResult(0, 0, '', '');
  };
}

class _SpyProcess implements Process {
  _SpyProcess({required this.pid});

  @override
  final int pid;

  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => throw UnimplementedError();
}

class _FakeFlutterProcess implements Process {
  _FakeFlutterProcess({required this.holderPid, required this.flutterPid});

  final int holderPid;
  final int flutterPid;

  @override
  int get pid => 9999;

  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  Stream<List<int>> get stdout {
    final lines = 'HOLDER=$holderPid\nFLUTTER=$flutterPid\n';
    return Stream<List<int>>.fromIterable(<List<int>>[lines.codeUnits]);
  }

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => throw UnimplementedError();
}
