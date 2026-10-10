import 'dart:convert';
import 'dart:io';

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

  group('VmServiceClient.callServiceExtension (method not found)', () {
    late HttpServer server;
    late VmServiceClient client;

    // Answers each extension call with the next entry of [replies] (an
    // `error` or a `result` member), and `getVM` with a single isolate whose
    // id is [isolateId].
    Future<void> serve(
      List<Map<String, dynamic>> replies, {
      String isolateId = 'isolates/1',
    }) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.transform(WebSocketTransformer()).listen((WebSocket socket) {
        socket.listen((dynamic raw) {
          final Map<String, dynamic> request =
              jsonDecode(raw as String) as Map<String, dynamic>;
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': request['id'],
              if (request['method'] == 'getVM')
                'result': <String, dynamic>{
                  'type': 'VM',
                  'isolates': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'type': '@Isolate',
                      'id': isolateId,
                      'name': 'main',
                      'number': '1',
                    },
                  ],
                }
              else
                ...replies.removeAt(0),
            }),
          );
        });
      });
      client = VmServiceClient('ws://127.0.0.1:${server.port}/ws');
      await client.connect();
    }

    const Map<String, dynamic> methodNotFound = <String, dynamic>{
      'error': <String, dynamic>{
        'code': -32601,
        'message': 'Method not found',
        'data': <String, dynamic>{},
      },
    };

    tearDown(() async {
      await client.disconnect();
      await server.close(force: true);
    });

    test('maps -32601 on the first call', () async {
      await serve(<Map<String, dynamic>>[methodNotFound]);

      await expectLater(
        client.callServiceExtension<Object?>(
          'ext.dusk.snapshot',
          isolateId: 'isolates/1',
        ),
        throwsA(
          isA<ExtensionNotRegisteredException>().having(
            (e) => e.method,
            'method',
            'ext.dusk.snapshot',
          ),
        ),
      );
    });

    test('maps -32601 on the retry after a collected promise', () async {
      await serve(<Map<String, dynamic>>[
        <String, dynamic>{
          'error': <String, dynamic>{
            'code': -32603,
            'message': 'WipError -32000 Promise was collected',
            'data': <String, dynamic>{},
          },
        },
        methodNotFound,
      ]);

      await expectLater(
        client.callServiceExtension<Object?>(
          'ext.dusk.snapshot',
          isolateId: 'isolates/1',
        ),
        throwsA(isA<ExtensionNotRegisteredException>()),
      );
    });

    test('maps -32601 on the retry against a refreshed isolate', () async {
      // A hot restart minted isolates/2 before its plugins registered their
      // extensions: the stale id answers with a sentinel, the fresh one with
      // method not found.
      await serve(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'result': <String, dynamic>{
              'type': 'Sentinel',
              'kind': 'Collected',
              'valueAsString': '<collected>',
            },
          },
          methodNotFound,
        ],
        isolateId: 'isolates/2',
      );

      await expectLater(
        client.callServiceExtension<Object?>(
          'ext.dusk.snapshot',
          isolateId: 'isolates/1',
        ),
        throwsA(isA<ExtensionNotRegisteredException>()),
      );
    });
  });
}
