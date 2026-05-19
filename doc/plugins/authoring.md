# Plugin Authoring Guide

## Overview

A plugin is a Dart package that ships an `ArtisanServiceProvider` subclass. The
subclass declares the CLI commands and MCP tool descriptors the plugin contributes.
When a consumer calls `plugin:install <name>`, artisan registers the provider in
`lib/app/_plugins.g.dart`, which is loaded at startup and merged into the
`ArtisanRegistry`. Commands appear in `artisan list`; MCP tool descriptors surface
through the stdio JSON-RPC server so LLM agents can invoke them by name.

---

## Getting Started

Scaffold the plugin skeleton with the `make:plugin` command:

```bash
dart run fluttersdk_artisan make:plugin awesome_plugin
```

The generator creates the following tree inside `awesome_plugin/`:

```
awesome_plugin/
  lib/
    awesome_plugin.dart          # barrel export
    src/
      awesome_artisan_provider.dart   # ArtisanServiceProvider subclass
      commands/                       # one file per ArtisanCommand
  pubspec.yaml                   # declares fluttersdk_artisan dependency
  CHANGELOG.md
  README.md
```

The generated provider is immediately wirable: `plugin:install awesome_plugin`
injects `AwesomeArtisanProvider.new` into the consumer's `_plugins.g.dart`.

---

## ArtisanServiceProvider Contract

Every plugin must extend `ArtisanServiceProvider`
(`lib/src/console/artisan_service_provider.dart:11-25`):

```dart
abstract class ArtisanServiceProvider {
  /// Human-readable provider name used in collision error messages.
  /// Defaults to the runtime class name.
  String get providerName => runtimeType.toString();

  /// Returns the commands this provider contributes to the application.
  List<ArtisanCommand> commands();

  /// Returns the MCP tool descriptors this provider contributes.
  ///
  /// Defaults to an empty list so existing providers compile without
  /// modification. Override to expose VM-Service-backed tools to the MCP
  /// server.
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[];
}
```

Key points:

- `commands()` is **abstract**: return every `ArtisanCommand` subclass your
  plugin ships. Duplicate command names throw `ArtisanCommandCollisionException`.
- `mcpTools()` defaults to an empty list. Override it to expose VM Service
  extension tools to the MCP server.
- `providerName` defaults to `runtimeType.toString()`. Override it with a
  stable identifier (e.g. `'fluttersdk_dusk'`) so collision messages survive
  class renames.
- There is no `register()` lifecycle hook on `ArtisanServiceProvider`.
  Initialization belongs in command constructors or the host app's boot phase.

Minimal scaffold provider (`assets/stubs/make_plugin/generic/provider.dart.stub`):

```dart
import 'package:fluttersdk_artisan/artisan.dart';

final class AwesomeArtisanProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        // Commands added via `make:command` land here automatically.
      ];
  // To expose MCP tools, override mcpTools() returning your descriptor list.
}
```

---

## Writing Commands

Each entry in `commands()` is an `ArtisanCommand` subclass. Declare the command
surface via the Signature DSL or `configure(ArgParser)`:

- **Signature DSL** (preferred): `String get signature => 'cmd:name {arg} {--flag}'`.
  See [Signature DSL reference](../reference/signature-dsl.md) for the full syntax.
- **`configure(ArgParser)`**: explicit fallback for cases the DSL cannot express
  (subcommands, allowed values with validation, etc.).

Scaffold a new command inside the plugin directory:

```bash
dart run fluttersdk_artisan make:command MyVerb
```

The generator writes `lib/src/commands/my_verb_command.dart` and auto-registers
it in the provider's `commands()` list. See
[make:command](../commands/make-command.md) for the full scaffold walkthrough.

---

## Adding MCP Tools

Override `mcpTools()` and return a `List<McpToolDescriptor>`. Each descriptor
(`lib/src/mcp/mcp_tool_descriptor.dart:24-82`) is a `const`-constructible value
with four required fields:

| Field | Type | Purpose |
|---|---|---|
| `name` | `String` | Snake-case, service-prefixed tool name (e.g. `awesome_start`). Must be globally unique across all loaded providers. |
| `description` | `String` | Action-oriented, LLM-targeted description. Imperative opening sentence, usage bullets, constraint-forward language. |
| `inputSchema` | `Map<String, dynamic>` | JSON Schema draft-7 object describing accepted input. Pass `{'type': 'object', 'properties': {}}` when the tool takes no arguments. |
| `extensionMethod` | `String` | VM Service extension registered in the running Flutter isolate (e.g. `ext.awesome.start`). Internal routing key; not included in the MCP wire shape. |

Example provider with commands and MCP tools:

```dart
import 'package:fluttersdk_artisan/artisan.dart';

final class AwesomePluginArtisanProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() => [
        AwesomeStartCommand(),
        AwesomeStopCommand(),
      ];

  @override
  List<McpToolDescriptor> mcpTools() => [
        McpToolDescriptor(
          name: 'awesome_start',
          description: 'Start the awesome service',
          inputSchema: {'type': 'object', 'properties': {}},
        ),
      ];
}
```

The example above omits `extensionMethod` for brevity. In production all four
fields are required; `extensionMethod` must match the `registerExtension` call
in the running Flutter isolate (e.g. `'ext.awesome.start'`).

The MCP server collects descriptors from all loaded providers when
`runArtisan(collectMcpTools: true)` fires (`bin/mcp.dart` sets this
automatically). Tool names must be unique; a collision throws
`ArtisanMcpToolCollisionException` at startup.

Naming convention: prefix every tool name with a short service identifier
followed by an underscore (`dusk_tap`, `telescope_tail`, `tinker_eval`).

---

## Publishing

1. Bump the version in `pubspec.yaml` following SemVer (patch for fixes, minor
   for new commands/tools, major for breaking provider API changes).

2. Declare the dependency on `fluttersdk_artisan` with a caret constraint, not
   `path:`:

   ```yaml
   dependencies:
     fluttersdk_artisan: ^0.0.1
   ```

3. Validate the archive before tagging:

   ```bash
   dart pub publish --dry-run
   ```

4. Add a CHANGELOG entry, then publish:

   ```bash
   dart pub publish
   ```

---

## Linking from Consumer

The consumer installs the plugin with:

```bash
dart run fluttersdk_artisan plugin:install awesome_plugin
```

This registers `AwesomeArtisanProvider.new` in `lib/app/_plugins.g.dart` and
re-generates the barrel; the provider is discovered at the next `artisan start`.
See [plugin:install](../commands/plugin-install.md) for the three routing modes
(manifest, canonical scaffold, legacy).

---

## Related

- [install-yaml.md](install-yaml.md) - `install.yaml` manifest schema for
  declaring install steps declaratively.
- [installer-dsl.md](installer-dsl.md) - `PluginInstaller` fluent DSL for
  authoring programmatic install logic.
- [make:plugin](../commands/make-plugin.md) - scaffold command reference with
  all flags and the generated file tree.
