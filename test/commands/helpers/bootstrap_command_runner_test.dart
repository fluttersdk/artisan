import 'dart:io';

import 'package:fluttersdk_artisan/src/commands/helpers/bootstrap_command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Records every [ProcessRunner] call so tests can assert on executable, args,
/// and working directory without spawning a real subprocess.
class _RecordingRunner {
  String? executable;
  List<String>? arguments;
  String? workingDirectory;

  ProcessResult returnResult = ProcessResult(0, 0, '', '');

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    executable = exe;
    arguments = args;
    this.workingDirectory = workingDirectory;
    return returnResult;
  }
}

void main() {
  group('BootstrapCommandRunner — dispatcher resolution', () {
    test('prefers ./bin/fsa when the wrapper exists', () async {
      final root = Directory.systemTemp.createTempSync('bootstrap_fsa_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'bin')).createSync(recursive: true);
      File(p.join(root.path, 'bin', 'fsa')).writeAsStringSync('#!/bin/sh\n');

      final runner = _RecordingRunner();
      final result =
          await BootstrapCommandRunner(processRunner: runner.call).run(
        bootstrapCommand: 'starter:install',
        projectRoot: root.path,
      );

      expect(result.outcome, BootstrapRunOutcome.invoked);
      expect(runner.executable, './bin/fsa');
      expect(
        runner.arguments,
        equals(<String>['starter:install', '--non-interactive']),
      );
      expect(runner.workingDirectory, root.path);
    });

    test(
        'falls back to dart run <consumer>:artisan when bin/fsa is absent but '
        'the consumer pubspec resolves a package name', () async {
      final root = Directory.systemTemp.createTempSync('bootstrap_dartrun_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
        'name: my_app\n'
        'environment:\n'
        "  sdk: '>=3.4.0 <4.0.0'\n",
      );

      final runner = _RecordingRunner();
      final result =
          await BootstrapCommandRunner(processRunner: runner.call).run(
        bootstrapCommand: 'starter:install',
        projectRoot: root.path,
      );

      expect(result.outcome, BootstrapRunOutcome.invoked);
      expect(runner.executable, 'dart');
      expect(
        runner.arguments,
        equals(<String>[
          'run',
          'my_app:artisan',
          'starter:install',
          '--non-interactive',
        ]),
      );
      expect(runner.workingDirectory, root.path);
    });

    test(
        'reports notResolvable when neither bin/fsa nor a consumer package '
        'name is available', () async {
      final root = Directory.systemTemp.createTempSync('bootstrap_unresolv_');
      addTearDown(() => root.deleteSync(recursive: true));
      // No bin/fsa, no pubspec → nothing to dispatch through.

      final runner = _RecordingRunner();
      final result =
          await BootstrapCommandRunner(processRunner: runner.call).run(
        bootstrapCommand: 'starter:install',
        projectRoot: root.path,
      );

      expect(result.outcome, BootstrapRunOutcome.notResolvable);
      expect(runner.executable, isNull,
          reason: 'no dispatcher means the runner is never invoked');
    });

    test('surfaces the subprocess exit code and stderr on failure', () async {
      final root = Directory.systemTemp.createTempSync('bootstrap_fail_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'bin')).createSync(recursive: true);
      File(p.join(root.path, 'bin', 'fsa')).writeAsStringSync('#!/bin/sh\n');

      final runner = _RecordingRunner()
        ..returnResult =
            ProcessResult(0, 64, '', 'Unknown command: starter:install');
      final result =
          await BootstrapCommandRunner(processRunner: runner.call).run(
        bootstrapCommand: 'starter:install',
        projectRoot: root.path,
      );

      expect(result.outcome, BootstrapRunOutcome.invoked);
      expect(result.succeeded, isFalse);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('Unknown command'));
    });

    test('reports succeeded when the subprocess exits zero', () async {
      final root = Directory.systemTemp.createTempSync('bootstrap_ok_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'bin')).createSync(recursive: true);
      File(p.join(root.path, 'bin', 'fsa')).writeAsStringSync('#!/bin/sh\n');

      final runner = _RecordingRunner()
        ..returnResult = ProcessResult(0, 0, '', '');
      final result =
          await BootstrapCommandRunner(processRunner: runner.call).run(
        bootstrapCommand: 'starter:install',
        projectRoot: root.path,
      );

      expect(result.succeeded, isTrue);
      expect(result.exitCode, 0);
    });

    test('always forwards --non-interactive to the chained command', () async {
      final root = Directory.systemTemp.createTempSync('bootstrap_noninter_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'bin')).createSync(recursive: true);
      File(p.join(root.path, 'bin', 'fsa')).writeAsStringSync('#!/bin/sh\n');

      final runner = _RecordingRunner();
      await BootstrapCommandRunner(processRunner: runner.call).run(
        bootstrapCommand: 'logger:install',
        projectRoot: root.path,
      );

      expect(runner.arguments, contains('--non-interactive'));
    });
  });
}
