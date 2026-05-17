import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArgvInput', () {
    test('option returns the parsed value', () {
      final parser = ArgParser()..addOption('device', defaultsTo: 'chrome');
      final input = ArgvInput.parse(parser, <String>['--device=macos']);

      expect(input.option('device'), 'macos');
    });

    test('option returns null when the option name is not declared', () {
      final parser = ArgParser()..addOption('known');
      final input = ArgvInput.parse(parser, <String>[]);

      expect(input.option('unknown'), isNull);
    });

    test('argument returns rest values by index', () {
      final parser = ArgParser();
      final input = ArgvInput.parse(parser, <String>['first', 'second']);

      expect(input.argument(0), 'first');
      expect(input.argument(1), 'second');
    });

    test('argument returns null when index is out of range', () {
      final parser = ArgParser();
      final input = ArgvInput.parse(parser, <String>['only']);

      expect(input.argument(5), isNull);
    });

    test('hasOption is true only when the user passed the flag', () {
      final parser = ArgParser()..addFlag('force', negatable: false);

      final passed = ArgvInput.parse(parser, <String>['--force']);
      final omitted = ArgvInput.parse(parser, <String>[]);

      expect(passed.hasOption('force'), isTrue);
      expect(omitted.hasOption('force'), isFalse);
    });

    test('verbosity defaults to 1 when no flag passed', () {
      final parser = ArgParser();
      final input = ArgvInput.parse(parser, <String>[]);

      expect(input.verbosity, 1);
    });

    test('verbosity bumps to 2 for --verbose', () {
      final parser = ArgParser()..addFlag('verbose', negatable: false);

      expect(ArgvInput.parse(parser, <String>['--verbose']).verbosity, 2);
    });

    test('verbosity bumps to 4 for --debug', () {
      final parser = ArgParser()..addFlag('debug', negatable: false);

      expect(ArgvInput.parse(parser, <String>['--debug']).verbosity, 4);
    });

    test('verbosity drops to 0 for --quiet', () {
      final parser = ArgParser()..addFlag('quiet', negatable: false);

      expect(ArgvInput.parse(parser, <String>['--quiet']).verbosity, 0);
    });

    test('-v ladder via positional rest tokens', () {
      // The verbosity scanner reads the raw arguments list. We can pass the
      // ladder tokens as positional (after `--`) so the parser does not
      // reject them as unknown options.
      final parser = ArgParser();

      expect(
        ArgvInput.parse(parser, <String>['--', '-v']).verbosity,
        2,
        reason: '-v alone -> verbose',
      );
      expect(
        ArgvInput.parse(parser, <String>['--', '-vv']).verbosity,
        2,
      );
      expect(
        ArgvInput.parse(parser, <String>['--', '-vvv']).verbosity,
        3,
      );
      expect(
        ArgvInput.parse(parser, <String>['--', '-vvvv']).verbosity,
        4,
      );
    });

    test('-q via positional rest tokens drops to 0', () {
      final parser = ArgParser();

      expect(ArgvInput.parse(parser, <String>['--', '-q']).verbosity, 0);
    });
  });

  group('MapInput', () {
    test('option reads from the supplied map', () {
      final input = MapInput(const {'foo': 'bar'});

      expect(input.option('foo'), 'bar');
    });

    test('option returns null for unknown keys', () {
      final input = MapInput(const {});

      expect(input.option('missing'), isNull);
    });

    test('argument reads from the positional list', () {
      final input = MapInput(const {}, positional: <String>['a', 'b']);

      expect(input.argument(0), 'a');
      expect(input.argument(1), 'b');
      expect(input.argument(2), isNull);
    });

    test('hasOption is true only when the key is present in the map', () {
      final input = MapInput(const {'present': null});

      expect(input.hasOption('present'), isTrue);
      expect(input.hasOption('absent'), isFalse);
    });

    test('verbosity defaults to 1 when no override supplied', () {
      final input = MapInput(const {});

      expect(input.verbosity, 1);
    });

    test('verbosity reflects the constructor override', () {
      final input = MapInput(const {}, verbosity: 3);

      expect(input.verbosity, 3);
    });
  });
}
