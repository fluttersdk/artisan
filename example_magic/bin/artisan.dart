import 'dart:io';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic/cli.dart' show MagicArtisanProvider;

Future<void> main(List<String> args) async {
  try {
    final registry = ArtisanRegistry();
    registry.registerAll(<ArtisanCommand>[
      StartCommand(), StopCommand(), StatusCommand(), LogsCommand(),
      RestartCommand(), ReloadCommand(), HotRestartCommand(), DoctorCommand(),
      ListCommand(registry), HelpCommand(registry),
      MakeCommandCommand(), CommandsRefreshCommand(),
      PluginInstallCommand(), PluginUninstallCommand(), MakePluginCommand(),
      TinkerCommand(),
    ], providerName: 'fluttersdk_artisan');
    registry.registerProvider(MagicArtisanProvider());
    exit(await ArtisanApplication(registry: registry).dispatch(args));
  } on ArtisanCommandCollisionException catch (e) {
    stderr.writeln('Fatal: $e'); exit(2);
  } catch (e, s) {
    stderr.writeln('Unexpected: $e\n$s'); exit(3);
  }
}
