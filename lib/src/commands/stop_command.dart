import 'dart:io';

import 'package:meta/meta.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';
import 'helpers/process_group_reaper.dart';
import 'start_command.dart';

/// Stops the recorded `flutter run` and returns only once it is gone.
///
/// The flutter tool's whole process group is SIGTERMed (so `frontend_server`
/// and the other children go with it rather than being orphaned), waited on
/// for [stopGracePeriod], then SIGKILLed and waited on again; a browser
/// session's web port is waited on too. The FIFO and the session are deleted
/// afterwards. When `chromePid` is present in state, Chrome is reaped the
/// same way, its CDP port waited on, and the `tmpProfileDir` deleted. An app
/// that outlives SIGKILL keeps its session and fails the command, so
/// `restart` never starts on top of it. Idempotent (silent if state.json
/// absent).
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

  /// How long each wait of a reap may last: for the process group after
  /// SIGTERM, after SIGKILL, and for its ports. Defaults to 5 s; a reap
  /// returns as soon as everything is gone, so this bounds only a stuck app.
  @visibleForTesting
  static Duration stopGracePeriod = const Duration(seconds: 5);

  /// Runs a host command (`adb`). Argv list, no shell, so a serial or an
  /// application id read from disk is never interpreted.
  @visibleForTesting
  static Future<ProcessResult> Function(String, List<String>)
      stopProcessRunner = Process.run;

  /// Answers whether a port is free to bind; `stop` waits on the web port of
  /// a browser session and on the CDP port. Defaults to
  /// [StartCommand.defaultPortProbe], the probe `start` refuses a busy port
  /// with, so `stop` waits for exactly what the next `start` checks.
  @visibleForTesting
  static Future<bool> Function(int port) stopPortProbe =
      StartCommand.defaultPortProbe;

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

    // 1. flutter run and its whole process group (frontend_server, the web
    //    server, device helpers), waited on so a `start` straight after this
    //    one does not race a port the old tool still holds.
    final pid = state['pid'] as int?;
    final ReapResult? app =
        pid == null ? null : await _reapApp(ctx, pid, state);

    // 2. FIFO stdin holder (the `tail -f /dev/null > fifo` background process
    //    that keeps the pipe's write end open across reload/hot-restart calls).
    //    It shares the tool's group, so this only matters when the group could
    //    not be signalled.
    final holderPid = state['stdinHolderPid'] as int?;
    if (holderPid != null) {
      try {
        stopKillFunction(holderPid, ProcessSignal.sigterm);
      } catch (_) {
        // Holder may already be gone; safe to ignore.
      }
    }

    // 3. Named pipe file. Safe to delete even when readers/writers are
    //    still attached; POSIX unlinks the inode, fds stay valid until
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
      await _reapChrome(
        ctx,
        chromePid,
        state['tmpProfileDir'] as String?,
        state['cdpPort'] as int?,
        _startedAt(state),
      );
    }

    // 5. Android app. Signalling the flutter tool detaches it from the device
    //    without stopping the app, so a profile run's next cold start would
    //    find the previous process still resident.
    final device = state['device'] as String?;
    if (device != null && isAndroidSerial(device)) {
      await _forceStopAndroidApp(ctx, device, state['projectRoot'] as String?);
    }

    // 6. Keep the session when the app outlived SIGKILL: deleting it would
    //    leave a live app nothing can find, and `restart` would start on top.
    if (app?.outcome == ReapOutcome.survived) {
      ctx.output.error(
        'flutter run pid=$pid is still alive after SIGKILL; the session is '
        'kept so `stop` can be run again.',
      );
      return 1;
    }

    await StateFile.delete();
    ctx.output.success('state.json removed.');
    return 0;
  }

  /// The reaper `stop` runs with its own seams, so a test drives both the
  /// flutter tool and Chrome through the same fakes.
  ProcessGroupReaper _reaper() {
    return ProcessGroupReaper(
      kill: stopKillFunction,
      run: stopProcessRunner,
      isAlive: (int pid) async => stopIsAlive(pid),
      isPortFree: stopPortProbe,
      grace: stopGracePeriod,
    );
  }

  /// Reaps the flutter tool's process group and reports how it ended. The web
  /// port is waited on for a browser session only: on a device target the
  /// recorded `webPort` is a default the tool never bound.
  ///
  /// The group is found through the tool pid, or through the FIFO holder in
  /// the same group when the tool is gone and a child of it may not be.
  Future<ReapResult> _reapApp(
    ArtisanContext ctx,
    int pid,
    Map<String, dynamic> state,
  ) async {
    final int? webPort = state['webPort'] as int?;
    final int? holderPid = state['stdinHolderPid'] as int?;
    final bool browser = StartCommand.browserDevices.contains(state['device']);
    final int anchor =
        holderPid != null && !stopIsAlive(pid) && stopIsAlive(holderPid)
            ? holderPid
            : pid;
    final ReapResult result = await _reaper().reap(
      anchor,
      ports: <int>[
        if (browser && webPort != null) webPort,
      ],
      startedBy: _startedAt(state),
    );

    if (result.pidReused) {
      ctx.output.warning(
        'pid=$anchor belongs to a process started after this session was '
        'recorded; the app is gone and that process was left alone.',
      );
      return result;
    }
    final String target = result.pgid == null
        ? 'pid=$anchor'
        : 'process group ${result.pgid} (flutter run pid=$pid)';
    if (result.termDelivered) {
      ctx.output.success('Sent SIGTERM to $target.');
    } else {
      ctx.output.warning('SIGTERM to $target reached no process.');
    }
    if (result.outcome == ReapOutcome.killed) {
      ctx.output.warning(
        'flutter run ignored SIGTERM for ${stopGracePeriod.inSeconds}s; sent '
        'SIGKILL to $target.',
      );
    }
    _warnBoundPorts(ctx, result);
    return result;
  }

  /// When the session was recorded, which every process it names started
  /// before. Null for a hand-written session without `startedAt`, which the
  /// reaper then takes on trust.
  DateTime? _startedAt(Map<String, dynamic> state) {
    final Object? raw = state['startedAt'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  void _warnBoundPorts(ArtisanContext ctx, ReapResult result) {
    for (final int port in result.boundPorts) {
      ctx.output.warning(
        'Port $port is still bound; a `start` on it fails until it is freed.',
      );
    }
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

  /// Reaps Chrome's process group (its renderer and GPU helpers share it,
  /// since `start` spawns Chrome detached too), waits for [cdpPort] to come
  /// free, then deletes [tmpProfileDir] when non-null and present on disk.
  ///
  /// A Chrome that survives is a warning, not a failure: the session belongs
  /// to the flutter tool, and a stray Chrome costs a port, not correctness.
  Future<void> _reapChrome(
    ArtisanContext ctx,
    int chromePid,
    String? tmpProfileDir,
    int? cdpPort,
    DateTime? startedBy,
  ) async {
    // 1. SIGTERM, wait, SIGKILL, wait: the port is what a restart on the same
    //    --cdp-port probes before it launches a new Chrome.
    final ReapResult result = await _reaper().reap(
      chromePid,
      ports: <int>[
        if (cdpPort != null) cdpPort,
      ],
      startedBy: startedBy,
    );
    if (result.pidReused) {
      ctx.output.warning(
        'Chrome pid=$chromePid belongs to a process started after this '
        'session was recorded; it was left alone.',
      );
    } else if (result.termDelivered) {
      ctx.output.success('Chrome SIGTERM sent to pid=$chromePid.');
    } else {
      ctx.output.warning(
        'Chrome SIGTERM not delivered to pid=$chromePid (process '
        'may already be gone).',
      );
    }
    if (result.outcome == ReapOutcome.survived) {
      ctx.output.warning('Chrome pid=$chromePid is still alive after SIGKILL.');
    }
    _warnBoundPorts(ctx, result);

    // 2. Best-effort delete of the tmp profile dir. Missing directories and
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
