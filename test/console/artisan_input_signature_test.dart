import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArgvInput.argument by name', () {
    test('returns null when name unknown without signature', () {
      final input = ArgvInput.parse(ArgParser(), <String>['acme']);
      expect(input.argument('team'), isNull);
    });

    test('resolves name via signature', () {
      final sig = CommandSignature.parse('sync {team} {scope?}');
      final parser = ArgParser();
      sig.applyTo(parser);
      final input = ArgvInput.parse(
        parser,
        <String>['acme', 'active'],
        signature: sig,
      );
      expect(input.argument('team'), 'acme');
      expect(input.argument('scope'), 'active');
    });

    test('falls back to default when positional missing', () {
      final sig = CommandSignature.parse('sync {team} {scope=all}');
      final parser = ArgParser();
      sig.applyTo(parser);
      final input = ArgvInput.parse(
        parser,
        <String>['acme'],
        signature: sig,
      );
      expect(input.argument('team'), 'acme');
      expect(input.argument('scope'), 'all');
    });

    test('returns null for non-int / non-string indices', () {
      final input = ArgvInput.parse(ArgParser(), <String>[]);
      expect(input.argument(3.14), isNull);
    });

    test('returns null when string name not in signature', () {
      final sig = CommandSignature.parse('sync {team}');
      final parser = ArgParser();
      sig.applyTo(parser);
      final input = ArgvInput.parse(
        parser,
        <String>['acme'],
        signature: sig,
      );
      expect(input.argument('unknown'), isNull);
    });
  });

  group('MapInput.argument by name', () {
    test('resolves name via signature when not in options map', () {
      final sig = CommandSignature.parse('sync {team} {scope?}');
      final input = MapInput(
        const <String, dynamic>{},
        positional: const <String>['acme', 'active'],
        signature: sig,
      );
      expect(input.argument('team'), 'acme');
      expect(input.argument('scope'), 'active');
    });

    test('options-map keyed lookup wins over signature', () {
      // Test-pattern: callers sometimes pass positional values as keyed
      // entries on the options map for clarity. That direct hit wins.
      final sig = CommandSignature.parse('sync {team}');
      final input = MapInput(
        const <String, dynamic>{'team': 'override-via-map'},
        positional: const <String>['acme'],
        signature: sig,
      );
      expect(input.argument('team'), 'override-via-map');
    });

    test('default fallback from signature', () {
      final sig = CommandSignature.parse('sync {team} {scope=all}');
      final input = MapInput(
        const <String, dynamic>{},
        positional: const <String>['acme'],
        signature: sig,
      );
      expect(input.argument('scope'), 'all');
    });

    test('returns null for non-int / non-string indices', () {
      final input = MapInput(const <String, dynamic>{});
      expect(input.argument(true), isNull);
    });

    test('returns null when no signature + name unknown', () {
      final input = MapInput(const <String, dynamic>{});
      expect(input.argument('team'), isNull);
    });
  });
}
