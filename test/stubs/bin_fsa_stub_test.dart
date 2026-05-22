import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Tests for the `bin_fsa.sh.stub` shell stub.
///
/// The fast-CLI wrapper acquires a directory-based atomic lock under
/// `.artisan/.fsa.lock/` so two parallel invocations do not both fire
/// `dart build cli` against the same output path. The original implementation
/// released the lock on `EXIT INT TERM` via `trap`, but SIGKILL (signal 9)
/// bypasses traps and leaves the lock dir dangling. Every subsequent
/// invocation then deadlocks inside `while ! mkdir "$LOCK_DIR"` waiting for
/// the dead owner.
///
/// The PID-aware staleness check fixes this: each successful acquisition
/// writes the owner's PID to `<LOCK_DIR>/pid`, and an `mkdir` failure
/// inspects that PID via `kill -0` to detect a dead owner and reclaim the
/// lock.
void main() {
  group('bin_fsa.sh.stub staleness check condition 4', () {
    test(
        'condition 4 compares pubspec.yaml against STAMP_FILE, not pubspec.lock',
        () {
      // Regression guard: a prior shape compared pubspec.yaml -nt pubspec.lock
      // to detect "user edited pubspec.yaml without running pub get". In
      // practice, `dart pub add` updates pubspec.yaml AFTER pub get writes
      // pubspec.lock, leaving pubspec.yaml mtime newer than pubspec.lock for
      // every freshly installed consumer. That tripped the check on every
      // invocation, forcing a ~5s AOT rebuild every time (the wrapper's
      // ~50ms cached-bundle target was never met after initial install).
      //
      // Correct semantic: rebuild when pubspec.yaml was modified SINCE the
      // last successful build (stamp write), not relative to pubspec.lock.
      final stub = StubLoader.load('bin_fsa.sh');

      expect(
        stub,
        contains(r'"$PROJECT_ROOT/pubspec.yaml" -nt "$STAMP_FILE"'),
        reason: 'staleness check must compare pubspec.yaml mtime against '
            'STAMP_FILE so normal pub-add workflows do not force a rebuild',
      );
      expect(
        stub,
        isNot(contains(
            r'"$PROJECT_ROOT/pubspec.yaml" -nt "$PROJECT_ROOT/pubspec.lock"')),
        reason: 'pre-fix shape compared against pubspec.lock and tripped on '
            'every freshly-installed consumer',
      );
    });
  });

  group('bin_fsa.sh.stub staleness check condition 5', () {
    test(
        'condition 5 compares lib/app/_plugins.g.dart against STAMP_FILE so '
        'plugin install invalidates the AOT bundle',
        () {
      // Regression guard for issue #9 GAP A: when plugin:install or
      // plugins:refresh regenerates lib/app/_plugins.g.dart, the bin/fsa
      // staleness check must detect the mtime drift and invalidate the
      // cached AOT bundle so the next invocation rebuilds with the new
      // plugin providers. Without this condition, newly installed plugins
      // silently fail to surface in the tool list (the stale AOT still
      // references the old provider set).
      final stub = StubLoader.load('bin_fsa.sh');

      expect(
        stub,
        contains(r'"$PROJECT_ROOT/lib/app/_plugins.g.dart" -nt "$STAMP_FILE"'),
        reason: 'condition 5 must invalidate the AOT bundle when '
            'plugin:install regenerates lib/app/_plugins.g.dart',
      );
      expect(
        stub,
        isNot(contains(
            r'"$PROJECT_ROOT/lib/app/_plugins.g.dart" -nt "$PROJECT_ROOT/pubspec.lock"')),
        reason: 'the comparison target must be STAMP_FILE, mirroring the '
            'condition-4 fix shape',
      );
    });
  });

  group('bin_fsa.sh.stub PID-aware lock recovery', () {
    test('stub source contains kill -0 staleness probe', () {
      // The defining marker of the PID-aware recovery is the `kill -0`
      // liveness check applied to a PID stored inside the lock dir.
      final stub = StubLoader.load('bin_fsa.sh');
      expect(
        stub,
        contains('kill -0'),
        reason: 'lock acquisition must probe the stored PID for liveness',
      );
      expect(
        stub,
        contains('LOCK_DIR/pid'),
        reason: 'lock acquisition must persist the owner PID inside the '
            'lock dir for future invocations to inspect',
      );
    });

    test('stub passes `sh -n` syntax validation', () async {
      // Render the stub to a temp file and run `sh -n` against it. POSIX-sh
      // compatibility is part of the fast-CLI contract.
      final tempDir = Directory.systemTemp.createTempSync('fsa_stub_syn_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final stubPath = p.join(tempDir.path, 'fsa');
      File(stubPath).writeAsStringSync(StubLoader.load('bin_fsa.sh'));

      final result = await Process.run('sh', ['-n', stubPath]);
      expect(
        result.exitCode,
        0,
        reason: 'sh -n must accept the stub. stderr: ${result.stderr}',
      );
    });

    test('stale lock with dead PID is reclaimed without deadlock', () async {
      // 1. Build a minimal driver script that inlines just the lock
      //    acquisition loop from the stub (extracted via the
      //    `acquire_lock` function the production stub defines). Driving
      //    the full stub would also fire `dart build cli`; we only need
      //    to validate the lock semantics.
      final tempDir = Directory.systemTemp.createTempSync('fsa_lock_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final lockDir = p.join(tempDir.path, '.fsa.lock');
      Directory(lockDir).createSync(recursive: true);
      // A dead PID: 32-bit max minus one, far above any real Unix PID.
      File(p.join(lockDir, 'pid')).writeAsStringSync('99999999\n');

      // 2. Extract the lock-acquisition function from the stub. Top-level
      //    stub code reads `$0`, computes pubspec.lock hash, and execs the
      //    AOT binary, none of which apply here; we only need the function
      //    body to exercise the PID-aware staleness logic.
      final stubSource = StubLoader.load('bin_fsa.sh');
      final fnMatch = RegExp(
        r'(acquire_lock\(\)\s*\{[\s\S]*?\n\})',
        multiLine: true,
      ).firstMatch(stubSource);
      expect(
        fnMatch,
        isNotNull,
        reason: 'stub must define acquire_lock() as an extractable function',
      );
      final fnSource = fnMatch!.group(1)!;

      final driver = '''
LOCK_DIR="$lockDir"
$fnSource
acquire_lock
echo "ACQUIRED"
rm -rf "\$LOCK_DIR"
''';

      final driverPath = p.join(tempDir.path, 'driver.sh');
      File(driverPath).writeAsStringSync(driver);

      // 3. Run with a hard timeout. A deadlocked loop would block forever;
      //    the PID-aware probe must reclaim within milliseconds.
      final proc = await Process.start('sh', [driverPath]);
      final stdoutBuf = <String>[];
      proc.stdout.transform(SystemEncoding().decoder).listen(stdoutBuf.add);

      final exitFuture = proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      final code = await exitFuture;
      expect(
        code,
        0,
        reason: 'acquire_lock with stale PID must succeed without deadlock; '
            'stdout: ${stdoutBuf.join()}',
      );
      expect(stdoutBuf.join(), contains('ACQUIRED'));
    });
  });
}
