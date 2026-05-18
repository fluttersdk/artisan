import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// Injectable typedef matching the [runArtisan] signature used by [mcpMain].
///
/// Tests inject a recording closure; production callers leave [runArtisan] at
/// its default ([runArtisan] from the barrel) so the full artisan bootstrap
/// (builtin registration, provider walk, MCP tool collection) runs unmodified.
typedef RunArtisanFn = Future<int> Function(
  List<String> args, {
  bool collectMcpTools,
});

/// Testable entry point for the MCP server binary.
///
/// Prepends `mcp:serve` to [args] so that [runArtisan] dispatches to
/// [McpServeCommand], and forces [collectMcpTools] to `true` so every
/// registered provider's MCP tool descriptors are collected into the
/// [ArtisanRegistry] before the server starts.
///
/// [runArtisan] is the injectable seam; production callers omit it and get
/// the real [runArtisan] bootstrap from `package:fluttersdk_artisan/artisan.dart`.
Future<int> mcpMain(
  List<String> args, {
  RunArtisanFn? runArtisan,
}) async {
  final fn = runArtisan ?? _defaultRunArtisan;
  return fn(['mcp:serve', ...args], collectMcpTools: true);
}

/// Forwards to the real [runArtisan] with positional + named args aligned.
Future<int> _defaultRunArtisan(
  List<String> args, {
  bool collectMcpTools = false,
}) =>
    runArtisan(args, collectMcpTools: collectMcpTools);

/// `dart run fluttersdk_artisan:mcp [args]` — MCP server entry point.
///
/// Thin wrapper around [mcpMain]. All server logic lives in [McpServeCommand]
/// dispatched by [runArtisan]; this file must not implement server logic
/// directly.
Future<void> main(List<String> args) async {
  stderr.writeln('[fluttersdk_artisan_mcp] starting');
  exit(await mcpMain(args));
}
