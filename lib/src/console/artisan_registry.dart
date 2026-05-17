import 'artisan_command.dart';
import 'artisan_command_collision_exception.dart';
import 'artisan_service_provider.dart';

/// Authoritative command registry for an [ArtisanApplication].
///
/// Holds the merged command map across builtin + provider-contributed
/// commands. FAIL-FAST collision: same name registered twice without
/// explicit `override: true` throws [ArtisanCommandCollisionException].
class ArtisanRegistry {
  final Map<String, _RegistryEntry> _commands = {};

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
