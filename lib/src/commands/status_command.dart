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
        // Present when `start` was cut short between spawning the app and
        // scraping its VM Service URI. The app is up and drivable through
        // the FIFO, but connected commands have nothing to dial yet.
        if (state['booting'] == true) 'booting': true,
      }),
    );
    if (state['booting'] == true) {
      ctx.output.warning(
        'The app is running but its start did not finish recording: no '
        'vmServiceUri yet. Connected commands recover it from the session '
        'log on their next call, or re-run `artisan start`.',
      );
    }
    if (foreign != null) ctx.output.warning(foreign);
    return 0;
  }
}
