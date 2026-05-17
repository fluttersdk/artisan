import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;

/// `dart run fluttersdk_artisan <cmd>` — universal entrypoint.
///
/// Auto-discovery rule: when invoked from a project that ships its own
/// `bin/artisan.dart` wrapper (the convention for consumers that register
/// custom ArtisanServiceProviders via `lib/config/artisan.dart`), this
/// binary transparently delegates to it via `dart run :artisan <args>`.
/// The consumer wrapper sees its full provider list. When no wrapper
/// exists (vanilla Flutter project, no providers configured), this binary
/// runs with the 9 builtin commands only.
///
/// Both invocation forms work from any project that depends on
/// `fluttersdk_artisan`:
///
/// ```bash
/// dart run fluttersdk_artisan list      # this binary; auto-delegates if wrapper present
/// dart run :artisan list                # consumer wrapper directly (current package)
/// ```
Future<void> main(List<String> args) async {
  final consumerWrapper = File(
    p.join(Directory.current.path, 'bin', 'artisan.dart'),
  );
  // commands:refresh runs standalone even when a consumer wrapper exists.
  // Otherwise a stale/broken lib/app/commands/_index.g.dart would block the
  // wrapper from compiling, which would block the very command that fixes
  // the index. Pure-substrate path stays compile-safe regardless of
  // consumer-tree state.
  final firstArg = args.isNotEmpty ? args.first : '';
  final bypassDelegate = firstArg == 'commands:refresh';

  if (consumerWrapper.existsSync() && !bypassDelegate) {
    // Delegate to the consumer wrapper. It owns the full provider list
    // from lib/config/artisan.dart + the auto-discovered commands index.
    final result = await Process.start(
      Platform.resolvedExecutable, // dart
      ['run', ':artisan', ...args],
      mode: ProcessStartMode.inheritStdio,
      workingDirectory: Directory.current.path,
    );
    exit(await result.exitCode);
  }

  // Standalone path: 9 builtins only.
  try {
    final registry = ArtisanRegistry();
    registry.registerAll(
      _builtinCommands(registry),
      providerName: 'fluttersdk_artisan',
    );
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
      CommandsRefreshCommand(),
      TinkerCommand(),
    ];
