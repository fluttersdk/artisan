import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../helpers/file_helper.dart';
import '../stubs/stub_loader.dart';

/// `make:fast-cli` — scaffold a POSIX shell wrapper (`bin/fsa`) that compiles
/// `bin/dispatcher.dart` into an AOT binary via `dart build cli`, cached at
/// `.artisan/cli-bundle/`. Wrapper auto-detects staleness and re-compiles
/// transparently. Result: ~50ms startup for `./bin/fsa <cmd>` vs ~3s for
/// `dart run fluttersdk_artisan <cmd>`.
///
/// Idempotent: skips `bin/fsa` when it already exists; pass `--force` to
/// overwrite.
///
/// POSIX-only V1 (macOS + Linux); Windows support is deferred.
final class MakeFastCliCommand extends ArtisanCommand {
  @override
  String get signature => 'make:fast-cli '
      '{--force : Overwrite bin/fsa even when it already exists}';

  @override
  String get description =>
      'Scaffold a fast-CLI wrapper (bin/fsa) plus AOT-compiled artisan '
      'binary, giving local invocations a ~50ms startup vs ~3s with '
      'dart run.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final force = ctx.input.option('force') as bool? ?? false;
    final root = FileHelper.findProjectRoot();
    return scaffoldInto(root: root, force: force, ctx: ctx);
  }

  /// Test seam: replace with a [_RecordingRunner]-style callable in tests.
  ///
  /// Signature matches the [Process.run] overload subset used by this command
  /// (executable + args list + optional workingDirectory). Tests inject a fake
  /// to avoid spinning up real child processes.
  @visibleForTesting
  static Future<ProcessResult> Function(
    String,
    List<String>, {
    String? workingDirectory,
  }) processRunner = Process.run;

  /// Testable entry point. Writes `bin/fsa`, sets executable bit, patches
  /// `.gitignore`, compiles the AOT bundle, and writes the build stamp.
  ///
  /// Idempotent across all phases:
  /// - `bin/fsa` write skips when the target already exists unless [force].
  /// - `.gitignore` append is a no-op when `.artisan/` is already present.
  /// - AOT compile is skipped on subsequent runs when `bin/fsa` exists and
  ///   [force] is false (stamp is written only on first compile).
  ///
  /// Public composition seam: called by both the `make:fast-cli` CLI entry
  /// (via [handle]) and by `InstallCommand.scaffoldInto` (auto-chain at the
  /// end of the canonical `install` flow). The previous `@visibleForTesting`
  /// gate was lifted so cross-command production composition does not trip
  /// `invalid_use_of_visible_for_testing_member`.
  static Future<int> scaffoldInto({
    required String root,
    required bool force,
    required ArtisanContext ctx,
  }) async {
    // 1. Validate pubspec.yaml — confirms we are inside a Dart/Flutter project.
    final pubspecPath = p.join(root, 'pubspec.yaml');
    if (!File(pubspecPath).existsSync()) {
      ctx.output.error(
        'Could not find pubspec.yaml at $pubspecPath. '
        'Run `make:fast-cli` from a Dart/Flutter project root.',
      );
      return 1;
    }

    // 2. Validate bin/dispatcher.dart — the consumer wrapper must exist before
    //    we scaffold the fast-CLI layer on top of it.
    final artisanBinPath = p.join(root, 'bin', 'dispatcher.dart');
    if (!File(artisanBinPath).existsSync()) {
      ctx.output.error(
        'bin/dispatcher.dart not found. Run `install` first.',
      );
      return 1;
    }

    // 3. Write bin/fsa from stub; skip when already present unless forced.
    final binFsaPath = p.join(root, 'bin', 'fsa');
    final wroteWrapper = _shouldWrite(binFsaPath, force);
    if (wroteWrapper) {
      final raw = StubLoader.load('bin_fsa.sh');
      FileHelper.writeFile(binFsaPath, raw);
      ctx.output.success('Created: $binFsaPath');
    } else {
      ctx.output.info('Skipped (exists): $binFsaPath');
    }

    // 4. Set the executable bit on bin/fsa so the user can invoke ./bin/fsa
    //    directly without a leading `sh`. Warn on non-zero exit (Windows may
    //    not have chmod; V1 POSIX-only doctrine means this should succeed on
    //    macOS and Linux).
    if (wroteWrapper) {
      final chmodResult = await processRunner('chmod', ['+x', binFsaPath]);
      if (chmodResult.exitCode != 0) {
        ctx.output.warning(
          'chmod +x $binFsaPath failed (exit ${chmodResult.exitCode}). '
          'Set the executable bit manually before running ./bin/fsa.',
        );
      }
    }

    // 5. Patch .gitignore: append `.artisan/` if not already present.
    //    Creates the file from scratch when it does not exist yet.
    final gitignorePath = p.join(root, '.gitignore');
    final gitignoreFile = File(gitignorePath);
    if (gitignoreFile.existsSync()) {
      final existing = gitignoreFile.readAsStringSync();
      if (!existing.contains('.artisan/')) {
        gitignoreFile.writeAsStringSync(
          existing.endsWith('\n')
              ? '$existing.artisan/\n'
              : '$existing\n.artisan/\n',
        );
      }
    } else {
      gitignoreFile.writeAsStringSync('.artisan/\n');
    }

    // When bin/fsa was not rewritten (idempotent skip), skip the expensive
    // compile so repeated runs do not trigger a multi-second dart build cli.
    if (!wroteWrapper) {
      ctx.output
          .success('fsa: ready. Run ./bin/fsa <cmd> for a ~50ms startup.');
      return 0;
    }

    // 6. Compute pubspec.lock SHA256 for the build stamp.
    final lockFile = File(p.join(root, 'pubspec.lock'));
    final lockBytes =
        lockFile.existsSync() ? lockFile.readAsBytesSync() : <int>[];
    final pubspecLockSha = sha256.convert(lockBytes).toString();

    // 7. Resolve the Dart SDK version for the build stamp.
    final versionResult = await processRunner('dart', ['--version']);
    final versionOutput = (versionResult.stdout as String).isNotEmpty
        ? versionResult.stdout as String
        : versionResult.stderr as String;
    final versionMatch = RegExp(r'(\d+\.\d+[\.\d]*)').firstMatch(versionOutput);
    final dartSdkVer = versionMatch?.group(1) ?? 'unknown';

    // 8. Compile the AOT bundle via dart build cli. Forward stdout + stderr
    //    so the user sees compiler progress. On non-zero exit, report the
    //    error details and surface a non-zero exit code.
    final buildResult = await processRunner(
      'dart',
      [
        'build',
        'cli',
        '-t',
        'bin/dispatcher.dart',
        '-o',
        '.artisan/cli-bundle'
      ],
      workingDirectory: root,
    );
    if (buildResult.stdout is String &&
        (buildResult.stdout as String).isNotEmpty) {
      ctx.output.writeln(buildResult.stdout as String);
    }
    if (buildResult.stderr is String &&
        (buildResult.stderr as String).isNotEmpty) {
      ctx.output.writeln(buildResult.stderr as String);
    }
    if (buildResult.exitCode != 0) {
      ctx.output.error(
        'dart build cli failed (exit ${buildResult.exitCode}). '
        'Output: ${buildResult.stderr}',
      );
      return 1;
    }

    // 9. Write stamp atomically (.tmp + rename) so a partial compile never
    //    leaves a stale stamp. Mirrors InstallTransaction.commit + StateFile.write
    //    atomic-write pattern used throughout artisan.
    final stampContent = '$pubspecLockSha:$dartSdkVer';
    final stampPath = p.join(root, '.artisan', 'build.stamp');
    final tmp = File('$stampPath.tmp');
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(stampContent);
    tmp.renameSync(stampPath);

    // 10. Signal success to the user.
    ctx.output.success('fsa: ready. Run ./bin/fsa <cmd> for a ~50ms startup.');
    return 0;
  }

  /// Returns true when [path] does not exist OR [force] is set.
  static bool _shouldWrite(String path, bool force) {
    if (force) return true;
    return !File(path).existsSync();
  }
}
