import 'dart:developer' as developer;

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

Future<developer.ServiceExtensionResponse> _handler(
  String method,
  Map<String, String> parameters,
) async {
  return developer.ServiceExtensionResponse.result('{}');
}

void main() {
  group('registerExtensionIdempotent', () {
    test('first registration succeeds without throwing', () {
      expect(
        () => registerExtensionIdempotent('ext.test.first_call', _handler),
        returnsNormally,
      );
    });

    test('duplicate registration is swallowed silently', () {
      registerExtensionIdempotent('ext.test.duplicate', _handler);

      expect(
        () => registerExtensionIdempotent('ext.test.duplicate', _handler),
        returnsNormally,
      );
    });

    test('rethrows ArgumentError when the message is unrelated', () {
      // Registering with an invalid extension name (no `ext.` prefix) raises
      // an ArgumentError that does NOT contain "already registered" or
      // "Extension". The helper must rethrow.
      expect(
        () => registerExtensionIdempotent('invalid_no_prefix', _handler),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
