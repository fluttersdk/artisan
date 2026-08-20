import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';

/// `artisan reload` — hot reload the running flutter app.
///
/// Writes `r\n` to the FIFO that flutter run's stdin reads from. flutter
/// run's own keystroke handler picks it up and runs incremental Dart
/// source reload + framework reassembly. Equivalent to pressing `r` in
/// an interactive `flutter run` session.
///
/// Works on every device target (web/desktop/mobile) because we drive
/// flutter_tools' own protocol rather than calling VM Service RPCs
/// directly (web's dwds rejects some of those).
///
/// Requires `artisan start` first.
class ReloadCommand extends ArtisanCommand {
  @override
  String get name => 'reload';

  @override
  String get description =>
      'Hot reload the running app (sends `r` to flutter run\'s stdin). State preserved.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    return _sendKeystroke(ctx, 'r', 'reload');
  }
}

/// Shared helper for [ReloadCommand] and [HotRestartCommand].
Future<int> _sendKeystroke(ArtisanContext ctx, String key, String label) async {
  final state = await StateFile.read();

  // The legacy pointer describes whichever app started last, so a
  // command that writes to the recorded FIFO would otherwise reach
  // into a sibling project's running app.
  final String? ownership = state == null
      ? null
      : sessionOwnershipError(
          state: state,
          workingDirectory: Directory.current.path,
          explicitStatePath: StateFile.explicitPath(),
        );
  if (ownership != null) {
    ctx.output.error(ownership);
    return 1;
  }
  if (state == null) {
    ctx.output.error(
      'No state file; nothing to $label. Run `artisan start` first.',
    );
    return 2;
  }
  final pipePath = state['stdinPipe'] as String?;
  if (pipePath == null) {
    ctx.output.error(
      'The session has no stdinPipe entry, so there is no FIFO to send the '
      'keystroke through. Either the app was started by an artisan that '
      'pre-dates the FIFO refactor, or the state file was hand-written '
      'without it: it holds the path `artisan start` creates for '
      '`flutter run`\'s stdin. Run `artisan restart` to have one made.',
    );
    return 2;
  }
  final pipe = File(pipePath);
  if (!pipe.existsSync()) {
    ctx.output.error('Pipe missing: $pipePath. Run `artisan restart`.');
    return 2;
  }

  // Push the keystroke via shell. Dart's File.open() calls lseek which
  // FIFOs reject ("Illegal seek"); `printf %s > fifo` opens-writes-closes
  // without seeking, which is what flutter run's stdin reader needs.
  final result = await Process.run('sh', <String>[
    '-c',
    'printf %s ${_shellQuote('$key\n')} > ${_shellQuote(pipePath)}',
  ]);
  if (result.exitCode != 0) {
    ctx.output.error(
      'Failed to write to pipe (exit ${result.exitCode}): ${result.stderr}',
    );
    return 1;
  }
  ctx.output.success('Sent `$key` ($label) to flutter run stdin.');
  return 0;
}

String _shellQuote(String s) {
  if (RegExp(r'^[A-Za-z0-9_./=:-]+$').hasMatch(s)) return s;
  return "'${s.replaceAll("'", r"'\''")}'";
}
