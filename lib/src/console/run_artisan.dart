import 'dart:io';

import 'package:path/path.dart' as p;

import '../commands/commands_refresh_command.dart';
import '../commands/doctor_command.dart';
import '../commands/help_command.dart';
import '../commands/hot_restart_command.dart';
import '../commands/list_command.dart';
import '../commands/logs_command.dart';
import '../commands/make_command_command.dart';
import '../commands/make_fast_cli_command.dart';
import '../commands/make_plugin_command.dart';
import '../commands/install_command.dart';
import '../commands/mcp_install_command.dart';
import '../commands/mcp_serve_command.dart';
import '../commands/mcp_uninstall_command.dart';
import '../commands/plugin_install_command.dart';
import '../commands/plugin_uninstall_command.dart';
import '../commands/plugins_refresh_command.dart';
import '../commands/reload_command.dart';
import '../commands/restart_command.dart';
import '../commands/start_command.dart';
import '../commands/status_command.dart';
import '../commands/stop_command.dart';
import '../commands/tinker_command.dart';
import 'artisan_application.dart';
import 'artisan_command.dart';
import 'artisan_command_collision_exception.dart';
import 'artisan_registry.dart';
import 'artisan_service_provider.dart';

/// Bypass list for auto-delegation.
///
/// Commands that regenerate the very files the consumer wrapper imports MUST
/// run from the substrate binary, never via delegation. Otherwise a stale or
/// broken `lib/app/_index.g.dart` / `lib/app/_plugins.g.dart` blocks the
/// wrapper from compiling, blocking the only command that can fix it.
const Set<String> _bypassDelegation = <String>{
  'commands:refresh',
  'plugins:refresh',
};

/// Signature for an injected "does CWD have a consumer wrapper?" check.
///
/// A consumer wrapper is either `bin/dispatcher.dart` (the canonical name
/// emitted by `dart run fluttersdk_artisan install`) or `bin/artisan.dart`
/// (the legacy name still accepted for backward compatibility with
/// hand-curated wrappers).
///
/// Defaults to the real FS lookup ([defaultConsumerWrapperExists]); tests
/// inject a deterministic stub.
typedef WrapperExistsCheck = bool Function();

/// Signature for an injected delegation strategy.
///
/// Defaults to `Process.start` against the consumer wrapper with stdio
/// inherited; tests inject a closure that records args + returns an exit
/// code without spawning a child process.
typedef DelegateStrategy = Future<int> Function(List<String> args);

/// Shared `artisan` bootstrap.
///
/// One entry point consolidates the four behaviors every artisan binary
/// (substrate `fluttersdk_artisan`, magic's consumer wrapper, magic_logger's
/// consumer wrapper, future consumer wrappers) needs:
///
/// 1. **Auto-delegation.** When invoked from a project that ships its own
///    consumer wrapper (`bin/dispatcher.dart`, or the legacy
///    `bin/artisan.dart`), transparently re-invoke `dart run :dispatcher <args>`
///    so the consumer's full provider list owns dispatch. Bypassed for
///    commands that regenerate the files the wrapper depends on (see
///    [_bypassDelegation]).
/// 2. **Standalone dispatch.** When no wrapper is present (or the call
///    bypasses delegation, or [delegateToConsumer] is `false`), register
///    builtins + [baseProviders] + auto-discovered providers and dispatch
///    via [ArtisanApplication].
/// 3. **Fail-fast collision.** A duplicate command between providers
///    surfaces as exit 2 (matches the substrate bin's prior behavior).
/// 4. **Generic crash handling.** Any unexpected throw surfaces as exit 3
///    (matches [ArtisanApplication]'s in-handle exception code).
///
/// [baseProviders] are statically known providers the caller wires by hand
/// (e.g. `[MagicArtisanProvider()]` from magic's wrapper). [autoProviders]
/// is a thunk for codegen-discovered providers (the `_plugins.g.dart`
/// `autoDiscoveredProviders()` function); deferred so a missing or broken
/// codegen file does not crash callers that pass only [baseProviders].
///
/// [wrapperExists] and [delegate] are seams for tests; production callers
/// leave them at their defaults.
///
/// When [collectMcpTools] is `true`, each provider's MCP tool descriptors are
/// registered via [ArtisanRegistry.registerMcpToolsFor] immediately after the
/// provider's commands are registered. Defaults to `false` so CLI invocations
/// (e.g. `dart run :dispatcher list`) pay no MCP overhead. Only the MCP server
/// entry point (`bin/mcp.dart`) passes `collectMcpTools: true`.
Future<int> runArtisan(
  List<String> args, {
  List<ArtisanServiceProvider> baseProviders = const <ArtisanServiceProvider>[],
  List<ArtisanServiceProvider> Function()? autoProviders,
  bool delegateToConsumer = true,
  bool collectMcpTools = false,
  WrapperExistsCheck? wrapperExists,
  DelegateStrategy? delegate,
}) async {
  // 1. Decide whether the consumer wrapper owns this invocation.
  if (delegateToConsumer) {
    final hasWrapper = (wrapperExists ?? defaultConsumerWrapperExists)();
    final firstArg = args.isEmpty ? '' : args.first;
    final bypassed = _bypassDelegation.contains(firstArg);
    if (hasWrapper && !bypassed) {
      return await (delegate ??
          _defaultDelegate)(<String>[':dispatcher', ...args]);
    }
  }

  // 2. Standalone path: builtins + baseProviders + autoProviders.
  try {
    final registry = ArtisanRegistry();
    registry.registerAll(
      _builtinCommands(registry),
      providerName: 'fluttersdk_artisan',
    );
    for (final provider in baseProviders) {
      registry.registerProvider(provider);
      if (collectMcpTools) registry.registerMcpToolsFor(provider);
    }
    final auto = autoProviders?.call() ?? const <ArtisanServiceProvider>[];
    for (final provider in auto) {
      registry.registerProvider(provider);
      if (collectMcpTools) registry.registerMcpToolsFor(provider);
    }
    final app = ArtisanApplication(registry: registry);
    return await app.dispatch(args);
  } on ArtisanCommandCollisionException catch (e) {
    stderr.writeln('Fatal: $e');
    return 2;
  } catch (e, s) {
    stderr.writeln('Unexpected error: $e');
    stderr.writeln(s);
    return 3;
  }
}

/// Default wrapper presence check.
///
/// Returns `true` when either `<cwd>/bin/dispatcher.dart` (the canonical name
/// scaffolded by `dart run fluttersdk_artisan install`) or
/// `<cwd>/bin/artisan.dart` (the legacy name, still accepted for backward
/// compatibility) exists. Either filename qualifies the current directory as
/// a consumer wrapper that auto-delegation should target.
///
/// [cwd] defaults to [Directory.current]; tests inject a temp-dir path to
/// drive the check deterministically without touching the host filesystem.
bool defaultConsumerWrapperExists({String? cwd}) {
  final base = cwd ?? Directory.current.path;
  final dispatcher = File(p.join(base, 'bin', 'dispatcher.dart'));
  if (dispatcher.existsSync()) return true;
  final legacy = File(p.join(base, 'bin', 'artisan.dart'));
  return legacy.existsSync();
}

/// Default delegation: `dart run :dispatcher <args>` with inherited stdio.
Future<int> _defaultDelegate(List<String> args) async {
  final result = await Process.start(
    Platform.resolvedExecutable,
    <String>['run', ...args],
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: Directory.current.path,
  );
  return await result.exitCode;
}

/// Builtins shipped by `fluttersdk_artisan` itself.
///
/// `CommandsRefreshCommand` and `PluginsRefreshCommand` ship side-by-side
/// here AND in the bypass list ([_bypassDelegation]); the bypass guarantee
/// is what lets these commands fix a broken consumer wrapper without first
/// requiring that same wrapper to compile.
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
      MakeFastCliCommand(),
      MakePluginCommand(),
      CommandsRefreshCommand(),
      PluginsRefreshCommand(),
      PluginInstallCommand(),
      PluginUninstallCommand(),
      InstallArtisanCommand(),
      TinkerCommand(),
      McpServeCommand(),
      McpInstallCommand(),
      McpUninstallCommand(),
    ];
