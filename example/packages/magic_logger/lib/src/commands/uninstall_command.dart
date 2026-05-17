import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;

/// `logger:uninstall` — removes `lib/config/logger.dart` from the host
/// project. Asks for confirmation unless `--force` is passed.
class LoggerUninstallCommand extends ArtisanCommand {
  @override
  String get signature =>
      'logger:uninstall {--force : Skip confirmation prompt}';

  @override
  String get description =>
      'Remove magic_logger configuration from the host project.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final root = FileHelper.findProjectRoot();
    final configPath = p.join(root, 'lib', 'config', 'logger.dart');
    final configFile = File(configPath);
    if (!configFile.existsSync()) {
      ctx.output.info('Nothing to uninstall — $configPath not found.');
      return 0;
    }

    final force = ctx.input.option('force') as bool;
    final ok =
        force || Prompt.confirm('Delete $configPath?', defaultValue: false);
    if (!ok) {
      ctx.output.warning('Aborted.');
      return 0;
    }
    configFile.deleteSync();
    ctx.output.success('Deleted: $configPath');
    ctx.output.info(
      'Also remove the `configureMagicLogger()` call + import from lib/main.dart.',
    );
    return 0;
  }
}
