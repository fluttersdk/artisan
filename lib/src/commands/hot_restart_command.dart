import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';

/// `artisan hot-restart` — full state reset of the running flutter app.
///
/// Writes `R\n` to the FIFO that flutter run's stdin reads from. flutter
/// run's own keystroke handler picks it up and reinitializes the Dart
/// isolate (drops all in-memory state, re-runs `main()`). Equivalent to
/// pressing `R` in an interactive `flutter run` session. Faster than
/// `restart` (no process re-spawn).
///
/// Use `restart` instead when you want a full process restart (e.g. to
/// pick up native plugin changes that hot restart doesn't see).
///
/// Requires `artisan start` first.
class HotRestartCommand extends ArtisanCommand {
  @override
  String get name => 'hot-restart';

  @override
  String get description =>
      'Hot restart the running app (sends `R` to flutter run\'s stdin). Drops Dart state, keeps process.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final state = await StateFile.read();
    if (state == null) {
      ctx.output.error(
        'No state file; nothing to hot-restart. Run `artisan start` first.',
      );
      return 2;
    }
    final pipePath = state['stdinPipe'] as String?;
    if (pipePath == null) {
      ctx.output.error(
        'state.json has no stdinPipe entry; the app was started by an older '
        'artisan that pre-dates the FIFO refactor. Run `artisan restart`.',
      );
      return 2;
    }
    final pipe = File(pipePath);
    if (!pipe.existsSync()) {
      ctx.output.error('Pipe missing: $pipePath. Run `artisan restart`.');
      return 2;
    }
    // Push the keystroke via shell (FIFOs reject lseek; printf via sh
    // opens-writes-closes without seeking).
    final result = await Process.run('sh', <String>[
      '-c',
      "printf %s 'R\n' > '${pipePath.replaceAll("'", r"'\''")}'",
    ]);
    if (result.exitCode != 0) {
      ctx.output.error(
        'Failed to write to pipe (exit ${result.exitCode}): ${result.stderr}',
      );
      return 1;
    }
    ctx.output.success('Sent `R` (hot-restart) to flutter run stdin.');
    return 0;
  }
}
