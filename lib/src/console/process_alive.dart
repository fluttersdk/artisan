import 'dart:io';

/// Returns `true` when a process with the supplied PID is currently alive.
///
/// POSIX path uses `kill -0 <pid>` — the kernel only checks the process
/// table without delivering a signal; exit 0 means alive, exit 1 means
/// gone (or unowned).
///
/// Windows path uses `tasklist /FI "PID eq <pid>"` and matches the PID
/// string in stdout.
///
/// Used by `StatusCommand` to differentiate `running:true alive:true`
/// (process registered AND visible to the kernel) from `running:true
/// alive:false` (state file recorded a PID that has since died — stale
/// session). Public so tests can assert against the current process and
/// against intentionally-impossible PIDs.
bool processAlive(int pid) {
  if (Platform.isWindows) {
    final result = Process.runSync('tasklist', <String>[
      '/FI',
      'PID eq $pid',
    ]);
    return result.exitCode == 0 && result.stdout.toString().contains('$pid');
  }
  final result = Process.runSync('kill', <String>['-0', '$pid']);
  return result.exitCode == 0;
}
