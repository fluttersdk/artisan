import 'dart:io';

import 'package:path/path.dart' as p;

/// Signature for the [Process.run] seam, injectable in tests.
///
/// Mirrors the subset of [Process.run] parameters that
/// [BootstrapCommandRunner] uses: executable, arguments, and an optional
/// workingDirectory. Tests pass a recording fake so no real subprocess spawns.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Default [ProcessRunner] that delegates to [Process.run].
Future<ProcessResult> _defaultRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
}

/// Outcome of a [BootstrapCommandRunner.run] attempt.
///
/// - [invoked]: a dispatcher was resolved and the bootstrap command was run
///   as a subprocess (regardless of the chained command's own exit code).
/// - [notResolvable]: no dispatcher could be resolved (no `bin/fsa` wrapper
///   and no consumer package name in `pubspec.yaml`), so nothing was spawned
///   and the caller should fall back to the one-line bootstrap hint.
enum BootstrapRunOutcome {
  invoked,
  notResolvable,
}

/// Runs a plugin's declared `bootstrap_command` as a fresh dispatcher
/// subprocess after `plugin:install` registers the plugin.
///
/// The bootstrap command is a PLUGIN command that was only just written to
/// `lib/app/_plugins.g.dart` during this same install run, so it is NOT
/// loaded in the current process. A fresh dispatcher invocation is the only
/// way to reach it, hence a subprocess rather than an in-process `handle()`.
///
/// ## Dispatcher resolution
///
/// 1. Prefer `./bin/fsa <command> --non-interactive` when a `bin/fsa` wrapper
///    exists at the consumer project root (the AOT fast-CLI path).
/// 2. Otherwise `dart run <pkg>:artisan <command> --non-interactive`, deriving
///    `<pkg>` (the consumer package name) from the project's `pubspec.yaml`
///    `name:` field.
/// 3. When neither resolves, return [BootstrapRunOutcome.notResolvable] so the
///    caller can fall back to printing the bootstrap hint.
///
/// `--non-interactive` is ALWAYS forwarded so an interactive chained install
/// (e.g. `starter:install`) cannot hang waiting on stdin.
///
/// ## Constructor injection seam
///
/// ```dart
/// // Production: real subprocess
/// final runner = BootstrapCommandRunner();
///
/// // Test: recording fake
/// final runner = BootstrapCommandRunner(processRunner: myFakeRunner);
/// ```
class BootstrapCommandRunner {
  /// Creates a runner with an optional [ProcessRunner] override.
  ///
  /// [processRunner] defaults to [Process.run] from `dart:io`. Inject a fake
  /// in tests to assert the resolved command without spawning a process.
  BootstrapCommandRunner({ProcessRunner? processRunner})
      : _runner = processRunner ?? _defaultRunner;

  final ProcessRunner _runner;

  /// Resolves a dispatcher and runs `<bootstrapCommand> --non-interactive`
  /// against [projectRoot].
  ///
  /// @param bootstrapCommand  The plugin command to chain (e.g.
  ///                          `starter:install`).
  /// @param projectRoot       Absolute path to the consumer project root.
  /// @return [BootstrapRunOutcome.invoked] when a dispatcher was resolved and
  ///         the subprocess ran; [BootstrapRunOutcome.notResolvable] when no
  ///         dispatcher could be resolved.
  Future<BootstrapRunOutcome> run({
    required String bootstrapCommand,
    required String projectRoot,
  }) async {
    // 1. Build the dispatcher invocation: bin/fsa fast-CLI when present,
    //    else `dart run <consumer>:artisan`. Return early when neither is
    //    resolvable so the caller can fall back to the hint.
    final invocation = _resolveDispatcher(projectRoot, bootstrapCommand);
    if (invocation == null) return BootstrapRunOutcome.notResolvable;

    // 2. Run the chained command as a subprocess scoped to the consumer root.
    //    The chained command's own exit code does not change this outcome:
    //    "invoked" reports that the auto-run fired, not that it succeeded.
    await _runner(
      invocation.executable,
      invocation.arguments,
      workingDirectory: projectRoot,
    );
    return BootstrapRunOutcome.invoked;
  }

  /// Resolves the dispatcher executable + argument list, or `null` when no
  /// dispatcher is available.
  _DispatcherInvocation? _resolveDispatcher(
    String projectRoot,
    String bootstrapCommand,
  ) {
    const nonInteractive = '--non-interactive';

    // bin/fsa fast-CLI wrapper takes precedence when present.
    if (File(p.join(projectRoot, 'bin', 'fsa')).existsSync()) {
      return _DispatcherInvocation(
        executable: './bin/fsa',
        arguments: <String>[bootstrapCommand, nonInteractive],
      );
    }

    // Fall back to `dart run <consumer>:artisan` using the pubspec name.
    final consumerName = _readConsumerName(projectRoot);
    if (consumerName != null) {
      return _DispatcherInvocation(
        executable: 'dart',
        arguments: <String>[
          'run',
          '$consumerName:artisan',
          bootstrapCommand,
          nonInteractive,
        ],
      );
    }

    return null;
  }

  /// Reads the consumer package name from `<root>/pubspec.yaml` `name:` field.
  /// Returns `null` when the pubspec is missing or has no `name:` entry.
  static String? _readConsumerName(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final match = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(
      pubspec.readAsStringSync(),
    );
    return match?.group(1);
  }
}

/// Resolved dispatcher executable + argument list.
class _DispatcherInvocation {
  const _DispatcherInvocation({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}
