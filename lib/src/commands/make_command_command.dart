import 'dart:io';

import 'package:path/path.dart' as p;

import '../console/artisan_context.dart';
import '../console/artisan_generator_command.dart';
import '../helpers/file_helper.dart';
import 'commands_index_writer.dart';

/// `artisan make:command MyCommand` — scaffolds a new ArtisanCommand subclass
/// under `lib/app/commands/` and refreshes the auto-discovery index so the
/// new command shows up on the next `artisan list` without manual wiring.
class MakeCommandCommand extends ArtisanGeneratorCommand {
  @override
  String get name => 'make:command';

  @override
  String get description =>
      'Scaffold a new ArtisanCommand subclass under lib/app/commands/.';

  @override
  String getStub() => 'artisan_command';

  @override
  String getDefaultNamespace() => 'lib/app/commands';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final code = await super.handle(ctx);
    if (code != 0) return code;
    // Auto-refresh the index so the consumer's bin/artisan.dart picks the
    // new command up without an extra `commands:refresh` invocation.
    final root = FileHelper.findProjectRoot();
    final commandsDir = Directory(p.join(root, 'lib', 'app', 'commands'));
    writeCommandsIndex(commandsDir);
    return 0;
  }
}
