# MCP Integration Overview

<a name="toc"></a>

- [What is MCP](#what-is-mcp)
- [Why MCP in artisan](#why-mcp-in-artisan)
- [10 Substrate Tools](#substrate-tools)
- [Plugin-Contributed Tools](#plugin-contributed-tools)
- [State File Contract](#state-file-contract)
- [Architecture Diagram](#architecture-diagram)
- [Related](#related)

---

<a name="what-is-mcp"></a>

## What is MCP

The [Model Context Protocol](https://modelcontextprotocol.io) (MCP) is an open standard that defines
how AI clients (Claude Code, Cursor, Windsurf, and similar) discover and invoke tools exposed by a
local or remote server over a JSON-RPC transport. A client connects once, calls `initialize` to
receive the full tool catalog, and then invokes individual tools by name. The server handles routing,
argument validation, and error formatting, returning structured content the client model can reason
over. MCP decouples the tool surface (what the agent can do) from the tool implementation (how it is
done), so the same server can serve multiple AI clients without code duplication.

---

<a name="why-mcp-in-artisan"></a>

## Why MCP in artisan

LLM agents working on Flutter codebases traditionally had one interaction mode: read source files and
shell out to CLI commands. That works for static analysis and compilation, but it breaks down the
moment the agent needs to observe or control a *running* Flutter application. Capturing a Semantics
snapshot, tailing HTTP traffic, evaluating an expression in the live isolate, or hot-reloading after
a code change all require a live connection to the Dart VM Service. Passing raw VM Service WebSocket
URIs and protocol bytes through shell commands is fragile and opaque.

artisan's MCP integration solves this by surfacing the running Flutter app's capabilities as
first-class MCP tools. The agent calls `artisan_start` to launch the app, `artisan_reload` to push a
hot reload, and plugin-contributed tools to snap the widget tree or tail HTTP requests, all without
copy-pasting commands or parsing raw output. The MCP server handles VM Service discovery, lazy
reconnect across stop-restart cycles, and structured error formatting so the model can self-correct.

---

<a name="substrate-tools"></a>

## 10 Substrate Tools

The MCP server always registers the following ten tools, derived from the artisan CLI's built-in
command set. Tool names are normalized from `cmd:name` to `cmd_name` so they satisfy the MCP
identifier constraint (`[a-zA-Z][a-zA-Z0-9_]*`). These tools run in-process via the artisan
registry; nine of them require no VM Service connection (so `artisan_start` works even before any
Flutter app is running), while `artisan_tinker` dispatches over the VM Service and lazy-reconnects
on first call.

| Tool | Maps to CLI command | Purpose |
|---|---|---|
| `artisan_start` | `start` | Launch the Flutter app via `flutter run` and write `state.json` |
| `artisan_stop` | `stop` | Send SIGTERM to the running Flutter process and delete `state.json` |
| `artisan_status` | `status` | Read `state.json` and return the current process metadata as JSON |
| `artisan_logs` | `logs` | Stream the most recent stdout lines captured from `flutter run` |
| `artisan_restart` | `restart` | Full restart (equivalent to `R` in the flutter run TTY) |
| `artisan_reload` | `reload` | Hot reload the running app without losing widget state |
| `artisan_hot_restart` | `hot-restart` | Hot restart the running app, resetting ephemeral state |
| `artisan_doctor` | `doctor` | Run `flutter doctor` and return the diagnostics report |
| `artisan_list` | `list` | List all registered artisan commands with their signatures |
| `artisan_tinker` | `tinker` | Evaluate Dart expression in running app via VM Service. Maps to: tinker command. Requires running app (artisan_start first). |

Commands intentionally excluded from the MCP allowlist: interactive commands (`help`),
codegen commands (`make:*`, `*:refresh`), installer commands (`plugin:*`, `install`), and
MCP meta commands (`mcp:*`). They either require a TTY, mutate source files better handled by the
client's own file tools, or recurse into the MCP server itself.

---

<a name="plugin-contributed-tools"></a>

## Plugin-Contributed Tools

Beyond the ten substrate tools, plugins extend the MCP catalog by overriding
`ArtisanServiceProvider.mcpTools()`. The default implementation returns an empty list; plugins return
a list of `McpToolDescriptor` instances that the MCP server collects at initialize time and registers
alongside the substrate tools. The same `McpFilterConfig` allow/deny rules apply uniformly, so a
deny rule against a plugin tool name works identically to `tools.deny: [artisan_start]`.

Plugin tools dispatch through the VM Service (not in-process), so they require a running Flutter app.
The MCP server lazy-reconnects on each dispatch call, meaning the agent can call `artisan_start`
first and the very next plugin tool call picks up the new app automatically.

**Plugin registration is explicit.** The consumer's `bin/artisan.dart` wrapper must list each
provider in its `artisanProviders` factory list. There is no auto-discovery of plugin providers in
V1: the `bin/mcp.dart` entry point loads only the substrate commands. Consumers register their
providers once in the wrapper and the MCP server inherits them from the shared registry.

The two sibling packages that ship production plugin tools are:

| Package | MCP tool reference |
|---|---|
| `fluttersdk_dusk` | [fluttersdk.com/dusk/mcp/tool-reference](https://fluttersdk.com/dusk/mcp/tool-reference) |
| `fluttersdk_telescope` | [fluttersdk.com/telescope/mcp/tool-reference](https://fluttersdk.com/telescope/mcp/tool-reference) |

Each package's provider is wired by the consumer (`DuskArtisanProvider`, `TelescopeArtisanProvider`)
registered in the wrapper's `artisanProviders` list. See the per-package CLAUDE.md for registration
details and each plugin's tool reference site for the current tool catalog. `magic_tinker` remains
the CLI REPL host for `dart run artisan tinker`, but its MCP surface is now the substrate's
`artisan_tinker`.

---

<a name="state-file-contract"></a>

## State File Contract

`artisan start` writes a single JSON file at `~/.artisan/state.json` (the path is machine-local and
user-scoped). The MCP server reads this file during `initialize` to discover the running Flutter
app's VM Service WebSocket URI. If the file is absent or lacks a `vmServiceUri` key, the server
stays online and registers all tools, but VM Service dispatch calls return an actionable error until
the app is started.

The state file is a single-slot store: starting a second app overwrites the previous record. It is
never committed to version control (`.gitignore` / `.pubignore` exclude `.artisan/`).

Fields (from `lib/src/state/state_file.dart`):

| Field | Type | Notes |
|---|---|---|
| `pid` | `int` | PID of the `flutter run` process |
| `vmServiceUri` | `string` | Canonical `ws://host:port/<token>/ws` used for VM Service connection |
| `webPort` | `int` | `--web-port` value passed to `flutter run` |
| `vmServicePort` | `int` | Informational; defaults to 8181 |
| `startedAt` | `string` | ISO 8601 UTC timestamp |
| `profile` | `string` | `debug` or `static` |
| `projectRoot` | `string` | Absolute path to the consumer project |
| `device` | `string` | `chrome`, `macos`, `linux`, `windows`, or a device UDID |
| `chromePid` | `int` or `null` | Chrome process PID when `--device=chrome` (D6 capture) |
| `tmpProfileDir` | `string` or `null` | Temp Chrome profile directory path (D6 capture) |

---

<a name="architecture-diagram"></a>

## Architecture Diagram

```
  Claude Code (MCP client)
        |
        | stdio JSON-RPC  (initialize / tools/call)
        |
  dart run fluttersdk_artisan:mcp
        |
   McpServer (mcp:serve)
        |
        +-- substrate tools (artisan_start, artisan_stop, ...)
        |         |
        |         v
        |   ArtisanRegistry  (in-process command dispatch)
        |
        +-- plugin tools (dusk_*, telescope_*) + artisan_tinker
                  |
                  | VM Service WebSocket
                  | ws://localhost:PORT/<token>/ws
                  |
             VmServiceClient
                  |
                  | ext.dusk.* / ext.telescope.* / VM evaluate RPC
                  |
          Flutter app isolate (debug mode)
                  |
          +-------+-------+
          |               |
  DuskIntegration   TelescopeIntegration
  (widget tree)     (HTTP + logs + exceptions)
```

**Flow summary:**

1. The MCP client (Claude Code) connects to the server over stdio and calls `initialize`.
2. `McpServer` reads `~/.artisan/state.json` and opens a VM Service WebSocket to the running Flutter
   app.
3. All registered tools become available to the client model.
4. Substrate tool calls (prefix `artisan:`) route in-process through `ArtisanRegistry` without VM
   Service involvement, so `artisan_start` works even when no app is running.
5. Plugin tool calls dispatch through `VmServiceClient.callServiceExtension`, reaching the Flutter
   app's registered extension handlers in the debug isolate.
6. Results return as `CallToolResult` text content; errors carry `isError: true` with an actionable
   message so the model can self-correct without a human in the loop.

---

<a name="related"></a>

## Related

- [Setup guide](setup.md): install the MCP server, configure `.artisan/mcp.json`, and wire provider
  registration in `bin/artisan.dart`.
- [Tool reference](tool-reference.md): per-tool input schema, example calls, and error codes for all
  ten substrate tools, plus links to each plugin's own MCP tool reference site.
