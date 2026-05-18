import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/src/commands/helpers/flutter_create_runner.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Minimal [Process] fake. With [ProcessStartMode.inheritStdio] the runner
/// never reads stdout/stderr — but the [Process] interface requires us to
/// expose them, so they return closed streams.
class _FakeProcess implements Process {
  _FakeProcess({required this.fakeExitCode});

  final int fakeExitCode;

  @override
  Future<int> get exitCode async => fakeExitCode;

  // The runner does not read stdout/stderr in inheritStdio mode.
  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => _NullSink();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  int get pid => 0;
}

/// No-op [IOSink] returned from the fake's [stdin].
class _NullSink implements IOSink {
  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {}

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? obj = '']) {}
}

// ---------------------------------------------------------------------------
// Captured invocation helper
// ---------------------------------------------------------------------------

/// Records every [ProcessStarter] call so tests can assert on executable,
/// args, and mode without running a real subprocess.
class _RecordingStarter {
  String? executable;
  List<String>? arguments;
  ProcessStartMode? mode;

  late _FakeProcess returnProcess;

  Future<Process> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
    ProcessStartMode? mode,
  }) async {
    executable = exe;
    arguments = args;
    this.mode = mode;
    return returnProcess;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FlutterCreateRunner', () {
    // ------------------------------------------------------------------
    // 1. Success path: mocked starter returns exit code 0.
    // ------------------------------------------------------------------
    test('create() returns 0 on success', () async {
      final starter = _RecordingStarter()
        ..returnProcess = _FakeProcess(fakeExitCode: 0);

      final runner = FlutterCreateRunner(processStarter: starter.call);
      final code = await runner.create(
        packageName: 'my_plugin',
        targetPath: '/tmp/my_plugin',
      );

      expect(code, 0);
    });

    // ------------------------------------------------------------------
    // 2. Failure path: mocked starter returns non-zero exit code.
    // ------------------------------------------------------------------
    test('create() returns non-zero exit code on process failure', () async {
      final starter = _RecordingStarter()
        ..returnProcess = _FakeProcess(fakeExitCode: 1);

      final runner = FlutterCreateRunner(processStarter: starter.call);
      final code = await runner.create(
        packageName: 'my_plugin',
        targetPath: '/tmp/my_plugin',
      );

      expect(code, 1);
    });

    // ------------------------------------------------------------------
    // 3. Missing binary: ProcessException is caught and rethrown as
    //    FormatException with an actionable message.
    // ------------------------------------------------------------------
    test(
      'create() throws FormatException with actionable message when flutter '
      'binary is missing',
      () async {
        Future<Process> missingBinaryStarter(
          String exe,
          List<String> args, {
          String? workingDirectory,
          ProcessStartMode? mode,
        }) async {
          throw ProcessException(
            'flutter',
            args,
            'No such file or directory',
            2,
          );
        }

        final runner =
            FlutterCreateRunner(processStarter: missingBinaryStarter);

        await expectLater(
          () => runner.create(
            packageName: 'my_plugin',
            targetPath: '/tmp/my_plugin',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('flutter create failed'),
                contains('PATH'),
              ),
            ),
          ),
        );
      },
    );

    // ------------------------------------------------------------------
    // 4. Command construction shape: assert exact args list.
    // ------------------------------------------------------------------
    test('create() builds the correct args list with explicit org', () async {
      final starter = _RecordingStarter()
        ..returnProcess = _FakeProcess(fakeExitCode: 0);

      final runner = FlutterCreateRunner(processStarter: starter.call);
      await runner.create(
        packageName: 'magic_logger',
        targetPath: '/out/magic_logger',
        org: 'com.acme',
      );

      expect(starter.executable, 'flutter');
      expect(
        starter.arguments,
        equals(<String>[
          'create',
          '--template=package',
          '--org',
          'com.acme',
          '--project-name',
          'magic_logger',
          '/out/magic_logger',
        ]),
      );
      expect(starter.mode, ProcessStartMode.inheritStdio);
    });

    // ------------------------------------------------------------------
    // 5. Default org falls back to 'com.example' when not supplied.
    // ------------------------------------------------------------------
    test('create() uses com.example as default org when org is null', () async {
      final starter = _RecordingStarter()
        ..returnProcess = _FakeProcess(fakeExitCode: 0);

      final runner = FlutterCreateRunner(processStarter: starter.call);
      await runner.create(
        packageName: 'my_plugin',
        targetPath: '/tmp/my_plugin',
      );

      expect(starter.arguments, contains('com.example'));
    });
  });
}
