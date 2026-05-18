import 'dart:io';

/// Signature for the [Process.start] seam, injectable in tests.
///
/// Mirrors the subset of [Process.start] parameters that [FlutterCreateRunner]
/// uses: executable, arguments, optional workingDirectory, and mode.
/// The [mode] parameter is nullable so test fakes can omit it comfortably;
/// [_defaultStarter] bridges the gap to [Process.start]'s non-nullable default.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  ProcessStartMode? mode,
});

/// Default [ProcessStarter] that delegates to [Process.start], bridging the
/// nullable [ProcessStartMode?] in [ProcessStarter] to [Process.start]'s
/// non-nullable parameter with a default.
Future<Process> _defaultStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  ProcessStartMode? mode,
}) {
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: mode ?? ProcessStartMode.normal,
  );
}

/// Runs `flutter create --template=package` as a subprocess.
///
/// The child process inherits the parent's stdio via
/// [ProcessStartMode.inheritStdio], so progress lines stream directly to the
/// terminal without buffering.
///
/// ## Constructor injection seam
///
/// ```dart
/// // Production: real subprocess
/// final runner = FlutterCreateRunner();
///
/// // Test: mocked starter
/// final runner = FlutterCreateRunner(processStarter: myFakeStarter);
/// ```
///
/// ## Usage
///
/// ```dart
/// final code = await FlutterCreateRunner().create(
///   packageName: 'my_plugin',
///   targetPath: '/workspace/my_plugin',
///   org: 'com.acme',
/// );
/// if (code != 0) throw StateError('flutter create failed with exit $code');
/// ```
class FlutterCreateRunner {
  /// Creates a runner with an optional [ProcessStarter] override.
  ///
  /// [processStarter] defaults to [Process.start] from `dart:io`, which
  /// resolves the `flutter` executable through `$PATH`. Inject a fake in tests.
  FlutterCreateRunner({ProcessStarter? processStarter})
      : _starter = processStarter ?? _defaultStarter;

  final ProcessStarter _starter;

  /// Spawns `flutter create` for a Dart package and returns the exit code.
  ///
  /// Builds the argument list:
  /// `['create', '--template=package', '--org', org, '--project-name', packageName, targetPath]`
  ///
  /// When [org] is omitted it defaults to `'com.example'`, which is Flutter's
  /// own default and keeps generated Android package IDs valid.
  ///
  /// Idempotency note: `flutter create` does NOT support a `--force` flag (the
  /// equivalent exists on `dart create` only). For re-runs on an existing
  /// non-empty target dir, flutter create exits with a non-zero code and the
  /// caller (MakePluginCommand.handle) is expected to delete the target first
  /// if re-scaffolding is desired. Documented in plan's V1.x followups.
  ///
  /// [description] is accepted but currently unused; it is reserved for a
  /// future `--description` flag pass-through without a breaking API change.
  ///
  /// @param packageName  The Dart package name (snake_case).
  /// @param targetPath   Absolute or relative path to the output directory.
  /// @param org          Reverse-domain org prefix (e.g. `com.acme`).
  /// @param description  Optional package description (reserved, not forwarded yet).
  /// @return             The flutter process exit code.
  /// @throws FormatException when `flutter` is not found in `$PATH`.
  Future<int> create({
    required String packageName,
    required String targetPath,
    String? org,
    String? description,
  }) async {
    final args = <String>[
      'create',
      '--template=package',
      '--org',
      org ?? 'com.example',
      '--project-name',
      packageName,
      targetPath,
    ];

    try {
      final process = await _starter(
        'flutter',
        args,
        mode: ProcessStartMode.inheritStdio,
      );
      return await process.exitCode;
    } on ProcessException catch (e) {
      throw FormatException(
        'flutter create failed: ${e.message}. '
        'Install Flutter SDK or add it to PATH.',
      );
    }
  }
}
