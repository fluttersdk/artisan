import 'dart:convert';
import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
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
    final alive = pid != null && _isAlive(pid);
    ctx.output.writeln(
      jsonEncode({
        'running': true,
        'pid': pid,
        'alive': alive,
        'vmServiceUri': state['vmServiceUri'],
        'webPort': state['webPort'],
        'startedAt': state['startedAt'],
        'device': state['device'],
      }),
    );
    return 0;
  }

  static bool _isAlive(int pid) {
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
}
