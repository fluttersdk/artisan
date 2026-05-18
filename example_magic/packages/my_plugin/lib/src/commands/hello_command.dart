import 'package:fluttersdk_artisan/artisan.dart';

/// `my_plugin:hello` — demo command that prints a greeting.
///
/// Wired through [MyPluginArtisanProvider.commands] and auto-registered into
/// the host artisan registry via `.artisan/plugins.json`.
class HelloCommand extends ArtisanCommand {
  @override
  String get signature => 'my_plugin:hello '
      '{--name=World : Recipient name shown in the greeting} ';

  @override
  String get description => 'Print a greeting from my_plugin.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final name = ctx.input.option('name') as String? ?? 'World';
    ctx.output.success('Hello, $name! Greetings from my_plugin.');
    return 0;
  }
}
