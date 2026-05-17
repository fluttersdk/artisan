import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/install_command.dart';
import 'commands/level_command.dart';
import 'commands/tail_command.dart';
import 'commands/uninstall_command.dart';

/// Registers the `logger:*` command namespace with the host's artisan
/// dispatcher.
///
/// Host wiring (in `bin/artisan.dart`):
/// ```dart
/// import 'package:magic_logger/cli.dart';
/// // ...
/// registry.registerProvider(MagicLoggerArtisanProvider());
/// ```
class MagicLoggerArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'magic_logger';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
    LoggerInstallCommand(),
    LoggerUninstallCommand(),
    LoggerTailCommand(),
    LoggerLevelCommand(),
  ];
}
