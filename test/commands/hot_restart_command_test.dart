import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('HotRestartCommand', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_hot_restart_');
      StateFile.debugHomeOverride = tempHome.path;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('metadata: name=hot-restart, boot=none', () {
      final command = HotRestartCommand();

      expect(command.name, 'hot-restart');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('returns 2 when no state file', () async {
      final command = HotRestartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 2);
      expect(output.content, contains('No state file'));
    });

    test('returns 2 when state lacks stdinPipe entry', () async {
      await StateFile.write(<String, dynamic>{'pid': 1});
      final command = HotRestartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 2);
      expect(output.content, contains('no stdinPipe'));
    });

    test('returns 2 when FIFO file missing on disk', () async {
      await StateFile.write(<String, dynamic>{
        'stdinPipe': '${tempHome.path}/missing.fifo',
      });
      final command = HotRestartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 2);
      expect(output.content, contains('Pipe missing'));
    });

    // Tagged `integration`: same FIFO-writer reader race as the reload variant.
    // Run on demand with `dart test --tags=integration`.
    test('returns 0 on real FIFO round-trip', tags: 'integration', () async {
      if (Platform.isWindows) return;
      final fifoPath = '${tempHome.path}/hot.fifo';
      final mkfifoResult = await Process.run('mkfifo', <String>[fifoPath]);
      if (mkfifoResult.exitCode != 0) return;

      final reader = await Process.start('sh', <String>[
        '-c',
        'cat $fifoPath > /dev/null',
      ]);

      await StateFile.write(<String, dynamic>{
        'stdinPipe': fifoPath,
      });

      final command = HotRestartCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      expect(output.content, contains('Sent `R`'));

      reader.kill();
      await reader.exitCode;
    });

    test('refuses a session that belongs to another project', () async {
      // The legacy pointer describes whichever app started last, so without
      // this a hot restart run from here writes `R` into a sibling project's FIFO
      // and reports success while nothing in this project moved.
      final Directory sibling =
          Directory.systemTemp.createTempSync('artisan_sibling_');
      addTearDown(() => sibling.deleteSync(recursive: true));

      final Directory stateDir = Directory('${tempHome.path}/.artisan');
      stateDir.createSync(recursive: true);
      File('${stateDir.path}/state.json').writeAsStringSync(
        jsonEncode(<String, dynamic>{
          'pid': 4242,
          'projectRoot': sibling.path,
          'stdinPipe': '${sibling.path}/stdin.fifo',
        }),
      );

      final output = BufferedOutput();
      final int code = await HotRestartCommand().handle(
        ArtisanContext.bare(MapInput(const {}), output),
      );

      expect(code, 1);
      expect(output.content, contains('another project'));
    });
  });
}
