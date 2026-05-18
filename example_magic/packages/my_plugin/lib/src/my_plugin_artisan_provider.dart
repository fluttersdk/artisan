import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/hello_command.dart';
import 'commands/install_command.dart';
import 'commands/uninstall_command.dart';

/// ArtisanServiceProvider for my_plugin.
///
/// Plugin authors register this in their consumer's `bin/artisan.dart` via
/// `artisan plugin:install my_plugin`. The auto-registration writes both the
/// import line and the `registry.registerProvider(MyPluginArtisanProvider())`
/// call into the consumer wrapper, so no manual wiring is required.
class MyPluginArtisanProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        InstallCommand(),
        UninstallCommand(),
        HelloCommand(),
      ];
}
