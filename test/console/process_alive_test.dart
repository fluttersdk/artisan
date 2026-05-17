import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('processAlive', () {
    test('returns true for the current process', () {
      expect(processAlive(pid), isTrue);
    });

    test('returns true while a spawned child is still running', () async {
      // Spawn a long-running sleep, probe it, then kill it.
      final spawn = Platform.isWindows
          ? await Process.start('cmd', <String>['/c', 'timeout', '/t', '5'])
          : await Process.start('sleep', <String>['5']);

      // Give the OS a moment to register the PID.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(processAlive(spawn.pid), isTrue);

      spawn.kill(ProcessSignal.sigkill);
      await spawn.exitCode;
    });

    test('returns false for an intentionally impossible PID', () {
      // 999,999,999 — well above any real PID seen in practice (Linux max
      // pid is 4,194,304; macOS default is 99,998). False both because the
      // PID does not exist AND because POSIX `kill -0` would return EINVAL
      // (handled by exit != 0 in either case).
      expect(processAlive(999999999), isFalse);
    });
  });
}
