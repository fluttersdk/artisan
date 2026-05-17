import 'dart:io';

import 'package:example/app/commands/_index.g.dart' as auto;
import 'package:example/config/artisan.dart';
import 'package:fluttersdk_artisan/artisan.dart';

/// Consumer-side artisan dispatcher.
///
/// Two registration paths:
/// 1. Auto-discovery — every `ArtisanCommand` subclass under
///    `lib/app/commands/` is registered from `_index.g.dart` (kept fresh
///    by `make:command` and `commands:refresh`). Zero config.
/// 2. Third-party providers — packages like `fluttersdk_dusk` or `magic`
///    ship their own `ArtisanServiceProvider`; declare them in
///    `lib/config/artisan.dart` once.
Future<void> main(List<String> args) async {
  try {
    final registry = ArtisanRegistry();
    registry.registerAll(
      _builtinCommands(registry),
      providerName: 'fluttersdk_artisan',
    );
    registry.registerAll(auto.commands, providerName: 'app');
    for (final factory in artisanProviders) {
      registry.registerProvider(factory());
    }
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
      TinkerCommand(),
    ];
