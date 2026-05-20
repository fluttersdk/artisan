import 'dart:io';

import 'package:meta/meta.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';

/// SIGTERMs the recorded `flutter run` PID + the FIFO stdin holder PID,
/// deletes the FIFO + state.json. When `chromePid` is present in state,
/// also delivers SIGTERM (with SIGKILL escalation) to that Chrome process
/// and deletes the `tmpProfileDir`. Idempotent (silent if state.json absent).
class StopCommand extends ArtisanCommand {
  // ---------------------------------------------------------------------------
  // Test seams for Chrome cleanup. Replaced in tests to avoid spawning real
  // processes or waiting two seconds during unit runs.
  // ---------------------------------------------------------------------------

  /// Sends a signal to the given PID. Defaults to [Process.killPid].
  @visibleForTesting
  static bool Function(int, ProcessSignal) stopKillFunction = Process.killPid;

  /// Returns true when the process [pid] is still alive.
  ///
  /// Default implementation runs `ps -p <pid>` and checks the exit code.
  @visibleForTesting
  static bool Function(int) stopIsAlive = defaultIsAlive;

  /// Grace period between SIGTERM and the liveness probe. Defaults to 2 s.
  @visibleForTesting
  static Duration stopGracePeriod = const Duration(seconds: 2);

  /// Default liveness probe: exits 0 when the process exists on POSIX.
  @visibleForTesting
  static bool defaultIsAlive(int pid) {
    try {
      final result = Process.runSync('ps', ['-p', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  String get name => 'stop';

  @override
  String get description =>
      'Stop the running flutter app + delete ~/.artisan/state.json.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final state = await StateFile.read();
    if (state == null) {
      ctx.output.writeln('No state file; nothing to stop.');
      return 0;
    }

    // 1. flutter run process.
    final pid = state['pid'] as int?;
    if (pid != null) {
      try {
        stopKillFunction(pid, ProcessSignal.sigterm);
        ctx.output.success('Sent SIGTERM to pid=$pid.');
      } catch (e) {
        ctx.output.warning('SIGTERM failed: $e (continuing).');
      }
    }

    // 2. FIFO stdin holder (the `sleep infinity > fifo` background process
    //    that keeps the pipe's write end open across reload/hot-restart calls).
    final holderPid = state['stdinHolderPid'] as int?;
    if (holderPid != null) {
      try {
        stopKillFunction(holderPid, ProcessSignal.sigterm);
      } catch (_) {
        // Holder may already be gone; safe to ignore.
      }
    }

    // 3. Named pipe file. Safe to delete even when readers/writers are
    //    still attached — POSIX unlinks the inode, fds stay valid until
    //    closed naturally.
    final pipePath = state['stdinPipe'] as String?;
    if (pipePath != null) {
      try {
        final pipe = File(pipePath);
        if (pipe.existsSync()) await pipe.delete();
      } catch (_) {
        // Best-effort cleanup; don't block stop on FIFO removal failure.
      }
    }

    // 4. Chrome process + tmp profile dir (CDP mode only; absent in non-CDP
    //    runs). Mirrors the SIGTERM-grace-SIGKILL-rm pattern from
    //    fluttersdk_dusk/lib/src/utils/chrome_reaper.dart without importing
    //    that package (no cross-package dep on a downstream plugin).
    final chromePid = state['chromePid'] as int?;
    if (chromePid != null) {
      await _reapChrome(ctx, chromePid, state['tmpProfileDir'] as String?);
    }

    await StateFile.delete();
    ctx.output.success('state.json removed.');
    return 0;
  }

  /// Delivers SIGTERM to [chromePid], waits [stopGracePeriod], escalates to
  /// SIGKILL when the liveness probe says the process is still alive, then
  /// deletes [tmpProfileDir] when non-null and present on disk.
  ///
  /// All failures are swallowed: a failed kill or a missing profile dir must
  /// never surface to the operator as an error; worst case the operator
  /// cleans up manually.
  Future<void> _reapChrome(
    ArtisanContext ctx,
    int chromePid,
    String? tmpProfileDir,
  ) async {
    // 1. Deliver SIGTERM. Continue even on failure; liveness probe decides
    //    whether to escalate.
    try {
      stopKillFunction(chromePid, ProcessSignal.sigterm);
      ctx.output.success('Chrome SIGTERM sent to pid=$chromePid.');
    } catch (_) {
      // Non-fatal; the probe below drives escalation.
    }

    // 2. Wait the grace period so Chrome can flush and exit cleanly.
    await Future<void>.delayed(stopGracePeriod);

    // 3. Liveness probe. If the probe throws, assume dead (safe-fail).
    bool stillAlive;
    try {
      stillAlive = stopIsAlive(chromePid);
    } catch (_) {
      stillAlive = false;
    }

    // 4. Escalate to SIGKILL when the probe reports alive. Failures are
    //    swallowed; the dual-signal cascade is best-effort.
    if (stillAlive) {
      try {
        stopKillFunction(chromePid, ProcessSignal.sigkill);
      } catch (_) {
        // Nothing actionable.
      }
    }

    // 5. Best-effort delete of the tmp profile dir. Missing directories and
    //    permission errors are non-fatal.
    if (tmpProfileDir != null && tmpProfileDir.isNotEmpty) {
      try {
        final dir = Directory(tmpProfileDir);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
          ctx.output.success('tmpProfileDir $tmpProfileDir cleaned.');
        }
      } catch (_) {
        // Swallow: a stale profile directory is not worth stopping for.
      }
    }
  }
}
