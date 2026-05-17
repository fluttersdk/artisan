import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import 'start_command.dart';
import 'stop_command.dart';

/// Composes stop + start atomically.
class RestartCommand extends ArtisanCommand {
  @override
  String get name => 'restart';

  @override
  String get description => 'Stop + start the running flutter app.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    await StopCommand().handle(ctx);
    return await StartCommand().handle(ctx);
  }
}
