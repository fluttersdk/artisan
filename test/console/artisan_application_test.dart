import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Run [body] capturing everything written to `stderr` and `stdout`, so the
/// dispatch path's user-facing output can be asserted in-process.
Future<({int code, String err, String out})> _captureDispatch(
  Future<int> Function() body,
) async {
  final err = _CapturingStdout();
  final out = _CapturingStdout();
  final code = await IOOverrides.runZoned(
    body,
    stderr: () => err,
    stdout: () => out,
  );
  return (code: code, err: err.buffer.toString(), out: out.buffer.toString());
}

void main() {
  group('ArtisanApplication.dispatch', () {
    test('empty args prints root help and exits 0', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      final code = await app.dispatch(<String>[]);

      expect(code, 0);
    });

    test('--help prints root help and exits 0', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      expect(await app.dispatch(<String>['--help']), 0);
      expect(await app.dispatch(<String>['-h']), 0);
    });

    test('--version prints version and exits 0', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      expect(await app.dispatch(<String>['--version']), 0);
      expect(await app.dispatch(<String>['-V']), 0);
    });

    test('unknown command exits 1', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      final code = await app.dispatch(<String>['no-such-command']);

      expect(code, 1);
    });

    test('dispatches to a registered bare command and propagates exit code',
        () async {
      final registry = ArtisanRegistry();
      registry.register(_FixedExitCommand('exit-7', 7));
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['exit-7']);

      expect(code, 7);
    });

    test('unknown long flag errors clearly on stderr and exits non-zero',
        () async {
      final registry = ArtisanRegistry();
      registry.register(_OptionCommand());
      final app = ArtisanApplication(registry: registry);

      final result = await _captureDispatch(
        () => app.dispatch(<String>['has-option', '--unknown']),
      );

      expect(result.code, isNonZero);
      expect(result.err, contains('Unknown option: --unknown'));
    });

    test('unknown short flag errors clearly on stderr and exits non-zero',
        () async {
      final registry = ArtisanRegistry();
      registry.register(_OptionCommand());
      final app = ArtisanApplication(registry: registry);

      final result = await _captureDispatch(
        () => app.dispatch(<String>['has-option', '-x']),
      );

      expect(result.code, isNonZero);
      expect(result.err, contains('Unknown option: -x'));
    });

    test('valid flag set parses unchanged and reaches handle', () async {
      final command = _OptionCommand();
      final registry = ArtisanRegistry();
      registry.register(command);
      final app = ArtisanApplication(registry: registry);

      final result = await _captureDispatch(
        () => app.dispatch(<String>['has-option', '--output', 'build/app']),
      );

      expect(result.code, 0);
      expect(command.capturedOutput, 'build/app');
      expect(result.err, isEmpty);
    });

    test('command --help still prints help and exits 0 unchanged', () async {
      final command = _OptionCommand();
      final registry = ArtisanRegistry();
      registry.register(command);
      final app = ArtisanApplication(registry: registry);

      final result = await _captureDispatch(
        () => app.dispatch(<String>['has-option', '--help']),
      );

      expect(result.code, 0);
      expect(command.handleCalls, 0);
      expect(result.err, isEmpty);
    });

    test('genuine missing-required-value error keeps its original message',
        () async {
      final registry = ArtisanRegistry();
      registry.register(_OptionCommand());
      final app = ArtisanApplication(registry: registry);

      final result = await _captureDispatch(
        () => app.dispatch(<String>['has-option', '--output']),
      );

      expect(result.code, isNonZero);
      expect(result.err, contains('Missing argument for "--output"'));
      expect(result.err, isNot(contains('Unknown option')));
    });

    test('command --help (per-command) returns 0 without running handle',
        () async {
      final command = _RecordingCommand();
      final registry = ArtisanRegistry();
      registry.register(command);
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['recording', '--help']);

      expect(code, 0);
      expect(command.calls, 0);
    });

    test('exception from handle returns exit 3', () async {
      final registry = ArtisanRegistry();
      registry.register(_ThrowingCommand());
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['throws']);

      expect(code, 3);
    });

    test('connected-mode command without state.json returns 1', () async {
      StateFile.debugHomeOverride =
          '/tmp/artisan_app_test_${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() => StateFile.debugHomeOverride = null);

      final registry = ArtisanRegistry();
      registry.register(_ConnectedCommand());
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['connected']);

      expect(code, 1);
    });

    test('default version is the published alpha tag', () {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      expect(app.version, ArtisanApplication.defaultVersion);
    });

    test('custom version is honored', () {
      final app = ArtisanApplication(
        registry: ArtisanRegistry(),
        version: '9.9.9',
      );

      expect(app.version, '9.9.9');
    });

    test('dispatch threads its registry into the context', () async {
      final registry = ArtisanRegistry();
      final capturingCommand = _RegistryCapturingCommand();
      registry.register(capturingCommand);
      final app = ArtisanApplication(registry: registry);

      await app.dispatch(<String>['capture-registry']);

      expect(capturingCommand.capturedRegistry, same(registry));
    });
  });
}

class _FixedExitCommand extends ArtisanCommand {
  _FixedExitCommand(this._name, this._exit);
  final String _name;
  final int _exit;

  @override
  String get name => _name;

  @override
  String get description => 'fixed exit';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => _exit;
}

class _OptionCommand extends ArtisanCommand {
  int handleCalls = 0;
  String? capturedOutput;

  @override
  String get name => 'has-option';

  @override
  String get description => 'declares a single --output option';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    parser.addOption('output', abbr: 'o', help: 'Output path');
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    handleCalls++;
    capturedOutput = ctx.input.option('output') as String?;
    return 0;
  }
}

class _RecordingCommand extends ArtisanCommand {
  int calls = 0;

  @override
  String get name => 'recording';

  @override
  String get description => 'records handle calls';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    calls++;
    return 0;
  }
}

class _ThrowingCommand extends ArtisanCommand {
  @override
  String get name => 'throws';

  @override
  String get description => 'always throws';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => throw StateError('boom');
}

class _ConnectedCommand extends ArtisanCommand {
  @override
  String get name => 'connected';

  @override
  String get description => 'requires a connected context';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _RegistryCapturingCommand extends ArtisanCommand {
  ArtisanRegistry? capturedRegistry;

  @override
  String get name => 'capture-registry';

  @override
  String get description => 'captures ctx.registry for assertion';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    capturedRegistry = ctx.registry;
    return 0;
  }
}

/// File-private [Stdout] fake that buffers writes for assertion. Used via
/// [IOOverrides.runZoned] to capture the dispatch path's stderr/stdout output
/// for both the [stdout:] and [stderr:] override slots (both slots accept a
/// [Stdout] factory in Dart's IO model).
class _CapturingStdout implements Stdout {
  final StringBuffer buffer = StringBuffer();

  @override
  Encoding encoding = systemEncoding;

  @override
  String lineTerminator = '\n';

  // --- StringSink writes (buffered for assertion) ---

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) =>
      buffer.writeAll(objects, sep);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  // --- StreamSink<List<int>> (bytes, decoded and buffered) ---

  @override
  void add(List<int> data) => buffer.write(encoding.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> flush() => Future<void>.value();

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> close() => Future<void>.value();

  // --- Stdout terminal-query members (no-op in tests) ---

  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  IOSink get nonBlocking => this;
}
