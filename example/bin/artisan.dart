import 'dart:io';

import 'package:example/app/commands/_index.g.dart' as auto;
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_logger/cli.dart';

/// Consumer-side artisan dispatcher.
///
/// Two registration paths:
///   1. App-level commands — every `ArtisanCommand` subclass under
///      `lib/app/commands/` is auto-discovered via the generated
///      `_index.g.dart` (kept fresh by `make:command` and
///      `commands:refresh`). ZERO config.
///   2. Third-party packages — uncomment the imports + registerProvider
///      lines below as you add pub packages that ship a
///      `cli.dart` sub-barrel (e.g. `fluttersdk_dusk`, `magic`).
Future<void> main(List<String> args) async {
  try {
    final registry = ArtisanRegistry();
    registry.registerAll(
      _builtinCommands(registry),
      providerName: 'fluttersdk_artisan',
    );
    registry.registerAll(auto.commands, providerName: 'app');
    registry.registerProvider(MagicLoggerArtisanProvider());

    // Third-party package providers — uncomment as you add them.
    // registry.registerProvider(DuskArtisanProvider());
    // registry.registerProvider(TelescopeArtisanProvider());
    // registry.registerProvider(MagicArtisanProvider());

    final app = ArtisanApplication(registry: registry);
    exit(await app.dispatch(args));
  } on ArtisanCommandCollisionException catch (e) {
    stderr.writeln('Fatal: $e');
    exit(2);
  } catch (e, s) {
    stderr.writeln('Unexpected error: $e');
    stderr.writeln(s);
    exit(3);
  }
}

List<ArtisanCommand> _builtinCommands(ArtisanRegistry registry) =>
    <ArtisanCommand>[
      StartCommand(),
      StopCommand(),
      StatusCommand(),
      LogsCommand(),
      RestartCommand(),
      ReloadCommand(),
      HotRestartCommand(),
      DoctorCommand(),
      ListCommand(registry),
      HelpCommand(registry),
      MakeCommandCommand(),
      CommandsRefreshCommand(),
      PluginInstallCommand(),
      TinkerCommand(),
    ];
