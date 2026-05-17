import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('LogsCommand', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_logs_');
      StateFile.debugHomeOverride = tempHome.path;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('metadata: name=logs, boot=none', () {
      final command = LogsCommand();

      expect(command.name, 'logs');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('returns 1 with warning when log file missing', () async {
      final command = LogsCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content, contains('Log file not found'));
    });

    test('configure registers --follow / -f flag', () {
      final command = LogsCommand();
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options.containsKey('follow'), isTrue);
    });

    test('non-follow path returns 0 when log file present', () async {
      final command = LogsCommand();
      final stateDir = Directory('${tempHome.path}/.artisan');
      stateDir.createSync(recursive: true);
      File('${stateDir.path}/flutter-dev.log').writeAsStringSync('hello');

      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const {'follow': false}),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0);
    });
  });
}
