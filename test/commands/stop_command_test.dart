import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StopCommand', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_stop_');
      StateFile.debugHomeOverride = tempHome.path;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
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
  });
}
