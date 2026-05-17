import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanCommandCollisionException', () {
    test('stores the three positional fields', () {
      final exception = ArtisanCommandCollisionException(
        commandName: 'foo',
        existingProvider: 'a',
        newProvider: 'b',
      );

      expect(exception.commandName, 'foo');
      expect(exception.existingProvider, 'a');
      expect(exception.newProvider, 'b');
    });

    test('message names the duplicate command', () {
      final exception = ArtisanCommandCollisionException(
        commandName: 'dusk:snap',
        existingProvider: 'dusk',
        newProvider: 'telescope',
      );

      expect(exception.message, contains("'dusk:snap'"));
    });

    test('message names both providers', () {
      final exception = ArtisanCommandCollisionException(
        commandName: 'foo',
        existingProvider: 'first',
        newProvider: 'second',
      );

      expect(exception.message, contains("'first'"));
      expect(exception.message, contains('second'));
    });

    test('message hints at the override escape hatch', () {
      final exception = ArtisanCommandCollisionException(
        commandName: 'foo',
        existingProvider: 'a',
        newProvider: 'b',
      );

      expect(exception.message, contains('override: true'));
    });

    test('toString prefixes the class name', () {
      final exception = ArtisanCommandCollisionException(
        commandName: 'foo',
        existingProvider: 'a',
        newProvider: 'b',
      );

      expect(
        exception.toString(),
        startsWith('ArtisanCommandCollisionException:'),
      );
    });
  });
}
