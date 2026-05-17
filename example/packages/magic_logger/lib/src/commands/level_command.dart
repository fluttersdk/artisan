import 'package:fluttersdk_artisan/artisan.dart';

import '../runtime/magic_logger.dart';

/// `logger:level <new-level>` — show or change the minimum log level
/// at runtime. Without an argument, prints the current level.
class LoggerLevelCommand extends ArtisanCommand {
  @override
  String get signature =>
      'logger:level '
      '{level? : New minimum level (debug|info|warn|error). Omit to read the current level}';

  @override
  String get description => 'Show or update the magic_logger minimum level.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final target = ctx.input.argument('level');
    if (target == null || target.isEmpty) {
      ctx.output.info('Current level: ${MagicLogger.minLevel.name}');
      return 0;
    }
    try {
      MagicLogger.minLevel = LogLevel.parse(target);
      ctx.output.success('Level set to ${MagicLogger.minLevel.name}.');
      return 0;
    } on ArgumentError catch (e) {
      ctx.output.error(e.message.toString());
      return 1;
    }
  }
}
