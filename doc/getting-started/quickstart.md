# Quickstart

A 5-step walkthrough taking a fresh Dart or Flutter project from zero to a working
artisan setup with a plugin installed and a custom command registered.

Prerequisites: Dart 3.4+ SDK, a Flutter project with a valid `pubspec.yaml`, and
`flutter pub get` already run so `.dart_tool/package_config.json` is present.

---

### 1. Install and scaffold

Add `fluttersdk_artisan` to your project dependencies, then run `install`
to write the canonical wrapper files. The scaffold is idempotent: re-running it when
the files already exist is a safe no-op (pass `--force` to overwrite).

```bash
dart pub add fluttersdk_artisan
dart run fluttersdk_artisan install
```

The scaffold writes three files:

- `bin/dispatcher.dart`: the CLI entry point you will invoke for every subsequent
  `dart run :dispatcher` call (or `./bin/fsa <cmd>` once the AOT bundle is built).
- `lib/app/_plugins.g.dart`: codegen barrel that wires registered plugin providers
  into the consumer wrapper automatically.
- `lib/app/commands/_index.g.dart`: codegen barrel that auto-discovers commands
  under `lib/app/commands/` so `dart run artisan list` picks them up without
  manual registration.

After scaffolding, all subsequent commands run via `dart run artisan` (the consumer
wrapper), not via `dart run fluttersdk_artisan` directly.

---

### 2. Add a custom command

Generate a command scaffold under `lib/app/commands/`. The name argument is
normalized: `HelloWorld` becomes class `HelloWorldCommand` with signature
`hello-world`. The codegen barrel is refreshed automatically so the command appears
on the next `artisan list` without an extra step.

```bash
dart run fluttersdk_artisan make:command HelloWorld
```

The generator creates `lib/app/commands/hello_world_command.dart` with a skeleton
`handle` method and a pre-filled `signature` string. Edit the file to implement
your command logic, then run `dart run artisan hello-world` to invoke it.

If you are authoring a plugin (a `lib/src/<name>_artisan_provider.dart` exists at
the project root) the generator writes to `lib/src/commands/` instead and injects
the import and registration line into the provider file automatically.

---

### 3. Install a plugin

Add the plugin package to your `pubspec.yaml` and resolve it, then register it with
the consumer wrapper via `plugin:install`. The command runs a three-stage resolution:

1. When the plugin ships an `install.yaml` manifest, the manifest flow runs: ops are
   parsed, conflict-checked, and committed atomically, then the plugin's
   `ArtisanServiceProvider` is registered in `.artisan/plugins.json` and
   `lib/app/_plugins.g.dart` is refreshed.
2. When no manifest is found but the canonical scaffold (`lib/app/_plugins.g.dart`)
   is present, registration writes directly to `.artisan/plugins.json` and refreshes
   the codegen barrel (no `bin/dispatcher.dart` edit needed).
3. When neither condition is met, the legacy fallback appends an import and a
   `registerProvider(...)` call to `bin/artisan.dart` directly.

```bash
dart pub add awesome_plugin
dart run fluttersdk_artisan plugin:install awesome_plugin
```

After installation the plugin's commands appear in `dart run artisan list` under the
plugin's own namespace. Pass `--dry-run` to preview every write operation before it
commits. Pass `--use-yaml-only` to error out instead of falling back when no
`install.yaml` is found.

---

### 4. Start a Flutter app (optional)

If your project ships a Flutter app, `start` boots `flutter run` in a detached
process and writes `~/.artisan/state.json` with the VM Service URI. The state file
is what lets MCP clients and hot-reload/hot-restart commands locate the running
instance without you providing the URI each time.

```bash
dart run fluttersdk_artisan start --device=chrome
```

The default target is `chrome`. Pass `--device=macos` (or any Flutter device
identifier) for desktop or mobile targets. The command scrapes the VM Service URI
from the flutter run output, normalizes it to a `ws://` WebSocket address, and
writes the full state (PID, VM URI, web port, device, project root) to
`~/.artisan/state.json`.

Once the state file is present, `reload`, `hot-restart`, `logs`, and `stop` all
resolve the running process automatically from the file without extra flags.

---

### 5. List everything wired

Verify the full command registry by running `list`. The output is grouped by `:`
namespace so built-in commands, your custom commands, and plugin-contributed commands
each appear in their own section.

```bash
dart run fluttersdk_artisan list
```

A clean setup shows the 21 built-in commands (under namespaces `consumer`, `make`,
`plugin`, `plugins`, `commands`, `mcp`, and a few root-level commands including
`start`, `stop`, `status`, `logs`, `restart`, `reload`, `hot-restart`, `doctor`,
`list`) plus your `hello-world` command under the root namespace (or under
`awesome_plugin:` if the plugin contributed commands).

---

## What's next?

- Browse the full [command catalog](../commands/) to see what each builtin does.
- Wire the MCP server into your AI client via [MCP setup](../mcp/setup).
- Write your own plugin via the [plugin authoring guide](../plugins/authoring).

---

All five commands shown above are part of the `fluttersdk_artisan` built-in command
set and require no additional packages beyond the initial `dart pub add` in step 1.
Plugin commands contributed by third-party packages appear in `artisan list` under
their own namespace after `plugin:install` completes.
