import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StateFile', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('artisan_state_test_');
      StateFile.debugHomeOverride = tempHome.path;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('path resolves under <home>/.artisan/state.json', () {
      expect(StateFile.path, '${tempHome.path}/.artisan/state.json');
    });

    test('read returns null when the file does not exist', () async {
      expect(await StateFile.read(), isNull);
    });

    test('write then read round-trips a map', () async {
      final payload = <String, dynamic>{
        'pid': 1234,
        'vmServiceUri': 'ws://127.0.0.1:8181/abc/ws',
        'device': 'chrome',
      };

      await StateFile.write(payload);
      final got = await StateFile.read();

      expect(got, payload);
    });

    test('write is atomic — no .tmp file remains after write', () async {
      await StateFile.write({'pid': 1});

      final tmp = File('${StateFile.path}.tmp');
      expect(tmp.existsSync(), isFalse,
          reason: '.tmp file must be renamed away after a successful write');
    });

    test('write creates the parent directory when missing', () async {
      // Fresh temp home; ~/.artisan does not exist yet.
      expect(Directory('${tempHome.path}/.artisan').existsSync(), isFalse);

      await StateFile.write({'pid': 1});

      expect(Directory('${tempHome.path}/.artisan').existsSync(), isTrue);
    });

    test('delete removes the file', () async {
      await StateFile.write({'pid': 1});
      expect(File(StateFile.path).existsSync(), isTrue);

      await StateFile.delete();

      expect(File(StateFile.path).existsSync(), isFalse);
    });

    test('delete is idempotent — no throw when file absent', () async {
      expect(() async => StateFile.delete(), returnsNormally);
    });

    test('read returns null on malformed JSON instead of throwing', () async {
      final file = File(StateFile.path);
      await file.parent.create(recursive: true);
      await file.writeAsString('{not json');

      expect(await StateFile.read(), isNull);
    });

    test('write overwrites prior content', () async {
      await StateFile.write({'pid': 1, 'device': 'chrome'});
      await StateFile.write({'pid': 2, 'device': 'macos'});

      final got = await StateFile.read();
      expect(got, {'pid': 2, 'device': 'macos'});
    });

    test('written file is valid JSON', () async {
      await StateFile.write({
        'pid': 42,
        'stdinPipe': '/tmp/foo.fifo',
        'stdinHolderPid': 41,
      });

      final raw = await File(StateFile.path).readAsString();
      final decoded = jsonDecode(raw);
      expect(decoded, isA<Map>());
      expect((decoded as Map)['pid'], 42);
    });

    test('cdpPort field round-trips correctly', () async {
      final payload = <String, dynamic>{
        'pid': 1234,
        'vmServiceUri': 'ws://127.0.0.1:8181/abc/ws',
        'device': 'chrome',
        'cdpPort': 9223,
      };

      await StateFile.write(payload);
      final got = await StateFile.read();

      expect(got?['cdpPort'], 9223);
      expect(got, payload);
    });
  });
}
