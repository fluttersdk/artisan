import 'dart:io';

import 'package:path/path.dart' as p;

/// Invalidates the AOT cli-bundle so the next `./bin/fsa` invocation rebuilds
/// against the freshly-regenerated `lib/app/_plugins.g.dart`.
///
/// Motivating bug: GitHub issue #9 GAP A. After `plugin:install` (or
/// `plugin:uninstall`, or `plugins:refresh`) writes a new
/// `lib/app/_plugins.g.dart`, the on-disk AOT bundle compiled before the
/// update still points at the OLD codegen barrel. The next `./bin/fsa` call
/// runs the stale bundle, silently missing the newly registered plugin tools.
/// Deleting `.artisan/cli-bundle/` and `.artisan/build.stamp` forces the
/// staleness check in `bin/fsa` to treat the bundle as outdated, triggering a
/// fresh compile on the very next invocation.
///
/// All operations are best-effort: missing files and directories are NOT an
/// error. Any [FileSystemException] thrown by the underlying I/O is swallowed
/// so callers never see a fatal error from a cosmetic cache-cleanup step
/// (mirrors the `stop_command.dart:162-173` safe-delete pattern).
final class CliBundleCache {
  /// Private const constructor: [CliBundleCache] is a purely-static utility.
  /// Never instantiate; call [purge] directly.
  const CliBundleCache._();

  /// Purges the AOT cli-bundle cache for the project rooted at [projectRoot].
  ///
  /// Deletes:
  ///   - `<projectRoot>/.artisan/cli-bundle/` (the AOT-compiled bundle dir).
  ///   - `<projectRoot>/.artisan/build.stamp` (the staleness sentinel file).
  ///
  /// Both deletions are wrapped individually so a failure on the directory
  /// does not prevent the stamp from being removed, and vice-versa.
  ///
  /// @param projectRoot  Absolute path to the consumer project root (the
  ///                     directory that contains `pubspec.yaml`).
  static void purge(String projectRoot) {
    final cacheDir = Directory(p.join(projectRoot, '.artisan', 'cli-bundle'));
    final stamp = File(p.join(projectRoot, '.artisan', 'build.stamp'));

    // 1. Remove the compiled AOT bundle directory (recursive).
    try {
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Swallow: a stale bundle directory is not worth aborting for.
    }

    // 2. Remove the build stamp so needs_build() trips on next ./bin/fsa call.
    try {
      if (stamp.existsSync()) {
        stamp.deleteSync();
      }
    } catch (_) {
      // Swallow: a missing or undeletable stamp is not worth aborting for.
    }
  }
}
