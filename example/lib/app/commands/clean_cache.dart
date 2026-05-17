import 'package:fluttersdk_artisan/artisan.dart';

class CleanCacheCommand extends ArtisanCommand {
  @override
  String get name => 'CleanCache'; // TODO: choose name, e.g. 'foo:bar'

  @override
  String get description => 'TODO: describe what this command does.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.success('Hello from CleanCacheCommand');
    return 0;
  }
}
