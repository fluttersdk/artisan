import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => Prompt.testOverride = null);
  tearDown(() => Prompt.testOverride = null);

  group('Prompt.ask', () {
    test('returns the user input trimmed', () {
      Prompt.testOverride = ['  Hello World  '];
      expect(Prompt.ask('name?'), 'Hello World');
    });

    test('returns default when input is empty (just Enter)', () {
      Prompt.testOverride = [''];
      expect(Prompt.ask('name?', defaultValue: 'guest'), 'guest');
    });

    test('returns empty string when no input and no default', () {
      Prompt.testOverride = [''];
      expect(Prompt.ask('name?'), '');
    });

    test('validator re-prompts on failure then accepts on success', () {
      Prompt.testOverride = ['nope', 'good'];
      final got = Prompt.ask(
        'word?',
        validator: (v) => v == 'good' ? null : 'must be "good"',
      );
      expect(got, 'good');
      // Both entries consumed.
      expect(Prompt.testOverride, isEmpty);
    });
  });

  group('Prompt.confirm', () {
    test('y/yes returns true', () {
      Prompt.testOverride = ['y'];
      expect(Prompt.confirm('proceed?'), isTrue);

      Prompt.testOverride = ['YES'];
      expect(Prompt.confirm('proceed?'), isTrue);
    });

    test('n/no returns false', () {
      Prompt.testOverride = ['n'];
      expect(Prompt.confirm('proceed?'), isFalse);

      Prompt.testOverride = ['No'];
      expect(Prompt.confirm('proceed?'), isFalse);
    });

    test('Enter uses defaultValue (true)', () {
      Prompt.testOverride = [''];
      expect(Prompt.confirm('proceed?', defaultValue: true), isTrue);
    });

    test('Enter uses defaultValue (false)', () {
      Prompt.testOverride = [''];
      expect(Prompt.confirm('proceed?'), isFalse);
    });

    test('re-prompts on invalid input', () {
      Prompt.testOverride = ['maybe', 'y'];
      expect(Prompt.confirm('proceed?'), isTrue);
      expect(Prompt.testOverride, isEmpty);
    });
  });

  group('Prompt.choice', () {
    test('accepts 1-based index', () {
      Prompt.testOverride = ['2'];
      expect(
        Prompt.choice('env?', options: ['local', 'staging', 'production']),
        'staging',
      );
    });

    test('accepts the option string directly', () {
      Prompt.testOverride = ['production'];
      expect(
        Prompt.choice('env?', options: ['local', 'staging', 'production']),
        'production',
      );
    });

    test('Enter uses defaultValue when supplied', () {
      Prompt.testOverride = [''];
      expect(
        Prompt.choice(
          'env?',
          options: ['local', 'staging'],
          defaultValue: 'local',
        ),
        'local',
      );
    });

    test('re-prompts on out-of-range index', () {
      Prompt.testOverride = ['9', '1'];
      expect(Prompt.choice('?', options: ['a', 'b']), 'a');
    });

    test('re-prompts on unknown string', () {
      Prompt.testOverride = ['wat', 'b'];
      expect(Prompt.choice('?', options: ['a', 'b']), 'b');
    });

    test('throws ArgumentError on empty options list', () {
      expect(
        () => Prompt.choice('?', options: const []),
        throwsArgumentError,
      );
    });
  });

  group('Prompt.testOverride lifecycle', () {
    test('throws when override list is consumed but more reads requested', () {
      Prompt.testOverride = ['only'];
      Prompt.ask('first');
      expect(() => Prompt.ask('second'), throwsStateError);
    });

    test('null override falls back to real stdin (not exercised here)', () {
      Prompt.testOverride = null;
      // Cannot drive real stdin from a unit test; just assert the override
      // is null and that calling methods would attempt stdin (skip the call).
      expect(Prompt.testOverride, isNull);
    });
  });
}
