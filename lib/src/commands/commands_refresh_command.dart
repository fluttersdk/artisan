import 'dart:io';

import 'package:path/path.dart' as p;

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../helpers/file_helper.dart';
import 'commands_index_writer.dart';

/// `artisan commands:refresh` — scans `lib/app/commands/` and rewrites
/// `_index.g.dart` so every ArtisanCommand subclass in that directory is
/// auto-registered on the next `artisan` invocation.
///
/// Run after manually adding/removing/renaming a command file (the more
/// common path is `artisan make:command Foo`, which already updates the
/// index automatically).
class CommandsRefreshCommand extends ArtisanCommand {
  @override
  String get name => 'commands:refresh';

  @override
  String get description =>
      'Rescan lib/app/commands/ and rewrite the auto-discovery index.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final root = FileHelper.findProjectRoot();
    final commandsDir = Directory(p.join(root, 'lib', 'app', 'commands'));
    final discovered = writeCommandsIndex(commandsDir);
    final indexPath = p.join(commandsDir.path, '_index.g.dart');
    ctx.output.success(
      'Refreshed: ${discovered.length} command(s) registered → $indexPath',
    );
    for (final c in discovered) {
      ctx.output.writeln('  - ${c.className}  (${c.fileName})');
    }
    return 0;
  }
}
