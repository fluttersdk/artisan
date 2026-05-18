import '../mcp/mcp_tool_collision_exception.dart';
import '../mcp/mcp_tool_descriptor.dart';
import 'artisan_command.dart';
import 'artisan_command_collision_exception.dart';
import 'artisan_service_provider.dart';

/// Authoritative command registry for an [ArtisanApplication].
///
/// Holds the merged command map across builtin + provider-contributed
/// commands. FAIL-FAST collision: same name registered twice without
/// explicit `override: true` throws [ArtisanCommandCollisionException].
///
/// Also acts as the authoritative MCP tool catalog when the application
/// boots through the MCP server entry point. MCP tools are collected via
/// a separate [registerMcpToolsFor] call (NOT auto-collected inside
/// [registerProvider]); the split-API asymmetry is intentional so that CLI
/// invocations (`dart run :artisan list`, `make:command`, etc.) pay zero
/// cost walking and validating tool descriptors they never consume. The
/// MCP entry point (`runArtisan(args, collectMcpTools: true)`) is the only
/// caller that opts in.
class ArtisanRegistry {
  final Map<String, _RegistryEntry> _commands = {};
  final Map<String, _RegisteredMcpTool> _mcpTools = {};

  /// Register a single command from a named provider.
  void register(
    ArtisanCommand command, {
    String providerName = 'unnamed',
    bool override = false,
  }) {
    final existing = _commands[command.name];
    if (existing != null && !override) {
      throw ArtisanCommandCollisionException(
        commandName: command.name,
        existingProvider: existing.providerName,
        newProvider: providerName,
      );
    }
    _commands[command.name] = _RegistryEntry(command, providerName);
  }

  /// Bulk register from a list (typically [ArtisanServiceProvider.commands]).
  void registerAll(
    List<ArtisanCommand> commands, {
    String providerName = 'unnamed',
    bool override = false,
  }) {
    for (final cmd in commands) {
      register(cmd, providerName: providerName, override: override);
    }
  }

  /// Register all commands from a provider (convenience wrapper).
  void registerProvider(
    ArtisanServiceProvider provider, {
    bool override = false,
  }) {
    registerAll(
      provider.commands(),
      providerName: provider.providerName,
      override: override,
    );
  }

  /// Register all MCP tool descriptors contributed by [provider].
  ///
  /// Mirrors [registerAll]'s collision discipline: every descriptor is
  /// inserted into [_mcpTools] keyed by [McpToolDescriptor.name]; a duplicate
  /// name throws [ArtisanMcpToolCollisionException] naming both the existing
  /// and the conflicting provider. There is no `override` escape hatch (V1):
  /// MCP tool names map 1:1 to the JSON-RPC method surface exposed to the
  /// LLM client, and silent shadowing would make behaviour undebuggable.
  ///
  /// NOT called from [registerProvider]. The MCP entry path
  /// (`runArtisan(args, collectMcpTools: true)`) opts in explicitly so that
  /// CLI invocations skip the descriptor walk + validation cost.
  void registerMcpToolsFor(ArtisanServiceProvider provider) {
    for (final tool in provider.mcpTools()) {
      final existing = _mcpTools[tool.name];
      if (existing != null) {
        throw ArtisanMcpToolCollisionException(
          toolName: tool.name,
          existingProvider: existing.providerName,
          newProvider: provider.providerName,
        );
      }
      _mcpTools[tool.name] = _RegisteredMcpTool(tool, provider.providerName);
    }
  }

  /// All registered MCP tool descriptors (immutable view).
  ///
  /// Returns an unmodifiable list snapshot; mutating the returned list throws.
  /// Order is insertion order, which matches registration order across
  /// providers as visited by [registerMcpToolsFor].
  List<McpToolDescriptor> get mcpTools => List<McpToolDescriptor>.unmodifiable(
        _mcpTools.values.map((entry) => entry.tool),
      );

  /// Returns the name of the provider that contributed the MCP tool named
  /// [toolName], or `null` when no tool with that name is registered.
  ///
  /// Backs [McpFilterConfig.apply]'s `providerNameLookup` callback: the
  /// filter needs to map each descriptor back to its owning package to honor
  /// `packagesAllow` / `packagesDeny`. Co-locating the lookup with the
  /// registry (which already stores `_RegisteredMcpTool { tool, providerName }`)
  /// avoids duplicating that index inside the MCP server.
  String? providerNameFor(String toolName) => _mcpTools[toolName]?.providerName;

  /// Look up a command by name; returns null if absent.
  ArtisanCommand? find(String name) => _commands[name]?.command;

  /// All registered commands, name-sorted.
  List<ArtisanCommand> all() {
    final entries = _commands.values.map((e) => e.command).toList();
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  /// All registered commands grouped by `:` namespace prefix.
  Map<String, List<ArtisanCommand>> groupedByNamespace() {
    final namespaces = <String, List<ArtisanCommand>>{};
    final rootCommands = <ArtisanCommand>[];
    for (final entry in _commands.values) {
      final parts = entry.command.name.split(':');
      if (parts.length > 1) {
        namespaces.putIfAbsent(parts[0], () => []).add(entry.command);
      } else {
        rootCommands.add(entry.command);
      }
    }
    final result = <String, List<ArtisanCommand>>{};
    if (rootCommands.isNotEmpty) {
      rootCommands.sort((a, b) => a.name.compareTo(b.name));
      result[''] = rootCommands;
    }
    final sortedNs = namespaces.keys.toList()..sort();
    for (final ns in sortedNs) {
      final cmds = namespaces[ns]!..sort((a, b) => a.name.compareTo(b.name));
      result[ns] = cmds;
    }
    return result;
  }

  /// Returns the count of registered commands (useful for tests + verification).
  int get length => _commands.length;
}

class _RegistryEntry {
  const _RegistryEntry(this.command, this.providerName);
  final ArtisanCommand command;
  final String providerName;
}

/// Private wrapper bundling a registered MCP tool descriptor with the name of
/// the provider that contributed it. The provider name is the diagnostic
/// surface for [ArtisanMcpToolCollisionException].
class _RegisteredMcpTool {
  const _RegisteredMcpTool(this.tool, this.providerName);
  final McpToolDescriptor tool;
  final String providerName;
}
