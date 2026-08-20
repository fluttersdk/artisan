import 'package:args/args.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';
import 'start_command.dart';
import 'stop_command.dart';

/// Composes stop + start atomically, preserving the prior session's
/// settings.
///
/// `StopCommand` deletes the session state, so everything the app was
/// started with would be lost before `StartCommand` runs. `RestartCommand`
/// reads the prior state first and carries the CDP port, the web port, the
/// VM Service port and the device across. An explicit flag on the restart
/// invocation always wins over the carried value.
///
/// Only the CDP port used to survive, and the other three mattered as much:
/// a restart relaunched on web port 3100, which a sibling worktree usually
/// holds, so the stop half succeeded and the relaunch failed with
/// `Address already in use` while naming a port the caller never typed. A
/// restart onto the default web-server device is quieter and worse: nothing
/// renders, and every screenshot after it comes back byte-identical.
class RestartCommand extends ArtisanCommand {
  @override
  String get name => 'restart';

  @override
  String get description => 'Stop + start the running flutter app.';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// The `state.json` keys a restart carries into the relaunch. They are
  /// also the [StartCommand] parameter names, which is why no translation
  /// table sits between the two.
  static const List<String> _carriedKeys = <String>[
    'cdpPort',
    'webPort',
    'vmServicePort',
    'device',
  ];

  /// The session settings a restart carries over, read from [priorState].
  ///
  /// Empty when there is nothing to carry. Exposed for testing because the
  /// forwarding is the whole behaviour of this command and the alternative
  /// is asserting it through a real `flutter run`.
  static Map<String, Object?> sessionOverridesFrom(
    Map<String, dynamic>? priorState,
  ) {
    if (priorState == null) return const <String, Object?>{};
    return <String, Object?>{
      for (final String key in _carriedKeys)
        if (priorState[key] != null) key: priorState[key],
    };
  }

  @override
  void configure(ArgParser parser) {
    // Every option below is declared so `restart --<opt>=N` parses AND so an
    // explicit flag can win over the value carried from the prior session.
    //
    // Only --cdp-port used to be carried, so a restart relaunched on the
    // default web port and VM Service port. Several worktrees run their own
    // dev server here, so 3100 is usually held by a sibling: the stop half
    // succeeded, the relaunch failed with `Address already in use`, and the
    // app being driven was gone. The error names a port that appears in no
    // command the caller ran, which reads as a machine problem rather than a
    // missing flag.
    parser.addOption(
      'cdp-port',
      defaultsTo: null,
      help: 'Chrome DevTools Protocol port. Overrides the CDP port preserved '
          'from the prior session. Omit to keep the previous session\'s port.',
    );
    parser.addOption(
      'port',
      defaultsTo: null,
      help: 'Web port. Omit to keep the previous session\'s port.',
    );
    parser.addOption(
      'vm-service-port',
      defaultsTo: null,
      help: 'Host VM Service port. Omit to keep the previous session\'s port.',
    );
    parser.addOption(
      'device',
      defaultsTo: null,
      help: 'Flutter device target. Omit to keep the previous session\'s '
          'device; a restart onto the default web-server device renders in no '
          'browser and every later screenshot comes back stale.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Read the prior state BEFORE stop deletes it, so every setting the
    //    session was started with can be carried over rather than silently
    //    reverting to a default.
    final priorState = await StateFile.read();
    final Map<String, Object?> carried = sessionOverridesFrom(priorState);

    // 2. Stop the running app (deletes the session state). A non-zero exit
    //    is a REFUSAL, not noise: `stop` returns 1 when the recorded session
    //    belongs to another project. Proceeding past it would relaunch this
    //    project on the OTHER project's ports and device, carried over by
    //    `sessionOverridesFrom` above, which is the `Address already in use`
    //    this command exists to stop producing.
    final int stopped = await StopCommand().handle(ctx);
    if (stopped != 0) return stopped;

    // 3. Start again with the carried settings. An explicit flag on ctx
    //    overrides the carried value inside StartCommand.handle (flag-wins).
    return StartCommand().handle(
      ctx,
      cdpPort: carried['cdpPort'] as int?,
      webPort: carried['webPort'] as int?,
      vmServicePort: carried['vmServicePort'] as int?,
      device: carried['device'] as String?,
    );
  }
}
