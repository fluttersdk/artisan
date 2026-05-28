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
/// Entry shape is chosen by a three-branch precedence rule:
///
/// 1. POSIX with `bin/fsa` present (fast path, ~110ms startup):
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
/// 2. `bin/fsa` absent and `--invocation=<executable>` supplied (plugin
/// executable path, e.g. `fluttersdk_dusk`, ~3s startup):
/// ```json
/// {
///   "mcpServers": {
///     "fluttersdk": {
///       "command": "dart",
///       "args": ["run", "fluttersdk_dusk", "mcp:serve"],
///       "cwd": "."
///     }
///   }
/// }
/// ```
///
/// 3. `bin/fsa` absent and `--invocation` omitted (`:dispatcher` fallback,
/// ~3s startup):
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
    parser.addOption(
      'invocation',
      help: 'Plugin executable name to write into .mcp.json command/args '
          'when fastcli is absent (e.g., fluttersdk_dusk). Optional; falls back '
          'to the :dispatcher shape when omitted.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final path = (ctx.input.option('path') as String?) ?? '.mcp.json';
    final invocation = ctx.input.option('invocation') as String?;
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

    // 2. Merge the fluttersdk entry into mcpServers using the appropriate
    //    payload shape: fsa fastcli, dart-run-invocation, or :dispatcher fallback.
    final servers = (config['mcpServers'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final useFsa = _hasFsa() && !_isWindows();
    if (useFsa) {
      servers['fluttersdk'] = <String, dynamic>{
        'command': './bin/fsa',
        'args': <String>['mcp:serve'],
        'cwd': '.',
      };
    } else if (invocation != null && invocation.isNotEmpty) {
      servers['fluttersdk'] = <String, dynamic>{
        'command': 'dart',
        'args': <String>['run', invocation, 'mcp:serve'],
        'cwd': '.',
      };
    } else {
      servers['fluttersdk'] = <String, dynamic>{
        'command': 'dart',
        'args': <String>['run', ':dispatcher', 'mcp:serve'],
        'cwd': '.',
      };
    }
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
