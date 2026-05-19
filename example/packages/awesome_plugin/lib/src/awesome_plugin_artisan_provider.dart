import 'package:fluttersdk_artisan/artisan.dart';
import 'commands/greet_command.dart';

/// ArtisanServiceProvider for awesome_plugin.
///
/// Plugin commands live in `lib/src/commands/`. Use `dart run magic:artisan
/// make:command Name` from inside the plugin directory to scaffold a new
/// command. The generator writes the command file under `lib/src/commands/`
/// AND auto-registers it in the [commands] list below (idempotent), so the
/// command surfaces immediately when the host runs `plugin:install awesome_plugin`.
class AwesomePluginArtisanProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        GreetCommand(),
        // Commands added via `make:command` land here automatically.
      ];
}
