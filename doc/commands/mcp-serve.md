# mcp:serve

Start the fluttersdk MCP server over stdio JSON-RPC, exposing substrate and
plugin-contributed tools to AI clients such as Claude Code, Cursor, and Windsurf.

**Contents**

- [Basic Usage](#basic-usage)
- [Synopsis](#synopsis)
- [Soft-Fail Behavior](#soft-fail-behavior)
- [3-Layer Filter](#3-layer-filter)
- [Tools Surfaced](#tools-surfaced)
- [Examples](#examples)
- [Related](#related)

---

## Basic Usage

```bash
./bin/fsa mcp:serve
```

The server opens a stdio JSON-RPC channel, registers every tool that passes the
active filter, and blocks until the MCP client disconnects. Exit code is `0` on a
clean disconnect, `1` on a startup `StateError`.

In normal usage the AI client launches the server automatically from your `.mcp.json`
entry. The form above uses the fast-compiled binary; the standalone fallback is useful for debugging:

```bash
dart run :dispatcher mcp:serve
```

---

## Synopsis

```
./bin/fsa mcp:serve [--include-package <package_name>]... [--exclude-package <package_name>]... [--include-tool <tool_name>]... [--exclude-tool <tool_name>]...
```

or, when `bin/fsa` is absent or on Windows:

```
dart run :dispatcher mcp:serve [--include-package <package_name>]... [--exclude-package <package_name>]... [--include-tool <tool_name>]... [--exclude-tool <tool_name>]...
```

All four flags are **repeatable**. Each can also be set via environment variable or
`.artisan/mcp.json` (see [3-Layer Filter](#3-layer-filter)).

| Flag | Effect |
|---|---|
| `--include-package <name>` | Accept only tools from the named package. CLI value replaces env and file allow lists for the package axis. |
| `--exclude-package <name>` | Block all tools from the named package. Deny wins over allow across every layer. |
| `--include-tool <name>` | Accept only the named tool. CLI value replaces env and file allow lists for the tool axis. |
| `--exclude-tool <name>` | Block the named tool. Deny wins over allow across every layer. |

---

## Soft-Fail Behavior

The server does **not** require a running Flutter app at startup. When
`~/.artisan/state.json` is absent or contains no `vmServiceUri`, initialization
completes normally: all tools register and the server stays online
(source: `mcp_server.dart:137-149`).

Tool calls that need the VM Service attempt a **lazy reconnect** on first
invocation (source: `mcp_server.dart:228-256`):

- Dispatch checks whether `_vmClient` is null.
- If null, a single shared in-flight future reads `~/.artisan/state.json`,
  connects the WebSocket, and captures the main isolate ID.
- Concurrent calls that arrive during the reconnect await the same future,
  preventing a client-leak race.
- On failure, dispatch returns `isError: true` with an actionable message:
  `Run artisan start to launch the Flutter app, then retry the tool call.`
- The guard clears in `finally` so the next call retries cleanly.

**Note:** the server does NOT auto-reload filter configuration in V1. After editing
`.artisan/mcp.json` or any `ARTISAN_MCP_*` env var, run `/mcp reconnect fluttersdk`
in Claude Code (or restart the server process in other clients) to apply the change.

---

## 3-Layer Filter

Tool visibility is controlled by three layers using **Cargo-style precedence**
(source: `mcp_filter_config.dart:97-235`):

| Layer | Source | Priority |
|---|---|---|
| File | `.artisan/mcp.json` in project root | Lowest |
| Env | `ARTISAN_MCP_*` environment variables | Middle |
| CLI | `--include-*` / `--exclude-*` flags | Highest |

**Allow lists (replace):** a non-null value at a higher layer replaces the lower
layer entirely for that axis. Resolution: `cli.allow ?? env.allow ?? file.allow`.
Null at all three layers means "include all".

**Deny lists (union):** the union of all three layers. A name denied at any layer
is denied in the result; deny always wins over allow.

### File layer

```json
{
  "packages": { "allow": null, "deny": ["fluttersdk_telescope"] },
  "tools":    { "allow": ["artisan_start", "artisan_tinker"], "deny": [] }
}
```

An absent file is treated as "no opinion" (all tools pass).

### Env layer

| Variable | Axis |
|---|---|
| `ARTISAN_MCP_PACKAGES_ALLOW` | Package allow list (CSV) |
| `ARTISAN_MCP_PACKAGES_DENY` | Package deny list (CSV) |
| `ARTISAN_MCP_TOOLS_ALLOW` | Tool allow list (CSV) |
| `ARTISAN_MCP_TOOLS_DENY` | Tool deny list (CSV) |

### CLI layer

Pass each `--include-*` / `--exclude-*` flag multiple times to accumulate entries.
A non-empty `--include-*` replaces the env and file allow list for that axis.

---

## Tools Surfaced

At initialize time the server merges two tool sets, then applies the active filter.

**Substrate tools (10):** run in-process via the artisan command registry. Nine work
without a running Flutter app; `artisan_tinker` dispatches over the VM Service and
lazy-reconnects on first call. Their filter package name is `fluttersdk_artisan`.

| MCP Tool Name | Artisan Command |
|---|---|
| `artisan_start` | `start` |
| `artisan_stop` | `stop` |
| `artisan_status` | `status` |
| `artisan_logs` | `logs` |
| `artisan_restart` | `restart` |
| `artisan_reload` | `reload` |
| `artisan_hot_restart` | `hot-restart` |
| `artisan_doctor` | `doctor` |
| `artisan_list` | `list` |
| `artisan_tinker` | `tinker` |

Excluded from the substrate allowlist: `help`, `make:*`, `*:refresh`, `mcp:*`,
`plugin:*`, `install`. These require a TTY, mutate source on disk, or
recurse into the server itself (source: `mcp_server.dart:744-755`).

**Plugin tools:** contributed via `ArtisanServiceProvider.mcpTools()` on each
registered provider. The default returns an empty list. Providers such as
`DuskArtisanProvider` and `TelescopeArtisanProvider` override it to expose tools that
dispatch over the VM Service extension surface and require a running Flutter app. Both
sets flow through the same filter, so a `--exclude-tool` deny against a plugin tool name
behaves identically to a deny against a substrate name. The current plugin tool catalogs
live on each plugin's own MCP tool reference site
([fluttersdk_dusk](https://fluttersdk.com/dusk/mcp/tool-reference),
[fluttersdk_telescope](https://fluttersdk.com/telescope/mcp/tool-reference)).

---

## Examples

### 1. Filter via file: allow only specific packages

```json
{
  "packages": { "allow": ["fluttersdk_artisan", "fluttersdk_dusk"], "deny": [] },
  "tools":    { "allow": null, "deny": [] }
}
```

```bash
./bin/fsa mcp:serve
```

Only substrate and Dusk tools register. Telescope is excluded because its package is
not in the allow list.

### 2. Filter via env vars: deny specific tools

```bash
export ARTISAN_MCP_PACKAGES_DENY="fluttersdk_telescope"
./bin/fsa mcp:serve
```

All Telescope tools are excluded; all others remain available. The env deny is
UNIONed with any deny entries already in `.artisan/mcp.json`.

### 3. Filter via CLI flags: pin to a minimal tool set

```bash
./bin/fsa mcp:serve \
  --include-tool artisan_start \
  --include-tool artisan_stop \
  --include-tool artisan_tinker
```

Only the three named tools register. Any `tools.allow` in `.artisan/mcp.json` or
`ARTISAN_MCP_TOOLS_ALLOW` is ignored for this invocation (CLI replaces).

---

## Related

- [mcp:install](index.md): write or update the `.mcp.json` client entry.
- [mcp:uninstall](index.md): remove the `fluttersdk` entry from `.mcp.json`.
- [MCP setup guide](../mcp/setup.md): end-to-end wiring for Claude Code, Cursor, Windsurf.
- [MCP tool reference](../mcp/tool-reference.md): full parameter and return value
  reference for every substrate and plugin tool.
