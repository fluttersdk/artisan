import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';

/// SIGTERMs the recorded `flutter run` PID + deletes state.json. Idempotent
/// (silent if state.json absent).
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
    final pid = state['pid'] as int?;
    if (pid != null) {
      try {
        Process.killPid(pid, ProcessSignal.sigterm);
        ctx.output.success('Sent SIGTERM to pid=$pid.');
      } catch (e) {
        ctx.output.warning('SIGTERM failed: $e (continuing).');
      }
    }
    await StateFile.delete();
    ctx.output.success('state.json removed.');
    return 0;
  }
}
