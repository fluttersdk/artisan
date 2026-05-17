import 'package:fluttersdk_artisan/artisan.dart';

/// Simplest signature: just a command name, no arguments, no options.
/// `artisan cache:clean` → runs handle().
class CleanCacheCommand extends ArtisanCommand {
  @override
  String get signature => 'cache:clean';

  @override
  String get description => 'Clear the in-memory cache stores.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.success('Cache cleared.');
    return 0;
  }
}
