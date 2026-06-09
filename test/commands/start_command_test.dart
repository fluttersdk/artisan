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
      StartCommand.cdpPortProbe = StartCommand.defaultPortProbe;
      StartCommand.cdpKillPid = Process.killPid;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
      if (tempProfileRoot.existsSync()) {
        await tempProfileRoot.delete(recursive: true);
      }
    });

    test(
        'rejects non-integer --cdp-port value: exit 1 + actionable error '
        '(no silent fallback to the default flow)', () async {
      final command = StartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(<String, dynamic>{
          'device': 'chrome',
          'port': '3100',
          'dds': false,
          'profile-static': false,
          'cdp-port': 'abc',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content,
          contains('--cdp-port expects an integer port number, got "abc"'));
      expect(output.content, contains('--cdp-port=9223'));
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

    test('busy webPort: returns 1, names port in error, Chrome never spawned',
        () async {
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';
      // Inject a probe that reports the web port as busy.
      StartCommand.cdpPortProbe = (port) async => false;

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

      expect(code, 1, reason: 'busy port must exit 1');
      expect(output.content, contains('3100'),
          reason: 'error message must name the busy port');
      expect(chromeLaunched, isFalse,
          reason: 'Chrome must not be launched when the web port is busy');
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
      //    + the default --host-vmservice-port=8181 (silent remap from chrome).
      final flutterArgs = spawned.firstWhere((a) => a.first == 'sh');
      final shPayload = flutterArgs[2];
      expect(shPayload, contains('-d web-server'));
      expect(shPayload, contains('--web-experimental-hot-reload'));
      expect(shPayload, contains('--host-vmservice-port=8181'));

      // 3. State file written; vmServicePort defaults to 8181.
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['chromePid'], 7777);
      expect(state['cdpPort'], 9223);
      expect(
          state['tmpProfileDir'], '${tempProfileRoot.path}/dusk-chrome-9223');
      expect(state['vmServiceUri'], 'ws://127.0.0.1:8181/abc/ws');
      expect(state['vmServicePort'], 8181);

      // 4. Page.navigate was sent.
      expect(navigateCalls, hasLength(1));
      expect(navigateCalls.first['port'], 9223);
      expect(navigateCalls.first['url'], 'http://localhost:3100/');
    });

    test(
        '--vm-service-port=8282 plumbs through to flutter --host-vmservice-port '
        '+ records the same value in state.json', () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      final spawned = <List<String>>[];
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        spawned.add(<String>[exec, ...args]);
        if (exec == '/fake/chrome') return _SpyProcess(pid: 1111);
        return _FakeFlutterProcess(holderPid: 200, flutterPid: 300);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      StartCommand.cdpChromeNavigator = (port, url) async {};
      StartCommand.cdpVmServiceScraper =
          (_) async => 'ws://127.0.0.1:8282/abc/ws';
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
          'vm-service-port': '8282',
          'dds': false,
          'profile-static': false,
          'cdp-port': '9223',
        }),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0, reason: output.content);
      final shPayload = spawned.firstWhere((a) => a.first == 'sh')[2];
      expect(shPayload, contains('--host-vmservice-port=8282'));
      final state = await StateFile.read();
      expect(state, isNotNull);
      expect(state!['vmServicePort'], 8282);
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

    test(
        'navigate throws after launch: returns 1, reaps Chrome + flutter pids '
        '+ deletes FIFO + tmp profile dir', () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      var chromeKilled = false;
      Process? flutterHandle;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          return _SpyProcess(pid: 7777, onKill: (_) => chromeKilled = true);
        }
        flutterHandle = _FakeFlutterProcess(holderPid: 100, flutterPid: 200);
        return flutterHandle!;
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      StartCommand.cdpWebServerReadyWaiter = (_) async {};
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      // The navigate step throws AFTER both children launched and PIDs scraped.
      StartCommand.cdpChromeNavigator = (port, url) async {
        throw StateError('Page.navigate failed');
      };

      final killedPids = <int>[];
      StartCommand.cdpKillPid = (pid, [signal = ProcessSignal.sigterm]) {
        killedPids.add(pid);
        return true;
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

      expect(code, 1, reason: 'navigate failure must exit 1');
      expect(output.content, contains('Page.navigate failed'),
          reason: 'surfaced error must be the original throw, not a cleanup '
              'error');
      expect(chromeKilled, isTrue, reason: 'Chrome must be reaped');
      expect(killedPids, containsAll(<int>[100, 200]),
          reason: 'both flutter holder + child pids must be SIGTERMed');
      final fifoPath = '${tempHome.path}/.artisan/flutter-dev.fifo';
      expect(File(fifoPath).existsSync(), isFalse,
          reason: 'FIFO must be deleted on failure');
      expect(Directory('${tempProfileRoot.path}/dusk-chrome-9223').existsSync(),
          isFalse,
          reason: 'tmp profile dir must be removed on failure');
    });

    test(
        'vmServiceUri scrape throws after launch: returns 1, reaps Chrome + '
        'flutter pids + deletes FIFO + tmp profile dir', () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      var chromeKilled = false;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          return _SpyProcess(pid: 4242, onKill: (_) => chromeKilled = true);
        }
        return _FakeFlutterProcess(holderPid: 300, flutterPid: 400);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      StartCommand.cdpWebServerReadyWaiter = (_) async {};
      StartCommand.cdpChromeNavigator = (port, url) async {};
      StartCommand.cdpFifoMaker = (path) async {
        File(path).writeAsStringSync('');
      };

      // The VM Service URI scrape throws AFTER navigate succeeded.
      StartCommand.cdpVmServiceScraper = (_) async {
        throw StateError('VM Service scrape timed out');
      };

      final killedPids = <int>[];
      StartCommand.cdpKillPid = (pid, [signal = ProcessSignal.sigterm]) {
        killedPids.add(pid);
        return true;
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

      expect(code, 1, reason: 'scrape failure must exit 1');
      expect(output.content, contains('VM Service scrape timed out'),
          reason: 'surfaced error must be the original throw');
      expect(chromeKilled, isTrue, reason: 'Chrome must be reaped');
      expect(killedPids, containsAll(<int>[300, 400]),
          reason: 'both flutter holder + child pids must be SIGTERMed');
      final fifoPath = '${tempHome.path}/.artisan/flutter-dev.fifo';
      expect(File(fifoPath).existsSync(), isFalse,
          reason: 'FIFO must be deleted on failure');
      expect(Directory('${tempProfileRoot.path}/dusk-chrome-9223').existsSync(),
          isFalse,
          reason: 'tmp profile dir must be removed on failure');
    });

    test(
        'FIFO setup throws after Chrome launch: returns 1, reaps Chrome + '
        'tmp profile dir', () async {
      StartCommand.cdpTmpProfileDirRoot = tempProfileRoot.path;
      StartCommand.cdpProcessRunner = _fakeProcessRunner(
        flutterVersionStdout: '{"frameworkVersion":"3.30.0"}',
      );
      StartCommand.cdpChromeBinaryResolver = (_) => '/fake/chrome';

      var chromeKilled = false;
      var flutterSpawned = false;
      StartCommand.cdpProcessStarter = (
        String exec,
        List<String> args, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async {
        if (exec == '/fake/chrome') {
          return _SpyProcess(pid: 5151, onKill: (_) => chromeKilled = true);
        }
        flutterSpawned = true;
        return _FakeFlutterProcess(holderPid: 500, flutterPid: 600);
      };

      StartCommand.cdpChromeProber = (port, timeout) async {};
      // FIFO creation throws AFTER Chrome launched but BEFORE flutter spawn.
      StartCommand.cdpFifoMaker = (path) async {
        throw StateError('mkfifo failed');
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

      expect(code, 1, reason: 'FIFO setup failure must exit 1');
      expect(output.content, contains('mkfifo failed'),
          reason: 'surfaced error must be the original throw');
      expect(chromeKilled, isTrue,
          reason: 'Chrome must be reaped even when the failure precedes the '
              'flutter spawn');
      expect(flutterSpawned, isFalse,
          reason:
              'flutter must not have been spawned (FIFO setup threw first)');
      expect(Directory('${tempProfileRoot.path}/dusk-chrome-9223').existsSync(),
          isFalse,
          reason: 'tmp profile dir must be removed on failure');
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

  group(
      'StartCommand.defaultChromeNavigate (regression: page-target selection)',
      () {
    // Regression guard for commit 871d0a7: defaultChromeNavigate must select
    // the first page-type target from /json, NOT the browser-level endpoint
    // that appears earlier in the list. If it regresses to selecting the
    // browser entry, the recorded url assertion fails because the browser ws
    // path never receives a Page.navigate frame.
    test(
        'selects page-type target from /json even when browser entry is first, '
        'and delivers Page.navigate with the correct url', () async {
      // 1. Stand up the fake CDP HTTP + WebSocket server on an ephemeral port.
      //    Bind to the 'localhost' hostname (not a fixed IPv4 literal) so the
      //    server is reachable however localhost resolves on the host
      //    (127.0.0.1 or ::1). defaultChromeNavigate connects via
      //    http://localhost:<port>, so server + client must share the same
      //    name resolution or the connect races to the wrong stack.
      final server = await HttpServer.bind('localhost', 0);
      final port = server.port;
      const host = 'localhost';

      String? recordedNavigateUrl;
      final navigateCompleter = Completer<void>();

      // 2. Serve requests: /json for HTTP, ws paths for WebSocket upgrades.
      server.listen((HttpRequest request) async {
        if (request.uri.path == '/json' &&
            !WebSocketTransformer.isUpgradeRequest(request)) {
          // Return the targets list: browser FIRST, page SECOND.
          final targets = jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'browser',
              'webSocketDebuggerUrl':
                  'ws://$host:$port/devtools/browser/fake-browser-id',
            },
            <String, dynamic>{
              'type': 'page',
              'webSocketDebuggerUrl':
                  'ws://$host:$port/devtools/page/fake-page-id',
            },
          ]);
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(targets);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/devtools/page/fake-page-id' &&
            WebSocketTransformer.isUpgradeRequest(request)) {
          // Accept the WebSocket upgrade on the page path, record the navigate
          // url, and ack with id:1.
          final ws = await WebSocketTransformer.upgrade(request);
          ws.listen((dynamic raw) async {
            if (navigateCompleter.isCompleted) return;
            try {
              final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
              if (decoded['method'] == 'Page.navigate') {
                final params = decoded['params'] as Map<String, dynamic>?;
                recordedNavigateUrl = params?['url'] as String?;
                ws.add(jsonEncode(<String, dynamic>{'id': 1}));
                await ws.close();
                navigateCompleter.complete();
              }
            } catch (e, st) {
              if (!navigateCompleter.isCompleted) {
                navigateCompleter.completeError(e, st);
              }
            }
          });
          return;
        }

        // Any other request (e.g. browser ws path) closes immediately to make
        // the regression obvious: connecting to it would cause the test to hang
        // or fail rather than silently succeed.
        request.response.statusCode = 404;
        await request.response.close();
      });

      try {
        // 3. Invoke the real defaultChromeNavigate; must complete without throw.
        const targetUrl = 'http://localhost:3100';
        await StartCommand.defaultChromeNavigate(port, targetUrl);

        // 4. Wait for the navigate frame to be processed by the fake server.
        await navigateCompleter.future;

        // 5. Assert page-target received the correct url.
        expect(
          recordedNavigateUrl,
          equals(targetUrl),
          reason: 'page-type WebSocket must receive the Page.navigate url; '
              'if the browser entry was selected instead, this assertion fails',
        );
      } finally {
        await server.close(force: true);
      }
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
