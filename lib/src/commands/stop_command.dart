import 'dart:io';

import 'package:meta/meta.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';
import 'start_command.dart';

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

  /// Runs a host command (`adb`). Argv list, no shell, so a serial or an
  /// application id read from disk is never interpreted.
  @visibleForTesting
  static Future<ProcessResult> Function(String, List<String>)
      stopProcessRunner = Process.run;

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

    // The legacy pointer describes whichever app started last, so without
    // this a stop from a project with nothing up reaches across and kills a
    // sibling's running app, reporting a clean success while doing it.
    final String? ownership = sessionOwnershipError(
      state: state,
      workingDirectory: Directory.current.path,
      explicitStatePath: StateFile.explicitPath(),
    );
    if (ownership != null) {
      ctx.output.error(ownership);
      return 1;
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

    // 5. Android app. Signalling the flutter tool detaches it from the device
    //    without stopping the app, so a profile run's next cold start would
    //    find the previous process still resident.
    final device = state['device'] as String?;
    if (device != null && isAndroidSerial(device)) {
      await _forceStopAndroidApp(ctx, device, state['projectRoot'] as String?);
    }

    await StateFile.delete();
    ctx.output.success('state.json removed.');
    return 0;
  }

  /// True when [device] can be an Android serial: not a web or desktop target
  /// and not an iOS device or simulator id (`<8 hex>-<16 hex>` UDID, a legacy
  /// 40-hex UDID, or a UUID).
  ///
  /// Serials of physical devices have no fixed shape, so the test is by
  /// exclusion; the `applicationId` lookup that follows is what confirms the
  /// project builds for Android at all. A device given by name or partial id
  /// (an iOS simulator named `iPhone 15`) passes too; the cost is one
  /// `adb force-stop ... exited 1` warning, and `stop` still succeeds.
  @visibleForTesting
  static bool isAndroidSerial(String device) {
    const desktop = <String>{'macos', 'linux', 'windows'};
    if (StartCommand.browserDevices.contains(device) ||
        desktop.contains(device)) {
      return false;
    }
    return !_iosDeviceId.hasMatch(device);
  }

  static final RegExp _iosDeviceId = RegExp(
    r'^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40}|'
    r'[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})$',
  );

  /// First `applicationId` in the Android app module's Gradle file (Groovy or
  /// Kotlin DSL) under [projectRoot], or null when there is none.
  ///
  /// The first match is the `defaultConfig` one; `applicationIdSuffix` is not
  /// matched because the quote must follow the key.
  @visibleForTesting
  static String? androidApplicationId(String projectRoot) {
    final pattern = RegExp('applicationId\\s*=?\\s*["\']([^"\']+)["\']');
    for (final file in <String>['build.gradle', 'build.gradle.kts']) {
      final gradle = File('$projectRoot/android/app/$file');
      if (!gradle.existsSync()) continue;
      final match = pattern.firstMatch(gradle.readAsStringSync());
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Runs `adb -s <serial> shell am force-stop <applicationId>`.
  ///
  /// A failure is a warning, never an error: the flutter tool is already
  /// signalled and the session is about to be deleted, so stop has nothing
  /// left to abort. The operator does need to hear that the app may still be
  /// running.
  Future<void> _forceStopAndroidApp(
    ArtisanContext ctx,
    String serial,
    String? projectRoot,
  ) async {
    final applicationId =
        androidApplicationId(projectRoot ?? Directory.current.path);
    if (applicationId == null) {
      ctx.output.warning(
        'No applicationId in android/app/build.gradle*; the app on $serial '
        'was not force-stopped.',
      );
      return;
    }

    try {
      final result = await stopProcessRunner('adb', <String>[
        '-s',
        serial,
        'shell',
        'am',
        'force-stop',
        applicationId,
      ]);
      if (result.exitCode == 0) {
        ctx.output.success('Force-stopped $applicationId on $serial.');
      } else {
        ctx.output.warning(
          'adb force-stop of $applicationId on $serial exited '
                  '${result.exitCode}: ${result.stderr}'
              .trimRight(),
        );
      }
    } on ProcessException catch (e) {
      ctx.output.warning(
        'adb force-stop of $applicationId on $serial failed: ${e.message}',
      );
    }
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
    // 1. Deliver SIGTERM. Process.killPid returns false when the signal
    //    cannot be delivered (process already gone, permission denied);
    //    continue regardless because the liveness probe drives escalation.
    try {
      final delivered = stopKillFunction(chromePid, ProcessSignal.sigterm);
      if (delivered) {
        ctx.output.success('Chrome SIGTERM sent to pid=$chromePid.');
      } else {
        ctx.output.warning(
          'Chrome SIGTERM not delivered to pid=$chromePid (process '
          'may already be gone).',
        );
      }
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
