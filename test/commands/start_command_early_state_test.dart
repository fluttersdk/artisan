import 'dart:async';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Verifies that a `start` cut short by its CALLER still leaves a usable
/// session behind.
///
/// The MCP client kills a tool call at 60s. An iOS build routinely takes
/// longer, and `start` wrote the session only AFTER scraping the VM Service
/// URI, which is the last thing it waits for. So the app came up, the process
/// survived (the wrapper detaches it), and nothing ever recorded it: `status`
/// answered `running: false` about an app that was listening, and the operator
/// had to hand-write the state file to get anything back.
///
/// Measured in the field on `device=50BAD9FA-...`, `vm-service-port=8183`:
/// "MCP server tool artisan_start timed out after 60s", then the app was found
/// installed and serving.
void main() {
  group('StartCommand session record', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_early_state_');
      StateFile.debugHomeOverride = tempHome.path;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      StateFile.debugProjectRootOverride = null;
      if (tempHome.existsSync()) await tempHome.delete(recursive: true);
    });

    test('bootingState carries everything a caller needs except the URI', () {
      // The keys that make an interrupted start recoverable: the pid to stop,
      // the FIFO to hot-restart through, and the ports to reach it on.
      final Map<String, dynamic> state = StartCommand.bootingState(
        pid: 4242,
        stdinPipe: '/tmp/x.fifo',
        stdinHolderPid: 4241,
        webPort: 3100,
        vmServicePort: 8183,
        profileStatic: false,
        device: 'iphone-udid',
        chromePid: null,
        tmpProfileDir: null,
        cdpPort: null,
      );

      expect(state['pid'], equals(4242));
      expect(state['stdinPipe'], equals('/tmp/x.fifo'));
      expect(state['stdinHolderPid'], equals(4241));
      expect(state['vmServicePort'], equals(8183));
      expect(state['device'], equals('iphone-udid'));
      expect(
        state['vmServiceUri'],
        isNull,
        reason: 'not scraped yet; that is the whole point',
      );
      expect(
        state['booting'],
        isTrue,
        reason: 'so a reader can tell an interrupted start from a finished one',
      );
    });

    test('the finished record drops the booting marker', () {
      final Map<String, dynamic> state = StartCommand.bootingState(
        pid: 4242,
        stdinPipe: '/tmp/x.fifo',
        stdinHolderPid: 4241,
        webPort: 3100,
        vmServicePort: 8183,
        profileStatic: false,
        device: 'chrome',
        chromePid: null,
        tmpProfileDir: null,
        cdpPort: null,
      );

      final Map<String, dynamic> done = StartCommand.readyState(
        state,
        vmServiceUri: 'ws://127.0.0.1:8183/tok/ws',
      );

      expect(done['vmServiceUri'], equals('ws://127.0.0.1:8183/tok/ws'));
      expect(done.containsKey('booting'), isFalse);
      expect(done['pid'], equals(4242), reason: 'everything else survives');
      expect(done['stdinPipe'], equals('/tmp/x.fifo'));
    });
  });

  // The field case: `start --device macos` on a fresh worktree, where the
  // first native build (CocoaPods, SwiftPM) outlasts the 90s scrape. `start`
  // used to die on the timeout's StateError and print a stack fragment, while
  // the app kept building and the next connected command found its URI.
  group('StartCommand when the VM Service scrape times out', () {
    late Directory tempHome;

    Future<({int code, String content})> startMacos() async {
      final output = BufferedOutput();
      final code = await StartCommand().handle(
        ArtisanContext.bare(
          MapInput(<String, dynamic>{
            'device': 'macos',
            'port': '3100',
            'dds': false,
            'profile-static': false,
            'timeout': '90',
          }),
          output,
        ),
      );
      return (code: code, content: output.content);
    }

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_cold_build_');
      StateFile.debugHomeOverride = tempHome.path;
      StateFile.debugProjectRootOverride = Directory.current.path;
      StartCommand.cdpFifoMaker = (String path) async {
        File(path).writeAsStringSync('');
      };
      StartCommand.cdpProcessStarter = (
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) async =>
          _FakeFlutterProcess(holderPid: 4241, flutterPid: 4242);
      StartCommand.cdpVmServiceScraper = (File _) async {
        throw TimeoutException('Timed out after 90s');
      };
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      StateFile.debugProjectRootOverride = null;
      StartCommand.cdpFifoMaker = null;
      StartCommand.cdpProcessStarter = (
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        ProcessStartMode? mode,
      }) =>
          Process.start(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            mode: mode ?? ProcessStartMode.normal,
          );
      StartCommand.cdpVmServiceScraper = null;
      StartCommand.startIsAlive = processAlive;
      StartCommand.cdpKillPid = Process.killPid;
      if (tempHome.existsSync()) await tempHome.delete(recursive: true);
    });

    test('a build still running exits 75 with a still-building line', () async {
      StartCommand.startIsAlive = (int pid) => pid == 4242;

      final result = await startMacos();

      expect(result.code, ArtisanCommand.exitTryAgain);
      expect(result.content, contains('still building after 90s'));
      expect(result.content, contains('artisan status'));
      expect(result.content, contains('--timeout'));
      final Map<String, dynamic>? state = await StateFile.read();
      expect(
        state!['booting'],
        isTrue,
        reason: 'the session stays recorded so a later command can heal it',
      );
      expect(state['pid'], 4242);
    });

    test('a flutter run that exited during the wait fails with exit 1',
        () async {
      StartCommand.startIsAlive = (int _) => false;
      final List<int> killed = <int>[];
      StartCommand.cdpKillPid = (int pid, [ProcessSignal? _]) {
        killed.add(pid);
        return true;
      };

      final result = await startMacos();

      expect(result.code, 1);
      expect(result.content, contains('exited before'));
      expect(result.content, contains('flutter-dev.log'));
      expect(result.content, isNot(contains('still building')));
      // A session left behind would have `status` report a dead app as
      // still booting, and the FIFO holder would outlive it for good.
      expect(await StateFile.read(), isNull);
      expect(killed, contains(4241), reason: 'the FIFO holder is reaped');
      expect(
        File('${File(StateFile.path).parent.path}/flutter-dev.fifo')
            .existsSync(),
        isFalse,
      );
    });
  });
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
  Stream<List<int>> get stdout => Stream<List<int>>.value(
        'HOLDER=$holderPid\nFLUTTER=$flutterPid\n'.codeUnits,
      );

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => throw UnimplementedError();
}
