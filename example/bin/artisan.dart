import 'dart:io';

import 'package:example/config/artisan.dart';
import 'package:fluttersdk_artisan/artisan.dart';

/// Consumer-side artisan dispatcher. Runs under `dart run :artisan` or
/// (auto-delegated) `dart run fluttersdk_artisan <cmd>`.
///
/// Two responsibilities:
/// 1. Register the 9 builtin commands from fluttersdk_artisan.
/// 2. Expand `artisanProviders` (from lib/config/artisan.dart) — each
///    provider contributes its own command set under a namespace.
Future<void> main(List<String> args) async {
  try {
    final registry = ArtisanRegistry();
    registry.registerAll(
      _builtinCommands(registry),
      providerName: 'fluttersdk_artisan',
    );
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
      ReloadCommand(),
      HotRestartCommand(),
      RestartCommand(),
      DoctorCommand(),
      ListCommand(registry),
      HelpCommand(registry),
      MakeCommandCommand(),
      TinkerCommand(),
    ];
