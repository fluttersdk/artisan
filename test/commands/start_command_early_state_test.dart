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
}
