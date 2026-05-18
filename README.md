<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Artisan Logo" />
</p>

<h1 align="center">Artisan</h1>

<p align="center">
  <strong>Symfony-Console-grade CLI framework for Dart and Flutter.</strong><br/>
  One <code>artisan</code> binary unifies every fluttersdk command surface: <code>make:*</code>, <code>plugin:*</code>, <code>dusk:*</code>, <code>telescope:*</code>, <code>tinker</code>, and any plugin you ship.
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluttersdk_artisan"><img src="https://img.shields.io/pub/v/fluttersdk_artisan.svg" alt="pub package"></a>
  <a href="https://github.com/fluttersdk/artisan/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/artisan/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/fluttersdk_artisan/score"><img src="https://img.shields.io/pub/points/fluttersdk_artisan" alt="pub points"></a>
  <a href="https://github.com/fluttersdk/artisan/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/artisan?style=flat" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://artisan.fluttersdk.com">Documentation</a> ·
  <a href="https://pub.dev/packages/fluttersdk_artisan">pub.dev</a> ·
  <a href="https://github.com/fluttersdk/artisan/issues">Issues</a>
</p>

---

> **Alpha Release**: Artisan is under active development. APIs may change before stable. [Star the repo](https://github.com/fluttersdk/artisan) to follow progress.

## Why Artisan?

Dart and Flutter ship a great runtime, but the developer surface is fragmented. Every project reinvents its own script directory: `bin/run.sh`, `bin/build.sh`, `bin/codegen.dart`. Generators live in scattered packages with conflicting conventions. Plugins (logging, analytics, auth) each invent their own install ritual.

**Artisan fixes this.** One `artisan` binary, one command grammar, one plugin protocol.

```bash
# Before: every package has its own incantation
dart run build_runner build
dart run melos run setup
flutter create --template=plugin foo && cd foo && sed -i 's/.../...' lib/foo.dart
dart pub global activate foo_cli && foo_cli init && foo_cli register

# After: one binary, one grammar
dart run magic:artisan make:plugin foo
cd packages/foo && dart run magic:artisan make:command Sync
dart run magic:artisan plugin:install foo
dart run magic:artisan foo:sync
```

If you know Laravel's Artisan or Symfony Console, you already know fluttersdk_artisan.

## Features

| | Feature | Description |
|:--|:--------|:------------|
| 🎼 | **Command Registry** | Type-safe `ArtisanRegistry`, auto-discovery via `_plugins.g.dart` codegen, collision detection on register |
| ✍️ | **Signature DSL** | Laravel-style `'cmd:name {arg} {arg?} {arg=default} {--flag} {--option=val}'` with help text inline |
| 🧰 | **19 Built-in Commands** | `make:plugin`, `make:command`, `plugin:install`, `plugin:uninstall`, `plugins:refresh`, `consumer:scaffold`, `tinker`, `doctor`, `start`/`stop`/`restart`/`logs`, `reload`/`hot-restart`, `help`, `list`, `mcp:serve`, `mcp:install`, `mcp:uninstall` |
| 🤖 | **MCP Server** | Single binary serves both CLI and MCP (Model Context Protocol). `mcp:install` writes a `.mcp.json` entry so any MCP-compatible client connects without extra setup. 11 V1 tools surfaced across Dusk, Telescope, and Tinker providers. Three-layer filter (file, env, CLI) controls which tools are exposed. |
| 🌳 | **Magic-Free Path** | `consumer:scaffold` writes the canonical `bin/artisan.dart` + `lib/app/_plugins.g.dart` + `lib/app/commands/_index.g.dart` for plain Flutter projects. `plugin:install` works without `install.yaml` once the scaffold is present (writes to `.artisan/plugins.json` + refreshes `_plugins.g.dart` directly) |
| 🔌 | **Plugin Protocol** | Declarative `install.yaml` manifest with `publish`, `magic.provider`, `native.*`, `prompts`, `bootstrap_command`. Procedural escape hatch via `ArtisanInstallCommand` |
| 🏗️ | **PluginInstaller DSL** | Fluent builder: `injectProvider`, `injectConfigFactory`, `injectRoute`, `publishConfig`, `injectAndroidPermission`, `injectIntoWebHead`, `injectEnvVar` |
| 🔄 | **Idempotent Installs** | `ConflictDetector` + atomic `.tmp` + rename writes; re-running `plugin:install` is a safe no-op |
| ↩️ | **Reversible Ops** | `InstallTransaction` records every op to `.artisan/installed/<plugin>.json`; `plugin:uninstall` reverses (V1 reverses `WriteFile`; manual reverse for inject ops) |
| 🪞 | **VM Service Hooks** | `tinker` REPL evaluates Dart expressions against a running Flutter app; `hot-restart` + `reload` drive `flutter run` via SIGUSR signals |
| 🎯 | **Context-Aware Generators** | `make:command` detects plugin vs consumer-app context, writes to the correct directory, auto-registers in the nearest `ArtisanServiceProvider` |
| 🧪 | **Testable Primitives** | `InMemoryFs` + `InstallContext.test()` + `BufferedOutput`. Every installer pathway is unit-testable without disk IO |

## Quick Start

Artisan is consumed in two roles: as a **CLI runner** (the `artisan` binary your consumer app calls) and as a **plugin authoring framework** (when you write a plugin that ships commands).

Two equivalent bootstrap paths land you in the same auto-discovery story:

### Path A: Plain Flutter (Magic-free)

For projects that do not want a framework dependency. Add only `fluttersdk_artisan`, then run `consumer:scaffold`.

```bash
flutter create my_app && cd my_app
```

```yaml
# pubspec.yaml
dependencies:
  fluttersdk_artisan:
    path: ../path/to/fluttersdk_artisan   # or pub.dev once published
```

```bash
flutter pub get
dart run fluttersdk_artisan consumer:scaffold
```

`consumer:scaffold` writes three canonical files (idempotent; pass `--force` to overwrite):

- `bin/artisan.dart`: thin wrapper that auto-discovers consumer commands from `lib/app/commands/_index.g.dart` AND plugin providers from `lib/app/_plugins.g.dart`. Zero manual edits required after every `make:command` / `plugin:install`.
- `lib/app/_plugins.g.dart`: empty plugin registry seed; populated by `plugin:install <name>`.
- `lib/app/commands/_index.g.dart`: empty consumer-command index; populated by `make:command <Name>`.

### Path B: Magic-managed (full framework)

For projects that want the Laravel-style Magic framework (Eloquent ORM, Facades, ServiceProviders) on top of Artisan.

```bash
flutter create my_app && cd my_app
```

```yaml
# pubspec.yaml
dependencies:
  magic:
    path: ../path/to/magic   # or pub.dev once published

dependency_overrides:
  fluttersdk_artisan:
    path: ../path/to/fluttersdk_artisan
```

```bash
flutter pub get
dart run magic:artisan magic:install
```

`magic:install` produces the same auto-discovery wiring as `consumer:scaffold` plus 10 magic configs, ServiceProviders, env files, and the `MagicApplication` runtime. The default Flutter counter app at `lib/main.dart` is auto-detected and silently overwritten by the ConflictDetector heuristic.

### Verify either path

```bash
dart run fluttersdk_artisan list   # Path A
dart run magic:artisan list        # Path B (also resolves to fluttersdk_artisan via the magic dep)
```

You should see the 16 built-in commands grouped by `:` namespace (`make:*`, `plugin:*`, `plugins:*`, `commands:*`, `consumer:*`, plus the unprefixed dev commands).

## The Recommended Plugin Flow

This is the validated end-to-end workflow for shipping a plugin that injects providers and contributes commands. The flow is identical in Path A (plain Flutter) and Path B (Magic); only the binary name differs (`fluttersdk_artisan` vs `magic:artisan`, both resolve to the same artisan runtime).

### Step 1: Scaffold the plugin

From the consumer app's root:

```bash
dart run fluttersdk_artisan make:plugin awesome_plugin     # Path A (plain Flutter)
dart run magic:artisan make:plugin awesome_plugin           # Path B (Magic-managed)
```

What this does:
- Runs `flutter create --template=package packages/awesome_plugin`
- Renders the generic plugin stubs (7 files: `pubspec.yaml`, `bin/awesome_plugin.dart`, `lib/cli.dart`, `lib/awesome_plugin.dart`, `lib/src/awesome_plugin_artisan_provider.dart`, `test/awesome_plugin_artisan_provider_test.dart`, `README.md`)
- In **magic mode** (auto-detected when `magic:install` is in the registry), adds 5 more stubs: `install.yaml` (declarative manifest), `lib/src/commands/{install,uninstall}_command.dart` (procedural escape hatches), `lib/src/awesome_plugin_service_provider.dart` (Magic ServiceProvider), `assets/stubs/install/awesome_plugin_config.dart.stub`, `lib/src/awesome_plugin_artisan_provider.dart` (with install/uninstall pre-registered)
- Enrolls the plugin into the parent app's `pubspec.yaml` `workspace:` list (Dart 3.6+ pub workspaces)
- Deletes the flutter-create-default `test/awesome_plugin_test.dart` to keep `flutter analyze` green out of the box

### Step 2: Add the plugin to the parent app's dependencies

Pub workspaces handle resolution, but the consumer needs an explicit `dependencies:` entry to import the package:

```yaml
# my_app/pubspec.yaml
dependencies:
  awesome_plugin:
    path: ./packages/awesome_plugin
```

```bash
flutter pub get
```

### Step 3: Add commands to the plugin

```bash
cd packages/awesome_plugin
dart run fluttersdk_artisan make:command Sync   # or magic:artisan
```

`make:command` is **context-aware**: when invoked inside a plugin (detected via `lib/src/*_artisan_provider.dart`), it:
- Writes the class to `lib/src/commands/sync_command.dart` (plugin convention, not the consumer `lib/app/commands/`)
- Generates `class SyncCommand extends ArtisanCommand` with idempotent suffix handling (`Sync` and `SyncCommand` both produce `SyncCommand`)
- Sets the signature to `awesome_plugin:sync` (auto-prefixed with the plugin name)
- Injects `import 'commands/sync_command.dart';` and `SyncCommand(),` into `AwesomePluginArtisanProvider.commands()` at the end of the list (idempotent, re-running is a safe no-op; falls back to inserting after the opening `<ArtisanCommand>[` when the list is empty)

Fill in the `handle()` body, then move on.

### Step 4: Install the plugin into the consumer

```bash
cd ../..   # back to my_app
dart run fluttersdk_artisan plugin:install awesome_plugin   # Path A
dart run magic:artisan plugin:install awesome_plugin         # Path B
```

What this does:
- **When `install.yaml` exists** (magic-mode plugin): reads the manifest, runs `ManifestInstaller` which publishes config files, injects providers into `lib/config/app.dart`, records the install at `.artisan/installed/<name>.json`. Then writes the plugin entry to `.artisan/plugins.json` and regenerates `lib/app/_plugins.g.dart`.
- **When `install.yaml` is absent** (generic plugin) AND `lib/app/_plugins.g.dart` exists (canonical scaffold from `consumer:scaffold` or `magic:install`): skips the manifest flow, writes the plugin entry directly to `.artisan/plugins.json`, and regenerates `_plugins.g.dart`. This is the Magic-free fast path.
- **When neither holds** (legacy consumer wrapper without canonical scaffold): falls back to the legacy `registry.registerProvider(...)` injection into `bin/artisan.dart` (anchored to the `auto.commands` line; documented at `doc/legacy-flow.md`).

After install, the consumer's `bin/artisan.dart` discovers `AwesomePluginArtisanProvider` via `_plugins.g.dart` and includes its commands in `list` on the next invocation.

### Step 5: Run the new command

```bash
dart run fluttersdk_artisan list                       # awesome_plugin:sync now visible (Path A)
dart run fluttersdk_artisan awesome_plugin:sync         # run from the consumer
```

Or via the consumer's own bin wrapper (created by `consumer:scaffold` / `magic:install`):

```bash
dart run my_app:artisan awesome_plugin:sync
```

Or from inside the plugin directory itself (each plugin ships its own bin):

```bash
cd packages/awesome_plugin
dart run awesome_plugin awesome_plugin:sync         # plugin's own bin/awesome_plugin.dart
```

That is the entire authoring loop. No manual provider edits, no manual registry edits, no manual `commands:refresh`. The recommended flow scales to dozens of plugins.

## Commands

### Consumer Setup

| Command | Description |
|---------|-------------|
| `consumer:scaffold` | Write the canonical native Flutter consumer wrapper: `bin/artisan.dart` + `lib/app/_plugins.g.dart` + `lib/app/commands/_index.g.dart`. Idempotent (pass `--force` to overwrite). Magic-managed consumers get the same wiring from `magic:install` and do not need this command. |

### Plugin Lifecycle

| Command | Description |
|---------|-------------|
| `make:plugin <name>` | Scaffold a new plugin package under `packages/<name>/`. Magic-mode add-ons (install.yaml + ServiceProvider + install/uninstall commands) included when `magic:install` is in the registry; otherwise generic 7-file scaffold (use `--path=<dir>` for a sibling location) |
| `plugin:install <name>` | Three routing modes: (1) `install.yaml` present → `ManifestInstaller` + `.artisan/plugins.json` + `_plugins.g.dart` refresh; (2) no manifest but `lib/app/_plugins.g.dart` exists → direct registry write + refresh (Magic-free fast path); (3) neither → legacy `bin/artisan.dart` injection |
| `plugin:uninstall <name>` | Reverse the recorded install ops (V1 reverses `WriteFile`; logs `[skipped]` for `InjectImport` and `InjectAfterPattern`) |
| `plugins:refresh` | Regenerate `lib/app/_plugins.g.dart` from `.artisan/plugins.json` (idempotent, byte-identical across runs) |

### Code Generators

| Command | Description |
|---------|-------------|
| `make:command <Name>` | Scaffold an `ArtisanCommand` subclass. Context-aware: writes to `lib/app/commands/` in consumer apps, `lib/src/commands/` in plugins (auto-registers in the nearest `ArtisanServiceProvider`) |
| `commands:refresh` | Regenerate the consumer's auto-discovery index for `lib/app/commands/` |

### Development Loop

| Command | Description |
|---------|-------------|
| `start [--device=<id>]` | Spawn `flutter run -d <device>` detached, record VM Service URI to `~/.artisan/state.json` |
| `stop` | SIGTERM the recorded `flutter run` process, delete `state.json` |
| `restart` | `stop` + `start` |
| `status` | Print the recorded process status as JSON |
| `logs [--follow]` | Print or tail the captured `flutter run` log |
| `reload` | Send `r` (hot reload) to the running `flutter run` stdin |
| `hot-restart` | Send `R` (hot restart). Drops Dart state, keeps process |

### Inspection

| Command | Description |
|---------|-------------|
| `tinker` | Connected REPL: evaluate Dart expressions against the running Flutter VM (Magic facade autocomplete, Eloquent model casting) |
| `doctor` | Preflight checks: `flutter` + `dart` on PATH, default port availability |
| `list` | Every registered command grouped by `:` namespace |
| `help <cmd>` | Detailed help for a single command |

### MCP Server

| Command | Description |
|---------|-------------|
| `mcp:serve [--include-tool <name>] [--exclude-tool <name>] [--include-package <pkg>] [--exclude-package <pkg>]` | Start the MCP server (stdio JSON-RPC). Merges three filter layers: `.artisan/mcp.json` (file), `ARTISAN_MCP_TOOLS_ALLOW` / `ARTISAN_MCP_TOOLS_DENY` / `ARTISAN_MCP_PACKAGES_ALLOW` / `ARTISAN_MCP_PACKAGES_DENY` (env), and CLI flags. Deny wins over allow at every layer. CLI flags are repeatable; CLI replaces env+file on the allow lists, deny lists from every layer union. |
| `mcp:install [--path <file>]` | Write (or update) the `fluttersdk` entry under `mcpServers` in `.mcp.json` (default: `.mcp.json` in cwd). Idempotent; preserves other server entries. |
| `mcp:uninstall [--path <file>]` | Remove the `fluttersdk` entry from `.mcp.json` (default: `.mcp.json` in cwd). |

## Command Signature DSL

Artisan parses Laravel-style signature strings into argument + option metadata. One line declares the full surface:

```dart
class SyncCommand extends ArtisanCommand {
  @override
  String get signature =>
      'awesome_plugin:sync '
      '{target : Team slug to sync} '         // required positional with help
      '{since? : Cutoff timestamp} '          // optional positional
      '{--limit=100 : Max records per page} ' // option with default
      '{--force : Skip confirmation prompt}'; // boolean flag

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final target = ctx.input.argument('target') as String;
    final since = ctx.input.argument('since') as String?;
    final limit = int.parse(ctx.input.option('limit') as String);
    final force = ctx.input.option('force') as bool;

    ctx.output.info('Syncing $target (limit=$limit, force=$force)');
    // ... your work ...
    ctx.output.success('Sync complete.');
    return 0;
  }
}
```

| Syntax | Meaning |
|--------|---------|
| `{name}` | Required positional argument |
| `{name?}` | Optional positional argument |
| `{name=default}` | Positional with default value |
| `{--flag}` | Boolean flag (presence sets `true`) |
| `{--opt=default}` | Option that accepts a value, with default |
| `{name : help text}` | Trailing colon provides help text shown by `help <cmd>` |

## install.yaml Manifest

The declarative manifest is the canonical install path. The procedural `<plugin>:install` command is an escape hatch for plugins that need runtime branching the YAML schema cannot express.

```yaml
# packages/awesome_plugin/install.yaml
plugin_name: awesome_plugin

publish:
  install/awesome_plugin_config.dart: lib/config/awesome_plugin.dart

magic:
  provider: AwesomePluginServiceProvider                    # injected into lib/config/app.dart
  configFactory: awesomePluginConfig                        # injected into lib/main.dart configFactories
  routes: AwesomePluginRoutes.register                      # registered in route provider

native:
  android:
    permissions:
      - android.permission.INTERNET
    metaData:
      io.flutter.embedding.android.SplashScreenDrawable: "@drawable/launch_background"
    gradle:
      plugins:
        - com.google.gms.google-services
      dependencies:
        - implementation 'com.google.firebase:firebase-bom:32.0.0'
  ios:
    plistEntries:
      NSCameraUsageDescription: "We need the camera for plugin features."
  web:
    headInjections:
      - <script src="https://example.com/awesome.js"></script>
    metaTags:
      - name: theme-color
        content: "#000000"

env:
  AWESOME_API_KEY:
    default: ""
    comment: "API key for Awesome Plugin"

prompts:
  - key: configPath
    type: string
    default: "~/.awesome.conf"
    question: "Configuration path?"

placeholders:
  configFilePath: "{{ prompts.configPath }}"

bootstrap_command: awesome_plugin:init
```

The schema is documented at `doc/install_yaml_schema.md`. Every section is optional except `plugin_name`.

## MCP Server

Artisan ships a built-in MCP (Model Context Protocol) server alongside the CLI. The same binary serves both surfaces: `mcp:serve` starts the JSON-RPC stdio server, and `mcp:install` writes the client config so any MCP-compatible host (Claude Desktop, Cursor, etc.) connects without extra setup.

### What it does

One binary, two surfaces: CLI commands and MCP tools share the same `ArtisanRegistry` and `ArtisanServiceProvider` plugin catalog. When `mcp:serve` starts, it scans all registered providers, collects their `mcpTools()` contributions, applies the active filter, and exposes the surviving tools to the MCP client.

### Installing the MCP entry

```bash
# Write the .mcp.json entry in the current directory (default: .mcp.json)
dart run artisan mcp:install

# Write to a different config path
dart run artisan mcp:install --path /path/to/.mcp.json

# Remove the entry
dart run artisan mcp:uninstall
```

`mcp:install` writes a JSON entry under the `mcpServers.fluttersdk` key of the target `.mcp.json` file. On subsequent runs the entry is updated in place (idempotent); other server entries are preserved untouched. After install, reconnect the client once: in Claude Desktop / Claude Code run `/mcp reconnect fluttersdk`.

### V1 Tool Catalog (11 tools)

Tools are contributed by provider. Every plugin that overrides `mcpTools()` in its `ArtisanServiceProvider` subclass adds to this list.

| Provider | Tool | Description |
|----------|------|-------------|
| `fluttersdk_dusk` | `dusk_snap` | Capture a Semantics YAML snapshot of the running Flutter app |
| `fluttersdk_dusk` | `dusk_tap` | Tap a widget by semantics label or test ID |
| `fluttersdk_dusk` | `dusk_screenshot` | Capture a PNG screenshot of the current screen |
| `fluttersdk_dusk` | `dusk_hover` | Hover over a widget (triggers hover state) |
| `fluttersdk_dusk` | `dusk_drag` | Drag from one point to another by coordinates |
| `fluttersdk_dusk` | `dusk_type` | Type text into the focused field |
| `fluttersdk_telescope` | `telescope_tail` | Stream the last N HTTP + log events from Telescope |
| `fluttersdk_telescope` | `telescope_requests` | List recorded HTTP requests with status + duration |
| `fluttersdk_telescope` | `telescope_clear` | Clear all recorded Telescope events |
| `fluttersdk_telescope` | `telescope_exceptions` | List recorded exceptions with stack traces |
| `magic_tinker` | `tinker_eval` | Evaluate a Dart expression against the live Flutter VM |

### Three-Layer Filter

Tools are filtered at three layers. Deny wins over allow at every layer. The layers apply in order: file (lowest priority) then env then CLI (highest priority). This matches Cargo-style resolution: the innermost (CLI) setting always wins.

| Layer | Mechanism | Example |
|-------|-----------|---------|
| File | `.artisan/mcp.json` `packages.deny` / `packages.allow` | Remove all Telescope tools without touching env |
| Env | `ARTISAN_MCP_TOOLS_DENY` / `ARTISAN_MCP_TOOLS_ALLOW` (comma-separated tool names) | Override file config in CI or per-session |
| CLI | `--exclude-tool <name>` / `--include-tool <name>` / `--include-package <pkg>` / `--exclude-package <pkg>` flags on `mcp:serve` (each repeatable) | One-shot override for a single server start |

**Example: remove Telescope tools via file, then override one tool via env, then exclude tinker_eval via CLI**

Step 1: create `.artisan/mcp.json` to deny all Telescope tools (removes 4 tools):

```json
{
  "packages": {
    "deny": ["fluttersdk_telescope"]
  }
}
```

Step 2: env override to also deny a specific Dusk tool, regardless of what the file says:

```bash
export ARTISAN_MCP_TOOLS_DENY=dusk_snap
```

Step 3: CLI flag for a one-shot session that additionally excludes `tinker_eval`:

```bash
dart run artisan mcp:serve --exclude-tool tinker_eval
```

Result: the running server exposes 5 tools (`dusk_tap`, `dusk_screenshot`, `dusk_hover`, `dusk_drag`, `dusk_type`). Deny at any layer is final: `dusk_snap` denied by env wins over any allow in the file; `tinker_eval` denied by CLI wins over everything.

### Reconnect Caveat

MCP clients cache the tool manifest at connect time. After changing `.artisan/mcp.json` or running `mcp:install`, reconnect the client to pick up the new tool list. In Claude Desktop: `/mcp reconnect fluttersdk`.

### Plugin Authoring: Contributing MCP Tools

Override `mcpTools()` in your `ArtisanServiceProvider` subclass to contribute tools to the MCP server. The default implementation returns an empty list, so existing providers need no changes.

```dart
class AwesomePluginArtisanProvider extends ArtisanServiceProvider {
  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
        McpToolDescriptor(
          name: 'awesome_ping',
          description: 'Ping the awesome service and return latency.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'url': <String, dynamic>{
                'type': 'string',
                'description': 'Target URL',
              },
            },
            'required': <String>['url'],
          },
          // The MCP server dispatches `awesome_ping` by calling this VM
          // Service extension on the running Flutter app. Register the
          // handler in your plugin's runtime via `registerExtension('ext.
          // awesome.ping', handler)` so the call lands in your app code.
          extensionMethod: 'ext.awesome.ping',
        ),
      ];
}
```

Tools contributed via `mcpTools()` are automatically discovered when the provider is registered. The three-layer filter applies to plugin-contributed tools the same way it applies to built-in tools.

## PluginInstaller DSL (Procedural Escape Hatch)

When the YAML manifest cannot express your install logic (runtime platform detection, env-specific branches, dynamic prompts), subclass `ArtisanInstallCommand` and drive `PluginInstaller` directly:

```dart
class CustomInstallCommand extends ArtisanInstallCommand {
  @override
  String get signature => 'awesome_plugin:install $baseFlags';

  @override
  String pluginName(ArtisanContext ctx) => 'awesome_plugin';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final installer = PluginInstaller(buildContext(ctx), pluginName: pluginName(ctx))
        .publishConfig(
          stubName: 'install/awesome_plugin_config.dart',
          targetPath: '${buildContext(ctx).projectRoot}/lib/config/awesome_plugin.dart',
        )
        .injectProvider('AwesomePluginServiceProvider')
        .injectConfigFactory('awesomePluginConfig')
        .injectAndroidPermission('android.permission.INTERNET')
        .injectEnvVar('AWESOME_API_KEY', defaultValue: '', comment: 'API key');

    if (Platform.isMacOS) {
      installer.injectAndroidGradlePlugin('com.google.gms.google-services');
    }

    final result = await installer.commit(dryRun: isDryRun(ctx), force: isForce(ctx));
    return switch (result) {
      Success() => 0,
      DryRun() => 0,
      Conflict() => 1,
      Error() => 2,
    };
  }
}
```

Every DSL call enqueues an `InstallOperation` to the transaction. `commit()` runs `ConflictDetector` against the planned ops, then atomically writes via `.tmp` + rename. Re-running the same command is a safe no-op thanks to the idempotency guards in `ConfigEditor.insertCodeAfterPattern` and `addImportToFile`.

## Programmatic API

Embed Artisan in your own bin script:

```dart
// bin/artisan.dart (consumer app)
import 'dart:io';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic/cli.dart' show MagicArtisanProvider;
import '../lib/app/_plugins.g.dart' as plugins;

Future<void> main(List<String> args) async {
  exit(await runArtisan(
    args,
    baseProviders: [
      MagicArtisanProvider(),
      ...plugins.autoDiscoveredProviders(),
    ],
    delegateToConsumer: false,
  ));
}
```

```dart
// bin/awesome_plugin.dart (plugin)
import 'dart:io';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:awesome_plugin/cli.dart' show AwesomePluginArtisanProvider;

Future<void> main(List<String> args) async {
  exit(await runArtisan(
    args,
    baseProviders: [AwesomePluginArtisanProvider()],
    delegateToConsumer: false,
  ));
}
```

`runArtisan` accepts `delegateToConsumer`. When true (default for the `magic:artisan` binary), it walks up looking for the consumer's wrapper and forwards execution so plugin contributions are included. Set false for self-contained plugin binaries that should not chain.

## Architecture

```
artisan <command> <args>
    ↓
ArtisanApplication.dispatch()
    ↓
ArtisanRegistry (collision-checked)
    ├─ baseProviders[]                    # injected at runtime
    └─ autoDiscoveredProviders()          # codegen from .artisan/plugins.json
    ↓
CommandSignature.parse() → ArtisanInput
    ↓
ArtisanContext { input, output, registry, fs, clock }
    ↓
command.handle(ctx) → int exit code
```

```
lib/src/
├── commands/          # 15 built-in commands (make:*, plugin:*, dev loop, tinker, doctor, list, help)
├── console/           # ArtisanApplication, ArtisanRegistry, CommandSignature, ArtisanContext, ArtisanInput, ArtisanOutput
├── installer/         # PluginInstaller, ManifestInstaller, InstallTransaction, ConflictDetector,
│                      # PluginsRegistryFile, VirtualFs, install_operation sealed hierarchy
├── stubs/             # StubLoader (asset + filesystem resolution)
├── helpers/           # FileHelper, ConfigEditor, MainDartEditor, EnvEditor, PlistWriter, StringHelper
├── extensions/        # String / Map extensions used across the framework
├── state/             # StateFile JSON state persistence for start/stop/status commands
├── tinker/            # REPL session + VM Service evaluation
└── vm/                # VmServiceClient (wraps package:vm_service for hot-reload, hot-restart, evaluate)
```

## Testing

Every installer primitive is unit-testable without disk IO via `InMemoryFs` and `InstallContext.test`:

```dart
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

test('injectProvider appends to the end of the providers list', () async {
  final fs = InMemoryFs();
  fs.writeAsString('/proj/lib/config/app.dart', _seedAppDart);

  final ctx = InstallContext.test(
    fs: fs,
    prompt: _SilentPromptDriver(),
    stubs: _SilentStubDriver(),
    projectRoot: '/proj',
  );

  final result = await PluginInstaller(ctx, pluginName: 'demo')
      .injectProvider('DemoServiceProvider')
      .commit(force: true);

  expect(result, isA<Success>());
  expect(fs.readAsString('/proj/lib/config/app.dart'),
      contains('(app) => DemoServiceProvider(app),'));
});
```

Real-FS integration tests use `Directory.systemTemp.createTempSync` for `make:plugin` and `plugin:install` end-to-end coverage. See `test/installer/plugin_installer_inject_test.dart` and `test/commands/plugin_install_command_test.dart` for the canonical patterns.

## AI Agent Integration

Use Artisan with AI coding assistants like Claude Code, Cursor, or GitHub Copilot. The **fluttersdk-artisan** skill teaches your AI the command signature DSL, plugin authoring conventions, install.yaml schema, `PluginInstaller` API, and the recommended `make:plugin` then `make:command` then `plugin:install` workflow, so it generates correct Artisan code on the first try.

Setup instructions and skill files: **[fluttersdk/ai](https://github.com/fluttersdk/ai)**

## Documentation

Full docs at **[artisan.fluttersdk.com](https://artisan.fluttersdk.com)**.

| Topic | |
|-------|--|
| [Quick Start](https://artisan.fluttersdk.com/getting-started/quick-start) | Setup and the recommended plugin flow |
| [Command Signature DSL](https://artisan.fluttersdk.com/basics/signature-dsl) | Argument and option syntax |
| [Plugin Authoring](https://artisan.fluttersdk.com/plugin-authoring/overview) | Manifest schema, DSL, lifecycle |
| [install.yaml Schema](https://artisan.fluttersdk.com/plugin-authoring/install-yaml) | Every section + every key |
| [PluginInstaller DSL](https://artisan.fluttersdk.com/plugin-authoring/plugin-installer) | Procedural escape hatch reference |
| [ConflictDetector](https://artisan.fluttersdk.com/internals/conflict-detector) | Atomic write semantics + scaffold detection |
| [VM Service Hooks](https://artisan.fluttersdk.com/internals/vm-service) | `tinker`, `reload`, `hot-restart` mechanics |

## Contributing

```bash
git clone https://github.com/fluttersdk/artisan.git
cd artisan && dart pub get
dart test && dart analyze
```

[Report a bug](https://github.com/fluttersdk/artisan/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/fluttersdk/artisan/issues/new?template=feature_request.yml)

## License

MIT, see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a></sub><br/>
  <sub>If Artisan saves you time, <a href="https://github.com/fluttersdk/artisan">give it a star</a>. It helps others discover it.</sub>
</p>
