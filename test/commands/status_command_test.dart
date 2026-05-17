import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StatusCommand', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('artisan_status_');
      StateFile.debugHomeOverride = tempHome.path;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('metadata: name=status, boot=none', () {
      final command = StatusCommand();

      expect(command.name, 'status');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('emits {"running":false} when no state file', () async {
      final command = StatusCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['running'], isFalse);
    });

    test('emits full JSON record when state file present', () async {
      await StateFile.write(<String, dynamic>{
        'pid': 999999,
        'vmServiceUri': 'ws://127.0.0.1:8181/abc/ws',
        'webPort': 3100,
        'startedAt': '2026-05-17T12:00:00Z',
        'device': 'chrome',
      });
      final command = StatusCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['running'], isTrue);
      expect(decoded['pid'], 999999);
      expect(decoded['vmServiceUri'], 'ws://127.0.0.1:8181/abc/ws');
      expect(decoded['webPort'], 3100);
      expect(decoded['device'], 'chrome');
      // alive is bool — pid likely not running, so false (but never null).
      expect(decoded['alive'], isA<bool>());
    });

    test('handles null pid in state without crashing', () async {
      await StateFile.write(<String, dynamic>{
        'vmServiceUri': 'ws://127.0.0.1:8181/abc/ws',
        'webPort': 3100,
        'startedAt': '2026-05-17T12:00:00Z',
        'device': 'chrome',
      });
      final command = StatusCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['running'], isTrue);
      expect(decoded['pid'], isNull);
      expect(decoded['alive'], isFalse);
    });

    test('reports alive=true for the current process pid', () async {
      await StateFile.write(<String, dynamic>{
        'pid': pid,
        'vmServiceUri': 'ws://127.0.0.1:8181/abc/ws',
      });
      final command = StatusCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['alive'], isTrue);
    });
  });
}
