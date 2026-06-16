# Commands

Catalog of every user-facing command shipped by `fluttersdk_artisan`. Twenty-one commands, grouped by intent.

Every command is invoked as `dart run fluttersdk_artisan <name>` (or via the consumer wrapper `dart run artisan <name>` once the project has run `install` or `magic:install`). Commands are auto-discovered through the registered providers list; nothing wires by hand.

Need a quick reminder of what a command does without leaving the terminal? Run `dart run artisan list` for the full registry grouped by namespace, or `dart run artisan help <name>` for the per-command flag surface. This page exists for the deeper view: the boot mode, the MCP exposure, and the grouping rationale.

## Table of contents

- [Lifecycle](#lifecycle)
- [Scaffolding](#scaffolding)
- [Plugin management](#plugin-management)
- [MCP](#mcp)
- [Introspection](#introspection)
- [Code generation](#code-generation)
- [Featured deep-dives](#featured-deep-dives)

## How to read this page

Each group section ships a single table with four columns:

- **Command** is the canonical name you type after `dart run fluttersdk_artisan` (or `dart run artisan`).
- **Description** is the one-line summary returned by the command's `description` getter; the same string surfaces in `dart run artisan list`.
- **Boot Mode** is the `CommandBoot` value the dispatcher reads before invoking `handle()` (see `lib/src/console/command_boot.dart`). `none` means pure CLI: no Flutter binding, no VM Service connection. `connected` means the command dials `~/.artisan/state.json` and fails fast if no app is running.
- **MCP Tool** is the canonical `artisan_*` tool name surfaced over stdio JSON-RPC by `mcp:serve`, or the literal `no` when the command is not in the substrate allowlist. The allowlist lives in `lib/src/mcp/mcp_server.dart` (`_safeArtisanCommandNames`) and intentionally omits interactive, codegen, installer, and MCP-meta commands.

## Naming conventions

Two shapes appear in the catalog:

- Single verb (`start`, `stop`, `status`, `logs`, `restart`, `reload`, `doctor`, `tinker`, `help`, `list`) for top-level actions on the substrate.
- Namespaced `<group>:<verb>` (`make:plugin`, `make:command`, `install`, `plugin:install`, `plugin:uninstall`, `plugins:refresh`, `mcp:serve`, `mcp:install`, `mcp:uninstall`, `commands:refresh`, `hot-restart`) for actions scoped to a subsystem.

The `hot-restart` command is the one outlier: it lives in the lifecycle group but uses a hyphen instead of a colon, mirroring the `R` keypress sent to `flutter run`.

## Lifecycle

Seven commands that own the running Flutter process: spawn, stop, query, tail, restart, reload, hot-restart. All run pure CLI; none of them boot Flutter or Magic in the artisan process. State is shared via `~/.artisan/state.json`, written by `start` and consumed by everything that needs the VM Service URI.

These seven are the only commands surfaced as MCP tools today, which makes them the agent-facing surface area of the substrate.

| Command | Description | Boot Mode | MCP Tool |
|---------|-------------|-----------|----------|
| `start` | Boot `flutter run -d <device>` detached and record the VM Service URI to `~/.artisan/state.json`. | none | artisan_start |
| `stop` | Stop the running flutter app and delete `~/.artisan/state.json`. | none | artisan_stop |
| `status` | Print JSON status of the recorded flutter app. | none | artisan_status |
| `logs` | Print or `--follow` the captured flutter run log. | none | artisan_logs |
| `restart` | Stop and start the running flutter app; preserves the prior session's `--cdp-port`. | none | artisan_restart |
| `reload` | Hot reload the running app (sends `r` to flutter run's stdin). State preserved. | none | artisan_reload |
| `hot-restart` | Hot restart the running app (sends `R` to flutter run's stdin). Drops Dart state, keeps process. | none | artisan_hot_restart |

## Scaffolding

Four commands that write source files into the consumer project. They are deliberately excluded from the MCP allowlist: source mutation is better routed through the client's own file tools, and the stub system uses placeholder substitution (`{{ name }}`, `{{ pascalName }}`, `{{ commandPrefix }}`) that benefits from interactive prompts.

| Command | Description | Boot Mode | MCP Tool |
|---------|-------------|-----------|----------|
| `make:plugin` | Scaffold a new fluttersdk_artisan plugin skeleton. | none | no |
| `make:command` | Scaffold a new ArtisanCommand subclass under `lib/app/commands/` (or `lib/src/commands/` when run inside a plugin). | none | no |
| `make:fast-cli` | Scaffold the POSIX `bin/fsa` wrapper and pre-compile the AOT cache under `.artisan/cli-bundle/` for ~50ms startup. | none | no |
| `install` | Scaffold the canonical native Flutter consumer wrapper (`bin/dispatcher.dart` plus `lib/app/_plugins.g.dart` plus `lib/app/commands/_index.g.dart`) and chain `make:fast-cli` in-process. | none | no |

## Plugin management

Three commands that maintain the `.artisan/plugins.json` registry and its generated barrel `lib/app/_plugins.g.dart`. Atomic writes (`.tmp` plus rename) across every mutation, so concurrent readers (editors, lint daemons) never observe partial state. `plugin:install` routes through three modes (manifest, magic-free fast path, legacy injection) depending on what the consumer project already has.

| Command | Description | Boot Mode | MCP Tool |
|---------|-------------|-----------|----------|
| `plugin:install` | Register a third-party artisan plugin (`install.yaml` manifest preferred; legacy `bin/artisan.dart` injection as fallback). | none | no |
| `plugin:uninstall` | Uninstall a third-party artisan plugin (reverses the manifest and removes the `bin/artisan.dart` registration). | none | no |
| `plugins:refresh` | Regenerate `lib/app/_plugins.g.dart` from `.artisan/plugins.json` registry. | none | no |

## MCP

Three commands that wire the fluttersdk MCP server into a host like Claude Code, Cursor, or Windsurf, plus the server entry itself. The `mcp:*` meta commands recurse into the server and are intentionally excluded from the allowlist. Per-tool visibility is configured via `.artisan/mcp.json`, environment variables, and CLI flags (the three layers compose Cargo-style: file plus env plus flags, with deny rules always winning).

| Command | Description | Boot Mode | MCP Tool |
|---------|-------------|-----------|----------|
| `mcp:serve` | Run the fluttersdk MCP server (stdio JSON-RPC) for Claude Code, Cursor, Windsurf. | none | no |
| `mcp:install` | Add the fluttersdk MCP server entry to `.mcp.json` (idempotent; preserves other server entries). | none | no |
| `mcp:uninstall` | Remove the fluttersdk MCP server entry from `.mcp.json` (preserves other entries). | none | no |

## Introspection

Four commands that observe the substrate or its host. `tinker` is the only command in the catalog with `CommandBoot.connected`: it dials the running app's VM Service and is interactive, so it stays out of the MCP allowlist.

| Command | Description | Boot Mode | MCP Tool |
|---------|-------------|-----------|----------|
| `help` | Show detailed help for a single command. | none | no |
| `list` | List every registered command grouped by namespace. | none | artisan_list |
| `doctor` | Run environment preflight checks (flutter, dart, port availability). | none | artisan_doctor |
| `tinker` | Connected REPL into the running Flutter app (Dart expression evaluation via VM Service). | connected | artisan_tinker |

## Code generation

One command that rewrites the `lib/app/commands/_index.g.dart` barrel. Codegen sits in its own bucket because the consumer rarely runs it by hand: `make:command` and `plugin:install` invoke it as a follow-up step. The generated barrel is never edited manually; the source of truth is the set of `*_command.dart` files under `lib/app/commands/`.

| Command | Description | Boot Mode | MCP Tool |
|---------|-------------|-----------|----------|
| `commands:refresh` | Rescan `lib/app/commands/` and rewrite the auto-discovery index. | none | no |

## Boot mode at a glance

Twenty of twenty-one commands run with `CommandBoot.none`. Only `tinker` is `CommandBoot.connected`, because its job is to evaluate Dart expressions against a live VM Service isolate. Everything else (lifecycle commands included) shells out to `flutter run` or operates on disk; the artisan process itself never depends on a Flutter binding.

This separation is what lets the substrate ship as a pure-Dart package: the consumer wrapper supplies the optional Magic / Flutter context, while the framework itself stays runtime-free.

A third boot mode, `headless`, is reserved for a V1.x release that will let Magic-bound commands (think `migrate`, `db:seed`) boot just enough of the host to read `Magic.Config` without spinning up a UI.

## Featured deep-dives

Six commands earn their own pages because their flags, modes, or composition rules outgrow a single table row:

- [start](start)
- [plugin:install](plugin-install)
- [mcp:serve](mcp-serve)
- [make:plugin](make-plugin)
- [install](install)
- [tinker](tinker)

Slug rule: the deep-dive URL drops the `:` separator in favor of `-`, so `plugin:install` lives at `commands/plugin-install/` and `mcp:serve` at `commands/mcp-serve/`. The remaining fifteen commands share this index page; reach for `dart run artisan help <name>` for their full flag surface.
