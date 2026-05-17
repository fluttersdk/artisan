import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanContext.bare', () {
    test('exposes input and output', () {
      final input = MapInput(const {'k': 'v'});
      final output = BufferedOutput();

      final ctx = ArtisanContext.bare(input, output);

      expect(ctx.input, same(input));
      expect(ctx.output, same(output));
    });

    test('vmClient is null', () {
      final ctx = ArtisanContext.bare(MapInput(const {}), BufferedOutput());

      expect(ctx.vmClient, isNull);
    });

    test('callExtension throws StateError citing connected-mode requirement',
        () async {
      final ctx = ArtisanContext.bare(MapInput(const {}), BufferedOutput());

      expect(
        () => ctx.callExtension('ext.flutter.reassemble'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CommandBoot.connected'),
          ),
        ),
      );
    });

    test('evaluate throws StateError citing connected-mode requirement',
        () async {
      final ctx = ArtisanContext.bare(MapInput(const {}), BufferedOutput());

      expect(
        () => ctx.evaluate('1 + 1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CommandBoot.connected'),
          ),
        ),
      );
    });
  });

  group('ArtisanContext.connected', () {
    test('exposes the supplied VmServiceClient', () {
      final client = VmServiceClient('ws://example.invalid:1/ws');
      final ctx = ArtisanContext.connected(
        MapInput(const {}),
        BufferedOutput(),
        client,
      );

      expect(ctx.vmClient, same(client));
    });

    test('input and output forwarded to the connected ctx', () {
      final input = MapInput(const {});
      final output = BufferedOutput();
      final client = VmServiceClient('ws://example.invalid:1/ws');

      final ctx = ArtisanContext.connected(input, output, client);

      expect(ctx.input, same(input));
      expect(ctx.output, same(output));
    });
  });
}
