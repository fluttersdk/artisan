# MCP Tool Reference

Catalog of every MCP tool surfaced by `fluttersdk_artisan` and its sibling plugin packages.
The MCP server exposes **10 substrate tools** (always available) and up to **26 plugin tools**
(available when the matching provider is registered in the consumer's `bin/artisan.dart`).
Total when all plugins are active: **36 tools**.

## Table of Contents

- [Tool Naming Convention](#tool-naming-convention)
- [Substrate Tools](#substrate-tools)
  - [artisan_start](#artisan_start)
  - [artisan_stop](#artisan_stop)
  - [artisan_status](#artisan_status)
  - [artisan_logs](#artisan_logs)
  - [artisan_restart](#artisan_restart)
  - [artisan_reload](#artisan_reload)
  - [artisan_hot_restart](#artisan_hot_restart)
  - [artisan_doctor](#artisan_doctor)
  - [artisan_list](#artisan_list)
  - [artisan_tinker](#artisan_tinker)
- [Plugin Tools](#plugin-tools)
  - [fluttersdk_dusk (17 tools)](#fluttersdk_dusk-17-tools)
  - [fluttersdk_telescope (9 tools)](#fluttersdk_telescope-9-tools)
- [Filter Configuration](#filter-configuration)
- [Related](#related)

---

## Tool Naming Convention

### Substrate tools

Substrate tools are built-in artisan commands exposed by `McpServer` directly. Their names
follow the pattern `artisan_<command>` where the artisan command name is transformed:

- `:` (namespace separator) becomes `_`
- `-` (word separator) becomes `_`

Examples: `start` maps to `artisan_start`; `hot-restart` maps to `artisan_hot_restart`.

### Plugin tools

Plugin tools are contributed via `ArtisanServiceProvider.mcpTools()`. Each plugin package
owns a prefix that matches the package name or domain:

| Plugin package | Tool prefix | Example |
|---|---|---|
| `fluttersdk_dusk` | `dusk_` | `dusk_snap` |
| `fluttersdk_telescope` | `telescope_` | `telescope_tail` |

The same `:` and `-` transformation applies inside the suffix part (e.g. `wait_for`,
`navigate_back`, `close_app`).

### Exclusions from the allowlist

Interactive (`help`), codegen (`make:*`, `*:refresh`), installer (`plugin:*`,
`consumer:scaffold`), and MCP meta (`mcp:*`) commands are intentionally excluded. They
either require a TTY, mutate source on disk (better served by the client's own file tools),
or recurse into the MCP server itself. `tinker` was previously excluded as interactive but
is now absorbed into the substrate as `artisan_tinker` (the `--eval` one-shot path drives
the MCP surface).

---

## Substrate Tools

The 10 substrate tools are always present when the MCP server starts. They are served
in-process: the server builds a `MapInput` from the MCP arguments, runs the artisan command
via `BufferedOutput`, and returns the combined stdout + exit code as MCP text content.

### artisan_start

Maps to artisan command: `start`

Starts the Flutter app in debug mode and records the process PID and VM Service URI in
`~/.artisan/state.json`. Once the state file exists the plugin tools (dusk, telescope,
tinker) can connect to the running VM.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `device` | string | first available | Flutter device id. Common values: `chrome` (web), `macos` (desktop), `<adb-serial>` (Android), or any id from `flutter devices`. |
| `port` | string | `3100` | Web port for the chrome device (numeric string). Ignored for non-web devices. |
| `vm-service-port` | string | `8181` | Port the VM Service binds to on the host. Change when 8181 is already taken. |
| `dds` | boolean | `false` | Enable the Dart Development Service (DDS) proxy. Set `true` when a tool requires DDS-only features. |
| `profile-static` | boolean | `false` | Run Flutter in `--profile` mode (release-like performance, no hot reload). |

### artisan_stop

Maps to artisan command: `stop`

Sends `SIGTERM` to the recorded Flutter process and deletes `~/.artisan/state.json`. After
this call, plugin tools will fail until `artisan_start` is called again.

No parameters.

### artisan_status

Maps to artisan command: `status`

Reads `~/.artisan/state.json` and returns the current process state as JSON: PID, device,
VM Service URI, start timestamp, and whether the process is still alive.

No parameters.

### artisan_logs

Maps to artisan command: `logs`

Returns buffered stdout/stderr lines produced by the Flutter process since it started. Use
this to see compilation errors, framework warnings, and `print()` output from the app.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `follow` | boolean | `false` | When `true`, tail the live log stream until the client disconnects (`-f` on the CLI). When `false`, return the most recent buffered lines and exit immediately. |

### artisan_restart

Maps to artisan command: `restart`

Sends a full restart signal to the running Flutter process via the VM Service. Equivalent to
pressing `R` in the flutter run terminal. All widget state is destroyed; static state in Dart
globals persists.

No parameters.

### artisan_reload

Maps to artisan command: `reload`

Sends a hot reload signal to the running Flutter process via the VM Service. Equivalent to
pressing `r` in the flutter run terminal. Updates code in place; widget state is preserved.
Faster than `artisan_restart` but does not pick up changes to `initState` or constructor
bodies.

No parameters.

### artisan_hot_restart

Maps to artisan command: `hot-restart`

Alias for the hot-restart cycle: tears down the widget tree and rebuilds from `main()` while
keeping the Dart VM alive. Faster than a full process restart; slower than hot reload. Use
when hot reload cannot pick up the change (e.g. changes to `StatefulWidget.createState`,
`didChangeDependencies`, or provider boot logic).

No parameters.

### artisan_doctor

Maps to artisan command: `doctor`

Checks the artisan environment: Flutter SDK on `PATH`, `flutter devices` reachability,
state file presence, and VM Service connectivity. Returns a summary report with per-check
status (OK / WARNING / ERROR). Run this first when plugin tools fail unexpectedly.

No parameters.

### artisan_list

Maps to artisan command: `list`

Lists every registered artisan command with its signature and description. Output mirrors
`dart run artisan list`. Useful for discovering commands contributed by plugin providers
registered in the consumer's `bin/artisan.dart`.

No parameters.

### artisan_tinker

Maps to artisan command: `tinker`

Evaluate a Dart expression inside the running Flutter app via the VM Service evaluate RPC.
Takes required `eval` argument (Dart expression). Returns the formatted evaluation result
as text. Dispatch follows the same lazy-reconnect path as plugin VM-extension tools; the
expression runs in the foreground isolate's root library scope and is passed through the
`Tinker.casters` chain before return.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `eval` | string | (required) | Dart expression to evaluate in the running app's root library (e.g. `User.current.name`, `MonitorController.instance.refresh()`, `1+1`). Runs synchronously in the foreground isolate; the formatted result returns as text. |

---

## Plugin Tools

Plugin tools are contributed by sibling packages via `ArtisanServiceProvider.mcpTools()`.
They surface in the MCP server only when the corresponding provider is registered in the
consumer's `bin/artisan.dart` and `dart run fluttersdk_artisan:mcp` is restarted.

Each plugin tool dispatches over a `ext.<domain>.*` VM Service extension registered by the
plugin inside the running Flutter app.

---

### fluttersdk_dusk (17 tools)

E2E interaction driver. All dusk tools operate over `ext.dusk.*` VM Service extensions
installed by `fluttersdk_dusk` inside the running app. Refs (`e<N>`) come from
`dusk_snap`; handles (`q<N>`) come from `dusk_find`.

| Tool | Extension method | Required parameters | Description |
|---|---|---|---|
| `dusk_snap` | `ext.dusk.snap` | none | Capture a YAML snapshot of the Semantics tree. Returns stable `[ref=eN]` tokens used by all action tools. |
| `dusk_tap` | `ext.dusk.tap` | `ref` | Tap a widget by ref token (Down + 50ms + Up). |
| `dusk_screenshot` | `ext.dusk.screenshot` | none | Capture a base64-encoded JPEG or PNG of the current frame. |
| `dusk_hover` | `ext.dusk.hover` | `ref` | Hover a mouse cursor over a widget (mouse/desktop only). |
| `dusk_drag` | `ext.dusk.drag` | `startRef`, `endRef` | Drag from one widget center to another (Down + 5x Move + Up). |
| `dusk_type` | `ext.dusk.type` | `ref`, `text` | Type text into a focused TextField. Replaces existing content. |
| `dusk_scroll` | `ext.dusk.scroll` | `ref` | Scroll the nearest Scrollable ancestor of the widget. Optional: `direction` (`up`/`down`/`left`/`right`, default `down`), `pixels` (default 300). |
| `dusk_wait_for` | `ext.dusk.wait_for` | one of `text`, `textGone`, `expression` | Poll until a UI condition is met or `timeoutMs` (default 5000) expires. |
| `dusk_dismiss_modals` | `ext.dusk.dismiss_modals` | none | Pop every modal route (dialog, bottom sheet) above the first persistent route. Idempotent. |
| `dusk_navigate` | `ext.dusk.navigate` | `route` | Push a named route path onto the active router. Always re-snap after navigation. |
| `dusk_navigate_back` | `ext.dusk.navigate_back` | none | Pop the top route off the navigator stack (equivalent to system Back). |
| `dusk_get_routes` | `ext.dusk.get_routes` | none | List route paths declared by the running app's router (`{ path, name }` records). |
| `dusk_press_key` | `ext.dusk.press_key` | `key` | Synthesize a hardware key event. Optional: `modifiers` array (`control`, `shift`, `alt`, `meta`). |
| `dusk_select_option` | `ext.dusk.select_option` | `ref`, `value` | Select an option in a DropdownButton by ref + value string. |
| `dusk_evaluate` | `ext.dusk.evaluate` | `expression` | Evaluate a Dart expression via the Tinker bridge (MCP-only; no CLI equivalent). |
| `dusk_close_app` | `ext.dusk.close_app` | none | Request a graceful shutdown via `SystemNavigator.pop()`. No-op on web. |
| `dusk_find` | `ext.dusk.find` | at least one of `text`, `semanticsLabel`, `key` | Mint a re-resolvable `q<N>` handle backed by predicates. Survives widget rebuilds unlike `e<N>` snap refs. |

---

### fluttersdk_telescope (9 tools)

Runtime inspector. All telescope tools read ring buffers populated by `ext.telescope.*`
VM Service extensions installed by `fluttersdk_telescope` inside the running app.

| Tool | Extension method | Required parameters | Description |
|---|---|---|---|
| `telescope_tail` | `ext.telescope.console` | none | Return recent `package:logging` log records. Optional: `level` (minimum level filter), `limit` (max records, newest first). |
| `telescope_requests` | `ext.telescope.requests` | none | Return recent HTTP request records (method, url, status, duration, body snippet). Optional: `limit`. |
| `telescope_clear` | `ext.telescope.clear` | none | Clear all three ring buffers (logs, requests, exceptions) atomically. Idempotent. |
| `telescope_exceptions` | `ext.telescope.exceptions` | none | Return recent uncaught exception records (type, message, stackTrace). Optional: `limit`. |
| `telescope_events` | `ext.telescope.events` | none | Return recent Magic `Event.dispatch()` records (class name, payload snapshot). Optional: `limit`. |
| `telescope_gates` | `ext.telescope.gates` | none | Return recent `Gate.allows / Gate.denies` check records (ability, result, user id). Optional: `limit`. |
| `telescope_dumps` | `ext.telescope.dumps` | none | Return recent `debugPrint()` output records captured by the global override. Optional: `limit`. |
| `telescope_queries` | `ext.telescope.queries` | none | Return recent Magic QueryBuilder SQL records (SQL, bindings, execution time). Optional: `limit`. |
| `telescope_caches` | `ext.telescope.caches` | none | Return recent Magic Cache operation records (`hit`, `miss`, `put`, `forget`, `flush`). Optional: `limit`. |

---

### Tinker (absorbed into the substrate)

The connected REPL is no longer a plugin tool: it ships as the substrate's
`artisan_tinker` (see above). `magic_tinker` is still consumed by the host app for the
interactive REPL CLI (`dart run artisan tinker`), but its MCP surface has been removed
to avoid duplicating the substrate path. Use `artisan_tinker` from any MCP client for
live state inspection, controller calls, or facade events; for widget tree inspection
prefer `dusk_snap`; for log output prefer `telescope_tail`.

---

## Filter Configuration

The MCP server applies a three-layer filter (file, then env vars, then CLI flags) to
control which plugin tools surface. Each layer uses Cargo-style replacement for allow lists
and union for deny lists.

### Precedence rules

- **Allow lists**: CLI replaces env, which replaces file. A non-null allow list at a higher
  layer REPLACES the lower layer entirely. Null means "no opinion at this layer."
- **Deny lists**: union of all three layers. A tool denied in any layer stays denied.
- **Deny wins over allow**: when a name appears in both the effective allow set and the
  effective deny set, the deny wins.

### Layer 1: `.artisan/mcp.json`

Place this file in the project root (next to `bin/artisan.dart`):

```json
{
  "packages": {
    "allow": null,
    "deny": []
  },
  "tools": {
    "allow": null,
    "deny": []
  }
}
```

Field reference:

| Key | Type | Meaning |
|---|---|---|
| `packages.allow` | `null` or `string[]` | `null` = allow all packages; array = allow only named packages |
| `packages.deny` | `string[]` | Package names always excluded (wins over allow) |
| `tools.allow` | `null` or `string[]` | `null` = allow all tool names; array = allow only named tools |
| `tools.deny` | `string[]` | Tool names always excluded (wins over allow) |

Package names match `ArtisanServiceProvider.providerName`: `fluttersdk_artisan` (substrate),
`fluttersdk_dusk`, `fluttersdk_telescope`. Tool names match `McpToolDescriptor.name` exactly
(e.g. `dusk_snap`, `telescope_tail`, `artisan_tinker`).

### Layer 2: environment variables

| Variable | Effect |
|---|---|
| `ARTISAN_MCP_PACKAGES_ALLOW` | CSV of package names to allow |
| `ARTISAN_MCP_PACKAGES_DENY` | CSV of package names to deny |
| `ARTISAN_MCP_TOOLS_ALLOW` | CSV of tool names to allow |
| `ARTISAN_MCP_TOOLS_DENY` | CSV of tool names to deny |

### Layer 3: CLI flags

Pass flags directly to `dart run fluttersdk_artisan:mcp`:

```bash
dart run fluttersdk_artisan:mcp \
  --include-package=fluttersdk_dusk \
  --exclude-tool=dusk_close_app \
  --exclude-tool=dusk_evaluate
```

CLI flags replace the env + file allow lists and are unioned into the deny sets.

**Example: expose dusk tools only**
`{ "packages": { "allow": ["fluttersdk_dusk"], "deny": [] }, "tools": { "allow": null, "deny": [] } }`

**Example: hide destructive tools**
`{ "packages": { "allow": null, "deny": [] }, "tools": { "allow": null, "deny": ["dusk_close_app", "artisan_stop"] } }`

---

## Related

- [MCP Overview](overview.md): architecture, transport, and server entry points
- [MCP Setup](setup.md): consumer registration, `.mcp.json`, and first-run checklist
