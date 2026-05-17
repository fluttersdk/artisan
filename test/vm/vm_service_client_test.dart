import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('VmServiceClient (offline contract)', () {
    test('constructor stores the wsUri verbatim', () {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      expect(client.wsUri, 'ws://example.invalid:8181/abc/ws');
    });

    test('isConnected is false until connect() succeeds', () {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      expect(client.isConnected, isFalse);
    });

    test('getMainIsolateId throws StateError without connect()', () async {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      await expectLater(
        client.getMainIsolateId(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not connected'),
          ),
        ),
      );
    });

    test('getExtensionRPCs throws StateError without connect()', () async {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      await expectLater(
        client.getExtensionRPCs('isolates/1'),
        throwsA(isA<StateError>()),
      );
    });

    test('callServiceExtension throws StateError without connect()', () async {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      await expectLater(
        client.callServiceExtension<dynamic>(
          'ext.dummy',
          isolateId: 'isolates/1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('evaluate throws StateError without connect()', () async {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      await expectLater(
        client.evaluate('isolates/1', '1 + 1'),
        throwsA(isA<StateError>()),
      );
    });

    test('reloadSources throws StateError without connect()', () async {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      await expectLater(
        client.reloadSources('isolates/1'),
        throwsA(isA<StateError>()),
      );
    });

    test('streamListen throws StateError without connect()', () async {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      await expectLater(
        client.streamListen('Isolate'),
        throwsA(isA<StateError>()),
      );
    });

    test('onIsolateEvent throws StateError without connect()', () {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      expect(() => client.onIsolateEvent, throwsA(isA<StateError>()));
    });

    test('disconnect is a no-op when not connected', () async {
      final client = VmServiceClient('ws://example.invalid:8181/abc/ws');

      await expectLater(client.disconnect(), completes);
    });
  });
}
