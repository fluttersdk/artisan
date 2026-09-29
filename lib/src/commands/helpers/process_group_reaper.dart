import 'dart:io' as io;

/// Delivers [signal] to [pid]; a negative [pid] addresses the process group
/// `-pid`, as `kill(2)` does. Mirrors [io.Process.killPid].
typedef ReaperKill = bool Function(int pid, io.ProcessSignal signal);

/// Runs a host command (`ps`) as an argv list, never through a shell.
typedef ReaperRunner = Future<io.ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// How the processes of a reap ended.
enum ReapOutcome {
  /// Gone within the grace period after SIGTERM, or already gone.
  exited,

  /// Ignored SIGTERM for the grace period and was gone after SIGKILL.
  killed,

  /// Still alive when the budget after SIGKILL ran out.
  survived,

  /// The process listing could not run, so only the pid was SIGTERMed and
  /// nothing was waited on: its children and its exit are unknown.
  unverified,
}

/// What [ProcessGroupReaper.reap] did, and what it left behind.
final class ReapResult {
  const ReapResult({
    required this.outcome,
    required this.pgid,
    required this.termDelivered,
    this.boundPorts = const <int>[],
    this.pidReused = false,
    this.listingError,
  });

  final ReapOutcome outcome;

  /// The process group that was signalled, or null when only the pid was:
  /// the pid was already gone, or it shared the caller's own group.
  final int? pgid;

  /// Whether the SIGTERM reached at least one process. False means the target
  /// was gone before the reap started.
  final bool termDelivered;

  /// The requested ports still bound when the budget ran out. The processes
  /// can be gone while a port is not: something outside the group holds it.
  final List<int> boundPorts;

  /// Whether the pid belonged to a process started after the session was
  /// recorded, so it was left alone: the recorded process is gone and its
  /// number was handed to something else.
  final bool pidReused;

  /// Why the outcome is [ReapOutcome.unverified]: the [io.ProcessException]
  /// of a host without `ps`, or the [FormatException] of an elapsed time it
  /// printed in an unknown shape. Null otherwise.
  final Object? listingError;
}

/// Stops a detached process together with everything it spawned, and waits,
/// within a bound, until they are gone.
///
/// `start` spawns `flutter run` through Dart's detached mode, which forks,
/// calls `setsid()` and forks again, so the flutter tool, its FIFO holder and
/// every child the tool starts (`frontend_server`, the web server, `adb` or
/// `iproxy` helpers) share one process group that is not the caller's. A
/// SIGTERM to the tool pid alone ends the tool and orphans the children to
/// pid 1, where they keep compiling; a return straight after the signal lets
/// the next `start` race a port the old tool still holds.
///
/// The group id is read from the live pid (`ps -o pgid=`) rather than stored:
/// once every member is gone the number is free for reuse, and a recorded id
/// from a stale session could name somebody else's group. The pid itself can
/// be reused too, so a caller holding a stale one passes the time its session
/// was recorded and a pid that started later is left alone. Zombies do not
/// count as live members, and a process listing that fails reads as alive,
/// never as gone; a listing that cannot run at all degrades the reap to the
/// pid alone. POSIX only (BSD and procps `ps`), like the FIFO the
/// lifecycle commands already depend on.
final class ProcessGroupReaper {
  /// [grace] bounds each wait: after SIGTERM, after SIGKILL, and for the
  /// ports once the processes are gone, so a reap returns within three times
  /// [grace] at worst. Without [isAlive] a pid is probed with `ps -o stat=`;
  /// without [isPortFree] ports are not waited on.
  /// [selfPid] is the caller's pid, whose group is never signalled.
  ProcessGroupReaper({
    required ReaperKill kill,
    required ReaperRunner run,
    Future<bool> Function(int pid)? isAlive,
    Future<bool> Function(int port)? isPortFree,
    this.grace = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 100),
    int? selfPid,
  })  : _kill = kill,
        _run = run,
        _isAlive = isAlive,
        _isPortFree = isPortFree,
        _selfPid = selfPid ?? io.pid;

  final ReaperKill _kill;
  final ReaperRunner _run;
  final Future<bool> Function(int pid)? _isAlive;
  final Future<bool> Function(int port)? _isPortFree;
  final int _selfPid;

  /// How long each wait, after SIGTERM and after SIGKILL, may last.
  final Duration grace;

  /// The pause between two liveness checks within a wait.
  final Duration pollInterval;

  /// SIGTERMs the process group of [pid] (the pid alone when it has no group
  /// of its own) and waits up to [grace] for every member to exit; SIGKILLs
  /// the group when a member is left and waits up to [grace] again; then
  /// waits up to [grace] for every one of [ports] to come free. A port that
  /// stays bound never triggers SIGKILL: once the group is gone, whatever
  /// holds it is not ours.
  ///
  /// [startedBy] is when the session holding [pid] was recorded. A pid whose
  /// process started later is a reused number and is not signalled at all.
  /// A pid of 1 or below never is either.
  ///
  /// Returns as soon as everything is gone, or when the budget is spent; the
  /// [ReapResult] says which. When `ps` cannot run, or prints an elapsed time
  /// it cannot read, the reap falls back to a SIGTERM to [pid] alone, the
  /// pre-group behaviour, and reports [ReapOutcome.unverified] so the caller
  /// can say so: a `stop` that throws leaves a session it can never delete.
  /// An unreadable elapsed time means the [startedBy] reuse check could not
  /// run, so that fallback SIGTERMs a pid it could not identify. That is a
  /// deliberate trade: one SIGTERM to one pid, never a group and never
  /// SIGKILL, is what `stop` sent before the check existed.
  Future<ReapResult> reap(
    int pid, {
    List<int> ports = const <int>[],
    DateTime? startedBy,
  }) async {
    try {
      return await _reapGroup(pid, ports: ports, startedBy: startedBy);
    } on io.ProcessException catch (error) {
      return _reapPidOnly(pid, ports, error);
    } on FormatException catch (error) {
      return _reapPidOnly(pid, ports, error);
    }
  }

  Future<ReapResult> _reapPidOnly(
    int pid,
    List<int> ports,
    Object error,
  ) async {
    return ReapResult(
      outcome: ReapOutcome.unverified,
      pgid: null,
      termDelivered: _kill(pid, io.ProcessSignal.sigterm),
      boundPorts: await _waitForPorts(ports),
      listingError: error,
    );
  }

  Future<ReapResult> _reapGroup(
    int pid, {
    required List<int> ports,
    required DateTime? startedBy,
  }) async {
    // 1. Nothing at or below pid 1 is ours: `kill(0)` addresses the caller's
    //    own group and `kill(-1)` every process it may signal.
    if (pid <= 1) {
      return const ReapResult(
        outcome: ReapOutcome.exited,
        pgid: null,
        termDelivered: false,
      );
    }

    // 2. A stale session's pid may now belong to anything; its group would be
    //    SIGKILLed along with it.
    if (startedBy != null && await _startedAfter(pid, startedBy)) {
      return const ReapResult(
        outcome: ReapOutcome.exited,
        pgid: null,
        termDelivered: false,
        pidReused: true,
      );
    }

    // 3. Resolve the group while the pid is alive: once it exits, it has none.
    final int? pgid = await _signallableGroup(pid);
    final int target = pgid == null ? pid : -pgid;

    // 4. SIGTERM, so the flutter tool can run its own shutdown first.
    final bool delivered = _kill(target, io.ProcessSignal.sigterm);
    if (await _settle(pid, pgid)) {
      return ReapResult(
        outcome: ReapOutcome.exited,
        pgid: pgid,
        termDelivered: delivered,
        boundPorts: await _waitForPorts(ports),
      );
    }

    // 5. SIGKILL the whole group. Killing only the pid would orphan the
    //    children exactly as a bare SIGTERM did.
    _kill(target, io.ProcessSignal.sigkill);
    final bool gone = await _settle(pid, pgid);
    return ReapResult(
      outcome: gone ? ReapOutcome.killed : ReapOutcome.survived,
      pgid: pgid,
      termDelivered: delivered,
      boundPorts: await _waitForPorts(ports),
    );
  }

  /// Whether [pid] started after [instant]. `etime` rather than `lstart`,
  /// because it is the same `[[dd-]hh:]mm:ss` on BSD and procps and carries
  /// no time zone. It has a one second resolution, hence the slack.
  Future<bool> _startedAfter(int pid, DateTime instant) async {
    final io.ProcessResult result = await _run('ps', <String>[
      '-o',
      'etime=',
      '-p',
      '$pid',
    ]);
    // Gone: the signal that follows reaches nothing.
    if (result.exitCode != 0) return false;
    final DateTime started = DateTime.now().subtract(
      _parseElapsed((result.stdout as String).trim()),
    );
    return started.isAfter(instant.add(const Duration(seconds: 2)));
  }

  /// Parses `ps -o etime=` output, `[[dd-]hh:]mm:ss`.
  static Duration _parseElapsed(String etime) {
    final RegExpMatch? match =
        RegExp(r'^(?:(?:(\d+)-)?(\d+):)?(\d+):(\d+)$').firstMatch(etime);
    if (match == null) {
      throw FormatException('Unreadable `ps -o etime=` output', etime);
    }
    int field(int group) => int.parse(match.group(group) ?? '0');
    return Duration(
      days: field(1),
      hours: field(2),
      minutes: field(3),
      seconds: field(4),
    );
  }

  /// The group of [pid], or null when the pid is gone or shares the caller's
  /// group, where a group signal would take the caller down too.
  Future<int?> _signallableGroup(int pid) async {
    final int? pgid = await _groupOf(pid);
    if (pgid == null || pgid <= 1) return null;
    if (pgid == await _groupOf(_selfPid)) return null;
    return pgid;
  }

  Future<int?> _groupOf(int pid) async {
    final io.ProcessResult result = await _run('ps', <String>[
      '-o',
      'pgid=',
      '-p',
      '$pid',
    ]);
    if (result.exitCode != 0) return null;
    return int.tryParse((result.stdout as String).trim());
  }

  /// Polls until the group (or the bare pid) is gone, up to [grace].
  Future<bool> _settle(int pid, int? pgid) async {
    return _poll(() async {
      if (pgid != null) return !await _groupAlive(pgid);
      return !await _pidAlive(pid);
    });
  }

  /// Polls until every port in [ports] is free, up to [grace], and returns
  /// the ones that are not.
  Future<List<int>> _waitForPorts(List<int> ports) async {
    final Future<bool> Function(int port)? isPortFree = _isPortFree;
    if (ports.isEmpty || isPortFree == null) return const <int>[];
    List<int> bound = ports;
    await _poll(() async {
      bound = <int>[
        for (final int port in bound)
          if (!await isPortFree(port)) port,
      ];
      return bound.isEmpty;
    });
    return bound;
  }

  /// Runs [done] until it answers true or [grace] has passed; always at least
  /// once, so a zero grace still reports the current state.
  Future<bool> _poll(Future<bool> Function() done) async {
    final Stopwatch clock = Stopwatch()..start();
    while (true) {
      if (await done()) return true;
      if (clock.elapsed >= grace) return false;
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Whether any member of [pgid] is alive. A zombie is not: under a pid 1
  /// that reaps nothing (a container entrypoint) it stays listed for good. A
  /// failed listing is: reading it as "gone" would delete a live session.
  Future<bool> _groupAlive(int pgid) async {
    final io.ProcessResult result = await _run('ps', <String>[
      '-A',
      '-o',
      'pgid=,stat=',
    ]);
    if (result.exitCode != 0) return true;
    return (result.stdout as String).split('\n').any((String line) {
      final List<String> fields = line.trim().split(RegExp(r'\s+'));
      return fields.length == 2 &&
          int.tryParse(fields[0]) == pgid &&
          !fields[1].startsWith('Z');
    });
  }

  Future<bool> _pidAlive(int pid) async {
    final Future<bool> Function(int pid)? isAlive = _isAlive;
    if (isAlive != null) return isAlive(pid);
    final io.ProcessResult result = await _run('ps', <String>[
      '-o',
      'stat=',
      '-p',
      '$pid',
    ]);
    return result.exitCode == 0 &&
        !(result.stdout as String).trim().startsWith('Z');
  }
}
