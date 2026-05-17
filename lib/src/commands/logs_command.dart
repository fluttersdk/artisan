import 'dart:io';

import 'package:args/args.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';

/// Print or tail the captured `flutter run` stdout/stderr log.
class LogsCommand extends ArtisanCommand {
  @override
  String get name => 'logs';

  @override
  String get description => 'Print or --follow the captured flutter run log.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    parser.addFlag('follow', abbr: 'f', defaultsTo: false, negatable: false);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final stateDir = File(StateFile.path).parent.path;
    final logFile = File('$stateDir/flutter-dev.log');
    if (!logFile.existsSync()) {
      ctx.output.warning(
        'Log file not found at ${logFile.path}. Run `artisan start` first.',
      );
      return 1;
    }
    final follow = (ctx.input.option('follow') as bool?) ?? false;
    if (!follow) {
      stdout.write(await logFile.readAsString());
      return 0;
    }
    int pos = 0;
    while (true) {
      final size = logFile.lengthSync();
      if (size > pos) {
        final raf = await logFile.open();
        await raf.setPosition(pos);
        final bytes = await raf.read(size - pos);
        await raf.close();
        stdout.add(bytes);
        pos = size;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}
