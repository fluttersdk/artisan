import 'dart:async';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// `logger:tail` — prints the last N log entries, then (with --follow)
/// streams new ones as they arrive. Reads the log file directly — no
/// VM Service connection needed, so this stays CommandBoot.none and
/// works whether the app is running or not.
class LoggerTailCommand extends ArtisanCommand {
  @override
  String get signature =>
      'logger:tail '
      '{--file= : Path to the log file (default: \$HOME/.magic_logger.log)} '
      '{--lines=20 : Number of trailing lines to print} '
      '{--follow : Keep streaming new lines (Ctrl+C to stop)}';

  @override
  String get description => 'Tail the magic_logger output file.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final path =
        (ctx.input.option('file') as String?) ??
        '${Platform.environment['HOME'] ?? '/tmp'}/.magic_logger.log';
    final lines = int.tryParse(ctx.input.option('lines') as String) ?? 20;
    final follow = ctx.input.option('follow') as bool;

    final file = File(path);
    if (!file.existsSync()) {
      ctx.output.warning(
        'Log file not found: $path. Has any MagicLogger.* call fired yet?',
      );
      return 1;
    }

    // 1. Print the trailing N lines.
    final all = await file.readAsLines();
    final start = (all.length - lines).clamp(0, all.length);
    for (var i = start; i < all.length; i++) {
      ctx.output.writeln(all[i]);
    }

    if (!follow) return 0;

    // 2. Follow: poll file size every 250ms; print appended bytes.
    ctx.output.info('-- following $path (Ctrl+C to stop) --');
    var lastSize = file.lengthSync();
    final completer = Completer<int>();
    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      try {
        final now = file.lengthSync();
        if (now > lastSize) {
          final raf = await file.open();
          await raf.setPosition(lastSize);
          final bytes = await raf.read(now - lastSize);
          await raf.close();
          stdout.write(String.fromCharCodes(bytes));
          lastSize = now;
        }
      } catch (_) {
        // File may rotate / vanish; ignore and keep polling.
      }
    });
    // SIGINT handler — closes the loop cleanly.
    ProcessSignal.sigint.watch().listen((_) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(0);
    });
    return completer.future;
  }
}
