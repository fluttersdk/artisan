import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StartCommand', () {
    test('metadata: name=start, boot=none', () {
      final command = StartCommand();

      expect(command.name, 'start');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('configure declares device / port / vm-service-port / dds / static',
        () {
      final command = StartCommand();
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options.containsKey('device'), isTrue);
      expect(parser.options.containsKey('port'), isTrue);
      expect(parser.options.containsKey('vm-service-port'), isTrue);
      expect(parser.options.containsKey('dds'), isTrue);
      expect(parser.options.containsKey('profile-static'), isTrue);
    });

    test('--device defaults to chrome', () {
      final command = StartCommand();
      final parser = ArgParser();
      command.configure(parser);

      final results = parser.parse(<String>[]);

      expect(results['device'], 'chrome');
      expect(results['port'], '3100');
      expect(results['dds'], isFalse);
    });

    test('--device override is honored', () {
      final command = StartCommand();
      final parser = ArgParser();
      command.configure(parser);

      final results = parser.parse(<String>['--device=macos']);

      expect(results['device'], 'macos');
    });

    test('normalizeVmServiceUri converts http:// to ws:// and appends /ws', () {
      expect(
        StartCommand.normalizeVmServiceUri('http://127.0.0.1:8181/abc'),
        'ws://127.0.0.1:8181/abc/ws',
      );
    });

    test('normalizeVmServiceUri keeps existing /ws suffix', () {
      expect(
        StartCommand.normalizeVmServiceUri('ws://127.0.0.1:8181/abc/ws'),
        'ws://127.0.0.1:8181/abc/ws',
      );
    });

    test('normalizeVmServiceUri normalizes https:// to wss://', () {
      expect(
        StartCommand.normalizeVmServiceUri('https://example.com:443/x/'),
        'wss://example.com:443/x/ws',
      );
    });

    test('normalizeVmServiceUri trims trailing slash before appending ws', () {
      expect(
        StartCommand.normalizeVmServiceUri('ws://host:1/token/ws/'),
        'ws://host:1/token/ws',
      );
    });

    test('normalizeVmServiceUri leaves unrecognised schemes alone (only /ws)',
        () {
      expect(
        StartCommand.normalizeVmServiceUri('foo://bar/baz'),
        'foo://bar/baz/ws',
      );
    });
  });

  group('StartCommand --cdp-port flag', () {
    test('configure declares --cdp-port option (default null)', () {
      final command = StartCommand();
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options.containsKey('cdp-port'), isTrue);
      final result = parser.parse(<String>[]);
      expect(result['cdp-port'], isNull);
    });

    test('--cdp-port accepts a numeric value', () {
      final command = StartCommand();
      final parser = ArgParser();
      command.configure(parser);

      final result = parser.parse(<String>['--cdp-port=9223']);

      expect(result['cdp-port'], '9223');
    });
  });

  group('StartCommand.compareSemver', () {
    test('3.30.0 == 3.30.0 returns 0', () {
      expect(StartCommand.compareSemver('3.30.0', '3.30.0'), 0);
    });

    test('3.29.0 < 3.30.0 returns -1', () {
      expect(StartCommand.compareSemver('3.29.0', '3.30.0'), lessThan(0));
    });

    test('3.31.0 > 3.30.0 returns 1', () {
      expect(StartCommand.compareSemver('3.31.0', '3.30.0'), greaterThan(0));
    });

    test('3.30.1 > 3.30.0 returns positive', () {
      expect(StartCommand.compareSemver('3.30.1', '3.30.0'), greaterThan(0));
    });

    test('4.0.0 > 3.99.99 returns positive', () {
      expect(StartCommand.compareSemver('4.0.0', '3.99.99'), greaterThan(0));
    });

    test('extra dev/build suffix tolerated (3.30.0-1.0.pre)', () {
      // Strips suffix, compares numeric segments only.
      expect(StartCommand.compareSemver('3.30.0-1.0.pre', '3.30.0'), 0);
    });
  });

  group('StartCommand.resolveChromeBinary', () {
    test('returns macOS path when file exists on macOS', () {
      // The file existence check on the actual host machine resolves to
      // /Applications/Google Chrome.app/Contents/MacOS/Google Chrome when
      // it exists. We can not assume CI hosts have Chrome installed, so
      // assert the negative case via direct overrides.
      final resolved = StartCommand.resolveChromeBinary(
        isMacOs: true,
        isLinux: false,
        macAppExists: (_) => true,
        pathLookup: (_) => null,
      );
      expect(
        resolved,
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      );
    });

    test('falls back to PATH lookup on Linux', () {
      final resolved = StartCommand.resolveChromeBinary(
        isMacOs: false,
        isLinux: true,
        macAppExists: (_) => false,
        pathLookup: (name) =>
            name == 'google-chrome' ? '/usr/bin/google-chrome' : null,
      );
      expect(resolved, '/usr/bin/google-chrome');
    });

    test('returns null on Windows', () {
      final resolved = StartCommand.resolveChromeBinary(
        isMacOs: false,
        isLinux: false,
        macAppExists: (_) => false,
        pathLookup: (_) => '/wherever',
      );
      expect(resolved, isNull);
    });

    test('returns null when no binary found', () {
      final resolved = StartCommand.resolveChromeBinary(
        isMacOs: true,
        isLinux: false,
        macAppExists: (_) => false,
        pathLookup: (_) => null,
      );
      expect(resolved, isNull);
    });
  });

  group('StartCommand handle() with --cdp-port', () {
    late Directory tempHome;
    late Directory tempProfileRoot;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('artisan_start_cdp_');
      StateFile.debugHomeOverride = tempHome.path;
      tempProfileRoot =
          await Directory.systemTemp.createTemp('artisan_start_cdp_profile_');
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
          Process.start(exec, args,
              workingDirectory: workingDirectory,
              mode: mode ?? ProcessStartMode.normal);
      StartCommand.cdpChromeBinaryResolver = StartCommand.defaultChromeBinary;
      StartCommand.cdpChromeProber = StartCommand.defaultChromeProbe;
      StartCommand.cdpChromeNavigator = StartCommand.defaultChromeNavigate;
      StartCommand.cdpVmServiceScraper = null;
      StartCommand.cdpTmpProfileDirRoot = null;
      StartCommand.cdpFifoMaker = null;
      StartCommand.cdpWebServerReadyWaiter = null;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
      if (tempProfileRoot.existsSync()) {
        await tempProfileRoot.delete(recursive: true);
      }
    });

    test('rejects --device=macos with --cdp-port: exit 1 + reject-device error',
        () async {
      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'macos',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': '9223',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(
          output.content,
          contains(
              '--cdp-port requires --device=chrome or --device=web-server'));
      expect(output.content, contains('macos'));
    });

    test('rejects Flutter SDK < 3.30.0 with upgrade hint before Chrome launch',
        () async {
      // Stub flutter --version --machine returning older SDK.
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.29.0"}',
      );
      // Chrome binary "found" so we know we exited because of SDK gate,
      // not Chrome resolution.
      StartCommand.cdpChromeBinaryResolver =
          (_) => '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

      var chromeLaunched = false;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        chromeLaunched = true;
        return _NoopProcess();
      };

      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': '9223',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content, contains('3.29.0'));
      expect(output.content, contains('3.30.0'));
      expect(output.content, contains('flutter upgrade'));
      expect(chromeLaunched, isFalse,
          reason: 'Chrome must not be launched when SDK gate fails');
    });

    test(
        'rejects when Chrome binary cannot be resolved (Windows / missing install)',
        () async {
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => null;

      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': '9223',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content, contains('Chrome binary not found'));
    });

    test('returns 1 + kills Chrome when CDP debug port probe fails', () async {
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';
      var killedPid = 0;
      final chrome = _SpyProcess(pid: 4242, onKill: (sig) => killedPid = 4242);
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        return chrome;
      };
      StartCommand.cdpChromeProber = (port, timeout) async {
        throw StateError('debug port unreachable');
      };

      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': '9223',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content, contains('Chrome failed to open debug port 9223'));
      expect(killedPid, 4242,
          reason: 'Chrome process must be killed when probe fails');
    });

    test(
        'happy path: spawns Chrome with correct args + flutter web-server '
        '+ writes state.json with chromePid + cdpPort + tmpProfileDir',
        () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      final spawned = <List<String>>[];
      _SpyProcess? chromeProc;
      _FakeFlutterProcess? flutterProc;

      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        spawned.add(<String>[exec, ...args]);
        if (exec == '/fake/chrome') {
          chromeProc = _SpyProcess(pid: 7777);
          return chromeProc!;
        }
        // Flutter wrapper sh -c launch: emit HOLDER + FLUTTER pids on stdout.
        flutterProc = _FakeFlutterProcess(holderPid: 100, flutterPid: 200);
        return flutterProc!;
      };

      StartCommand.cdpChromeProber = (port, timeout) async {
        // Probe succeeds (void return).
      };

      final navigateCalls = <Map<String, dynamic>>[];
      StartCommand.cdpChromeNavigator = (port, url) async {
        navigateCalls.add(<String, dynamic>{'port': port, 'url': url});
      };

      // Skip the real VM Service URI scrape (would require log file flow).
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8181/abc/ws';
      StartCommand.cdpWebServerReadyWaiter = (_) async {};
      StartCommand.cdpFifoMaker = (path) async {
        // Pretend we created the FIFO.
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
          'cdp-port': '9223',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);

      // 1. Chrome spawn args check.
      final chromeArgs = spawned.firstWhere((a) => a.first == '/fake/chrome');
      expect(chromeArgs, contains('--remote-debugging-port=9223'));
      expect(chromeArgs, contains('--remote-allow-origins=*'));
      expect(chromeArgs.any((a) => a.startsWith('--user-data-dir=')), isTrue);
      expect(chromeArgs, contains('about:blank'));

      // 2. flutter wrapper carries -d web-server + --web-experimental-hot-reload
      //    even though user passed --device=chrome (silent remap).
      final flutterArgs = spawned.firstWhere((a) => a.first == 'sh');
      final shPayload = flutterArgs[2];
      expect(shPayload, contains('-d web-server'));
      expect(shPayload, contains('--web-experimental-hot-reload'));

      // 3. State file written.
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['chromePid'], 7777);
      expect(state['cdpPort'], 9223);
      expect(
          state['tmpProfileDir'], '${tempProfileRoot.path}/dusk-chrome-9223');
      expect(state['vmServiceUri'], 'ws://127.0.0.1:8181/abc/ws');

      // 4. Page.navigate was sent.
      expect(navigateCalls, hasLength(1));
      expect(navigateCalls.first['port'], 9223);
      expect(navigateCalls.first['url'], 'http://localhost:3100/');
    });

    test(
        '--device=web-server with --cdp-port is accepted (no silent remap needed)',
        () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          return _SpyProcess(pid: 8888);
        }
        return _FakeFlutterProcess(holderPid: 101, flutterPid: 202);
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
          'device': 'web-server',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': '9223',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);
    });

    test(
        'Page.navigate fires AFTER web-server ready + BEFORE vmServiceUri scrape '
        '(ordering invariant)', () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          return _SpyProcess(pid: 9000);
        }
        return _FakeFlutterProcess(holderPid: 102, flutterPid: 203);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};

      // Drive a deterministic ordering: readyWaiter blocks until released,
      // navigate fires next, then scrape begins. Asserts the post-fix flow:
      // ready -> navigate -> scrape (NOT scrape -> navigate, which would
      // deadlock under DWDS because the URI emits only after Chrome connects).
      final timeline = <String>[];
      final readyCompleter = Completer<void>();
      StartCommand.cdpWebServerReadyWaiter = (_) async {
        timeline.add('ready:start');
        await readyCompleter.future;
        timeline.add('ready:done');
      };
      StartCommand.cdpChromeNavigator = (port, url) async {
        timeline.add('navigate');
      };
      StartCommand.cdpVmServiceScraper = (_) async {
        timeline.add('scrape:start');
        return 'ws://127.0.0.1:8181/abc/ws';
      };
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
          'cdp-port': '9223',
        }),
        output,
      );

      final handleFuture = command.handle(ctx);
      // Yield event loop to let ready:start log; navigate must not have fired.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(timeline, ['ready:start']);
      // Release the ready gate; navigate then scrape should follow in order.
      readyCompleter.complete();
      final code = await handleFuture;

      expect(code, 0, reason: output.content);
      expect(
          timeline, ['ready:start', 'ready:done', 'navigate', 'scrape:start']);
    });

    test('without --cdp-port: existing flow unchanged (no Chrome pre-launch)',
        () async {
      // Existing flow runs Process.start sh -c ... directly. We stub the
      // wrapper Process.start by overriding cdpProcessStarter for the
      // flutter side; Chrome must NOT be invoked because --cdp-port is null.
      var chromeInvocations = 0;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') chromeInvocations++;
        return _FakeFlutterProcess(holderPid: 50, flutterPid: 51);
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
          // 'cdp-port' absent.
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);
      expect(chromeInvocations, 0,
          reason: 'Chrome must not be pre-launched when --cdp-port is absent');

      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['chromePid'], isNull);
      expect(state['cdpPort'], isNull);
      expect(state['tmpProfileDir'], isNull);
    });
  });
}

// Test helpers below.

Future<ProcessResult> Function(
  String,
  List<String>, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) _fakeProcessRunner({required String flutterVersionStdout}) {
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
      return ProcessResult(0, 0, flutterVersionStdout, '');
    }
    if (exec == 'mkfifo') {
      // Allow mkfifo to run for real OR delegate; we delegate to real here.
      return Process.run(exec, args);
    }
    return ProcessResult(0, 0, '', '');
  };
}

class _NoopProcess implements Process {
  @override
  int get pid => 1;
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

class _SpyProcess implements Process {
  _SpyProcess({required this.pid, this.onKill});
  @override
  final int pid;
  final void Function(ProcessSignal)? onKill;
  @override
  Future<int> get exitCode => Future<int>.value(0);
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    onKill?.call(signal);
    return true;
  }

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
