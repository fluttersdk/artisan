import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';
import 'start_command.dart';
import 'stop_command.dart';

/// Composes stop + start atomically, preserving the prior CDP port.
///
/// StopCommand deletes state.json, so the [cdpPort] from the previous session
/// would be lost before StartCommand runs. RestartCommand reads the prior state
/// BEFORE stopping, captures [cdpPort], then forwards it into StartCommand.
/// An explicit [--cdp-port] flag on [ctx] always wins over the forwarded value.
class RestartCommand extends ArtisanCommand {
  @override
  String get name => 'restart';

  @override
  String get description => 'Stop + start the running flutter app.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Read the prior state BEFORE stop deletes it so we can forward cdpPort.
    final priorState = await StateFile.read();
    final priorCdpPort = priorState?['cdpPort'] as int?;

    // 2. Stop the running app (deletes state.json).
    await StopCommand().handle(ctx);

    // 3. Start again, forwarding the prior CDP port so restart is transparent.
    //    An explicit --cdp-port flag on ctx overrides the forwarded value inside
    //    StartCommand.handle (flag-wins rule).
    return StartCommand().handle(ctx, cdpPort: priorCdpPort);
  }
}
