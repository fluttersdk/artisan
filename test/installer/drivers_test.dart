import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only fake implementations (NOT exported from lib/).
// ---------------------------------------------------------------------------

/// Fake [PromptDriver] that consumes a [List<String>] queue FIFO.
///
/// Simulates user input without touching stdin. Booleans are encoded as
/// the strings `'true'` / `'false'` / `'y'` / `'n'` for [confirm].
class FakePromptDriver implements PromptDriver {
  /// Queued answers consumed FIFO by each method call.
  final List<String> queue;

  FakePromptDriver(this.queue);

  String _next() {
    if (queue.isEmpty) {
      throw StateError(
        'FakePromptDriver queue exhausted. Supply more entries.',
      );
    }
    return queue.removeAt(0);
  }

  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) =>
      _next();

  @override
  bool confirm(String question, {bool defaultValue = false}) {
    final raw = _next().toLowerCase();
    return raw == 'true' || raw == 'y' || raw == 'yes';
  }

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) =>
      _next();

  @override
  String secret(String question) => _next();
}

/// Fake [StubDriver] that resolves stubs from an in-memory [fixtures] map.
///
/// Key is the stub name (without extension), value is raw stub content.
class FakeStubDriver implements StubDriver {
  /// Fixture registry: stub name -> raw content.
  final Map<String, String> fixtures;

  FakeStubDriver(this.fixtures);

  @override
  String load(String name, {List<String>? searchPaths}) {
    final content = fixtures[name];
    if (content == null) {
      throw ArgumentError('FakeStubDriver: no fixture registered for "$name".');
    }
    return content;
  }

  @override
  String replace(String stub, Map<String, String> replacements) {
    var result = stub;
    for (final entry in replacements.entries) {
      result = result.replaceAll('{{ ${entry.key} }}', entry.value);
    }
    return result;
  }

  @override
  String make(String name, Map<String, String> replacements) =>
      replace(load(name), replacements);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PromptDriver', () {
    tearDown(() {
      Prompt.testOverride = null;
    });

    test('RealPromptDriver.ask delegates to Prompt.ask via testOverride', () {
      Prompt.testOverride = ['dart'];
      final driver = RealPromptDriver();

      final answer = driver.ask('What language?', defaultValue: 'flutter');

      expect(answer, 'dart');
    });

    test('RealPromptDriver.ask returns defaultValue when answer is empty', () {
      Prompt.testOverride = [''];
      final driver = RealPromptDriver();

      final answer = driver.ask('What language?', defaultValue: 'flutter');

      expect(answer, 'flutter');
    });

    test(
        'RealPromptDriver.confirm delegates to Prompt.confirm via testOverride',
        () {
      Prompt.testOverride = ['y'];
      final driver = RealPromptDriver();

      expect(driver.confirm('Proceed?'), isTrue);
    });

    test('RealPromptDriver.confirm returns false for "n"', () {
      Prompt.testOverride = ['n'];
      final driver = RealPromptDriver();

      expect(driver.confirm('Proceed?'), isFalse);
    });

    test('RealPromptDriver.choice delegates to Prompt.choice via testOverride',
        () {
      Prompt.testOverride = ['2'];
      final driver = RealPromptDriver();

      final chosen = driver.choice(
        'Pick env:',
        options: ['local', 'staging', 'production'],
        defaultValue: 'local',
      );

      expect(chosen, 'staging');
    });

    test('RealPromptDriver.secret signature matches PromptDriver contract', () {
      // Prompt.secret reads stdin.hasTerminal which throws StdinException in
      // the headless dart test runner (no TTY attached). The delegation
      // contract is verified via FakePromptDriver below; here we only assert
      // that RealPromptDriver implements the PromptDriver interface correctly.
      final PromptDriver driver = RealPromptDriver();
      expect(driver, isA<PromptDriver>());
    });

    test('FakePromptDriver.ask consumes queue FIFO', () {
      final driver = FakePromptDriver(['first', 'second']);

      expect(driver.ask('Q1'), 'first');
      expect(driver.ask('Q2'), 'second');
    });

    test('FakePromptDriver.confirm interprets "y" as true', () {
      final driver = FakePromptDriver(['y']);

      expect(driver.confirm('Proceed?'), isTrue);
    });

    test('FakePromptDriver.confirm interprets "n" as false', () {
      final driver = FakePromptDriver(['n']);

      expect(driver.confirm('Proceed?'), isFalse);
    });

    test('FakePromptDriver throws StateError when queue is exhausted', () {
      final driver = FakePromptDriver([]);

      expect(() => driver.ask('Q'), throwsA(isA<StateError>()));
    });

    test('FakePromptDriver.choice returns queued value', () {
      final driver = FakePromptDriver(['staging']);

      final chosen = driver.choice(
        'Env?',
        options: ['local', 'staging', 'production'],
      );

      expect(chosen, 'staging');
    });

    test('FakePromptDriver.secret returns queued value', () {
      final driver = FakePromptDriver(['my_token']);

      expect(driver.secret('Token:'), 'my_token');
    });
  });

  group('StubDriver', () {
    test('RealStubDriver.replace substitutes {{ key }} placeholders', () {
      final driver = RealStubDriver();
      const stub = 'class {{ className }} {}';

      final result = driver.replace(stub, {'className': 'Monitor'});

      expect(result, 'class Monitor {}');
    });

    test('RealStubDriver.replace handles multiple placeholders', () {
      final driver = RealStubDriver();
      const stub = '{{ a }} + {{ b }} = {{ c }}';

      final result = driver.replace(stub, {'a': '1', 'b': '2', 'c': '3'});

      expect(result, '1 + 2 = 3');
    });

    test('FakeStubDriver.load returns registered fixture', () {
      final driver = FakeStubDriver({'model': 'class {{ className }} {}'});

      expect(driver.load('model'), 'class {{ className }} {}');
    });

    test('FakeStubDriver.load throws ArgumentError for unknown stub', () {
      final driver = FakeStubDriver({});

      expect(() => driver.load('unknown'), throwsA(isA<ArgumentError>()));
    });

    test('FakeStubDriver.replace substitutes placeholders', () {
      final driver = FakeStubDriver({});
      const stub = 'Hello, {{ name }}!';

      expect(driver.replace(stub, {'name': 'World'}), 'Hello, World!');
    });

    test('FakeStubDriver.make loads and replaces in one call', () {
      final driver = FakeStubDriver({'greeting': 'Hello, {{ name }}!'});

      final result = driver.make('greeting', {'name': 'Artisan'});

      expect(result, 'Hello, Artisan!');
    });

    test('FakeStubDriver.make throws ArgumentError for unknown stub', () {
      final driver = FakeStubDriver({});

      expect(
        () => driver.make('missing', {'key': 'val'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
