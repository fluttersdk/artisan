import 'package:fluttersdk_artisan/artisan.dart';

/// Edit the [signature] to add arguments, flags, and options. Examples:
///
/// ```dart
/// String get signature => 'awesome_plugin:greet {target}';                 // required positional
/// String get signature => 'awesome_plugin:greet {target?}';                // optional positional
/// String get signature => 'awesome_plugin:greet {target=acme}';            // positional with default
/// String get signature => 'awesome_plugin:greet {--force}';                // boolean flag
/// String get signature => 'awesome_plugin:greet {--limit=10}';             // option with default
/// String get signature => 'awesome_plugin:greet {target : Team slug} {--force : Skip prompts}';
/// ```
///
/// Read with: `ctx.input.argument('target')`, `ctx.input.option('force') as bool`,
///            `ctx.input.option('limit') as String`.
class GreetCommand extends ArtisanCommand {
  @override
  String get signature => 'awesome_plugin:greet';

  @override
  String get description => 'TODO: describe what this command does.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.success('Hello from awesome_plugin:greet');
    return 0;
  }
}
