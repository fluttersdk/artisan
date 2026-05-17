import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';

/// SIGTERMs the recorded `flutter run` PID + the FIFO stdin holder PID,
/// deletes the FIFO + state.json. Idempotent (silent if state.json absent).
class StopCommand extends ArtisanCommand {
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
        Process.killPid(pid, ProcessSignal.sigterm);
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
        Process.killPid(holderPid, ProcessSignal.sigterm);
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

    await StateFile.delete();
    ctx.output.success('state.json removed.');
    return 0;
  }
}
