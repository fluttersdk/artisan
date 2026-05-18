import 'dart:io';

import 'package:args/args.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/artisan_registry.dart';
import '../console/command_boot.dart';
import '../mcp/mcp_filter_config.dart';
import '../mcp/mcp_server.dart';

/// Signature for the serve strategy injected into [McpServeCommand].
///
/// Production code passes [McpServer.serve]; tests inject a no-op closure
/// that returns immediately without opening a stdio JSON-RPC connection.
typedef ServeStrategy = Future<void> Function({
  required ArtisanRegistry registry,
  required McpFilterConfig filter,
});

/// `artisan mcp:serve` — starts the fluttersdk MCP server over stdio JSON-RPC.
///
/// The server bridges Claude Code / Cursor / Windsurf to the running Flutter
/// app via the VM Service extension method surface contributed by installed
/// plugins ([ArtisanServiceProvider.mcpTools]).
///
/// Filter precedence (Cargo-style replace for allow; union for deny):
///   file `.artisan/mcp.json` < env vars < CLI flags.
///
/// After editing `.artisan/mcp.json` or env vars, the client must reconnect;
/// the server does NOT auto-reload in V1 (SIGHUP/file-watch is V1.1 BACKLOG).
class McpServeCommand extends ArtisanCommand {
  /// Constructs the command.
  ///
  /// [serveOverride] is a test-seam: pass a no-op to skip the live stdio
  /// JSON-RPC connection. Production callers leave it null and get
  /// [McpServer.serve] by default.
  McpServeCommand({ServeStrategy? serveOverride})
      : _serve = serveOverride ?? McpServer.serve;

  final ServeStrategy _serve;

  @override
  String get name => 'mcp:serve';

  @override
  String get description =>
      'Run the fluttersdk MCP server (stdio JSON-RPC) for Claude Code / Cursor / Windsurf.'
      '\n\nAfter editing .artisan/mcp.json or env vars, run '
      '/mcp reconnect fluttersdk in Claude Code to apply the changes.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    super.configure(parser);
    parser
      ..addMultiOption(
        'include-package',
        help: 'Include tools from this package only (repeatable). '
            'When absent all packages are included. '
            'CLI value replaces env and file allow lists.',
        valueHelp: 'package_name',
      )
      ..addMultiOption(
        'exclude-package',
        help: 'Exclude all tools from this package (repeatable). '
            'Deny wins over allow across all layers.',
        valueHelp: 'package_name',
      )
      ..addMultiOption(
        'include-tool',
        help: 'Include only this tool name (repeatable). '
            'CLI value replaces env and file allow lists.',
        valueHelp: 'tool_name',
      )
      ..addMultiOption(
        'exclude-tool',
        help: 'Exclude this tool name (repeatable). '
            'Deny wins over allow across all layers.',
        valueHelp: 'tool_name',
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Parse CLI flags into a filter layer.
    final cliConfig = McpFilterConfig.fromCli(
      includePackage:
          (ctx.input.option('include-package') as List?)?.cast<String>(),
      excludePackage:
          (ctx.input.option('exclude-package') as List?)?.cast<String>(),
      includeTool: (ctx.input.option('include-tool') as List?)?.cast<String>(),
      excludeTool: (ctx.input.option('exclude-tool') as List?)?.cast<String>(),
    );

    // 2. Parse the environment layer.
    final envConfig = McpFilterConfig.fromEnv(Platform.environment);

    // 3. Parse the file layer; absent file is treated as "no opinion".
    const mcpJsonPath = '.artisan/mcp.json';
    final fileConfig = File(mcpJsonPath).existsSync()
        ? McpFilterConfig.fromFile(mcpJsonPath)
        : McpFilterConfig.empty();

    // 4. Merge the three layers (CLI > env > file for allow; union for deny).
    final filter = McpFilterConfig.merge(fileConfig, envConfig, cliConfig);

    // 5. Build the registry so tool descriptors contributed by providers are
    //    available to the server. The registry is passed through to _serve so
    //    that McpServer.serve can register tools from it at initialize time.
    //    Using a fresh bare registry here mirrors the bin/mcp.dart entry pattern
    //    (Step 22): providers are collected via the caller's context registry
    //    or a fresh one when invoked standalone.
    final registry = ctx.registry ?? ArtisanRegistry();

    // 6. Spawn the server and block until the peer closes the connection.
    //    Returns 0 on graceful disconnect, 1 on connection failure.
    try {
      await _serve(registry: registry, filter: filter);
      return 0;
    } on StateError catch (e) {
      ctx.output.error('mcp:serve failed: $e');
      return 1;
    }
  }
}
