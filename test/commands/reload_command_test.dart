import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ReloadCommand', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_reload_');
      StateFile.debugHomeOverride = tempHome.path;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('metadata: name=reload, boot=none', () {
      final command = ReloadCommand();

      expect(command.name, 'reload');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('returns 2 with friendly message when no state file', () async {
      final command = ReloadCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 2);
      expect(output.content, contains('No state file'));
    });

    test('returns 2 when state has no stdinPipe entry', () async {
      await StateFile.write(<String, dynamic>{'pid': 1});
      final command = ReloadCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 2);
      expect(output.content, contains('no stdinPipe'));
    });

    test('returns 2 when pipe path missing on disk', () async {
      await StateFile.write(<String, dynamic>{
        'stdinPipe': '${tempHome.path}/does_not_exist.fifo',
      });
      final command = ReloadCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 2);
      expect(output.content, contains('Pipe missing'));
    });

    // Tagged `integration`: spawns `sh -c 'cat <fifo>'` then ReloadCommand
    // opens the FIFO for write. POSIX FIFOs block O_WRONLY until a reader is
    // present; on hosted Linux runners the reader-process spawn loses the race
    // and the writer hangs. Local macOS scheduler timing happens to win the
    // race, so the test is reliable locally but not in CI. Run on demand:
    // `dart test --tags=integration test/commands/reload_command_test.dart`.
    test('returns 0 on real FIFO round-trip', tags: 'integration', () async {
      // Skip on Windows where mkfifo is not available.
      if (Platform.isWindows) return;

      final fifoPath = '${tempHome.path}/test.fifo';
      final mkfifoResult = await Process.run('mkfifo', <String>[fifoPath]);
      if (mkfifoResult.exitCode != 0) {
        // mkfifo unavailable in the test environment.
        return;
      }

      // Drain the FIFO in the background so the writer doesn't block on
      // POSIX open() (which waits for a reader on a FIFO).
      final reader = await Process.start('sh', <String>[
        '-c',
        'cat $fifoPath > /dev/null',
      ]);

      await StateFile.write(<String, dynamic>{
        'stdinPipe': fifoPath,
      });

      final command = ReloadCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      expect(output.content, contains('Sent `r`'));

      reader.kill();
      await reader.exitCode;
    });
  });
}
