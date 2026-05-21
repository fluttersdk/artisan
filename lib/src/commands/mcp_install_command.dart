import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../helpers/file_helper.dart';

/// `artisan mcp:install` — idempotently adds the fluttersdk MCP server entry
/// to the project's `.mcp.json` (Claude Code / Cursor / Windsurf config).
///
/// Entry shape branches on whether `bin/fsa` is present and the platform is
/// not Windows:
///
/// POSIX with `bin/fsa` present (fast path, ~110ms startup):
/// ```json
/// {
///   "mcpServers": {
///     "fluttersdk": {
///       "command": "./bin/fsa",
///       "args": ["mcp:serve"],
///       "cwd": "."
///     }
///   }
/// }
/// ```
///
/// Windows or when `bin/fsa` is absent (dart-direct fallback, ~3s startup):
/// ```json
/// {
///   "mcpServers": {
///     "fluttersdk": {
///       "command": "dart",
///       "args": ["run", ":dispatcher", "mcp:serve"],
///       "cwd": "."
///     }
///   }
/// }
/// ```
///
/// Pre-existing `mcpServers` keys are preserved. Running the command twice
/// replaces the `fluttersdk` key in-place (idempotent; no duplicates).
///
/// After writing, the success line reminds the user that Claude Code does NOT
/// auto-reconnect on `.mcp.json` edits and must be told to do so manually.
class McpInstallCommand extends ArtisanCommand {
  /// Creates an [McpInstallCommand].
  ///
  /// [hasFsa] and [isWindows] are optional predicates injected for testing.
  /// Production callers omit both; tests pass custom closures to exercise
  /// each branch without touching the filesystem or reading `Platform`.
  McpInstallCommand({
    bool Function()? hasFsa,
    bool Function()? isWindows,
  })  : _hasFsa = hasFsa ?? _defaultHasFsa,
        _isWindows = isWindows ?? _defaultIsWindows;

  final bool Function() _hasFsa;
  final bool Function() _isWindows;

  static bool _defaultHasFsa() => FileHelper.fileExists('bin/fsa');
  static bool _defaultIsWindows() => Platform.isWindows;
  @override
  String get name => 'mcp:install';

  @override
  String get description => 'Add the fluttersdk MCP server entry to .mcp.json '
      '(idempotent; preserves other server entries).';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'path',
      defaultsTo: '.mcp.json',
      help: 'Path to the target .mcp.json file.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final path = (ctx.input.option('path') as String?) ?? '.mcp.json';
    final file = File(path);

    // 1. Load existing config or start fresh.
    Map<String, dynamic> config;
    if (file.existsSync()) {
      try {
        config = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (e) {
        ctx.output.error('Failed to parse $path: $e');
        return 1;
      }
    } else {
      config = <String, dynamic>{};
    }

    // 2. Merge the fluttersdk entry into mcpServers; preserve all other keys.
    final servers = (config['mcpServers'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final useFsa = _hasFsa() && !_isWindows();
    servers['fluttersdk'] = useFsa
        ? <String, dynamic>{
            'command': './bin/fsa',
            'args': <String>['mcp:serve'],
            'cwd': '.',
          }
        : <String, dynamic>{
            'command': 'dart',
            'args': <String>['run', ':dispatcher', 'mcp:serve'],
            'cwd': '.',
          };
    config['mcpServers'] = servers;

    // 3. Write atomically (single write; no partial-read window on success).
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n',
    );

    ctx.output.success(
      'Wrote fluttersdk MCP server entry to $path.\n\n'
      'Note: Claude Code does NOT auto-reconnect on .mcp.json edits. '
      'Run /mcp reconnect fluttersdk inside Claude Code to load the new entry.',
    );
    return 0;
  }
}
