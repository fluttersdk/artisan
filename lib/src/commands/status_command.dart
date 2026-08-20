import 'dart:convert';
import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../console/process_alive.dart';
import '../state/state_file.dart';

/// Prints JSON status of the recorded flutter app + liveness check.
class StatusCommand extends ArtisanCommand {
  @override
  String get name => 'status';

  @override
  String get description => 'Print JSON status of the recorded flutter app.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final state = await StateFile.read();
    if (state == null) {
      ctx.output.writeln(jsonEncode({'running': false}));
      return 0;
    }
    final pid = state['pid'] as int?;
    final alive = pid != null && processAlive(pid);

    // `status` reads rather than acts, so it reports a foreign session
    // instead of refusing it. But it must not report one as THIS project's:
    // an agent that reads `running: true` from a checkout with nothing up
    // would conclude its own app is live and act on that.
    final String? foreign = sessionOwnershipError(
      state: state,
      workingDirectory: Directory.current.path,
      explicitStatePath: StateFile.explicitPath(),
    );

    ctx.output.writeln(
      jsonEncode({
        'running': true,
        'pid': pid,
        'alive': alive,
        'vmServiceUri': state['vmServiceUri'],
        'webPort': state['webPort'],
        'startedAt': state['startedAt'],
        'device': state['device'],
        'projectRoot': state['projectRoot'],
        'ownedByThisProject': foreign == null,
      }),
    );
    if (foreign != null) ctx.output.warning(foreign);
    return 0;
  }
}
