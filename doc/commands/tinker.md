# tinker

Connected REPL into the running Flutter app. Evaluates Dart expressions via the
VM Service protocol and pretty-prints the result. Requires the app to be running
before invoking (see [start](start)).

## Table of contents

- [Basic Usage](#basic-usage)
- [Synopsis](#synopsis)
- [Connected Mode](#connected-mode)
- [Two Modes](#two-modes)
- [Examples](#examples)
- [VM Service Evaluate](#vm-service-evaluate)
- [MCP Surface](#mcp-surface)
- [Related](#related)

---

## Basic Usage

```bash
dart run fluttersdk_artisan tinker
```

Drops you into an interactive read-eval-print loop connected to the running Flutter
app. Type any Dart expression at the `>>>` prompt and press Enter. Press Ctrl+D
or type `exit` / `quit` to end the session.

```bash
dart run artisan tinker        # via consumer wrapper (same effect)
```

---

## Synopsis

```
tinker {--eval=expr}
```

| Option | Description |
|--------|-------------|
| `--eval=<expr>` | Evaluate a single Dart expression and exit. REPL is skipped. |

---

## Connected Mode

`tinker` sets `CommandBoot.connected` as its boot mode. Before `handle` runs, the
dispatcher reads `~/.artisan/state.json` (written by `start`) and dials the VM
Service WebSocket URI recorded there. If no state file is present, or the app
is not running, the command exits with an error.

Prerequisite: the Flutter app must be running via `dart run fluttersdk_artisan start`
(or the consumer wrapper equivalent) before any `tinker` invocation. The `status`
command reports whether a state file is present and what VM Service URI it holds.

---

## Two Modes

### REPL (default)

When `--eval` is not provided, `tinker` enters an interactive read-eval-print loop:

1. Prints `Tinker connected. Type expressions; Ctrl+D to exit.`
2. Displays a `>>>` prompt and reads one line at a time from stdin.
3. Evaluates the line in the running app's root library via VM Service.
4. Formats the result through the `Tinker.casters` chain and prints it.
5. Repeats until stdin closes (Ctrl+D) or the user types `exit` or `quit`.

The session prints `Tinker session ended.` on exit.

### `--eval` (one-shot)

When `--eval=<expr>` is supplied, `tinker` evaluates the expression once, writes
the formatted result to stdout, and exits immediately. No prompt or session messages
are printed. Exit code is `0` on success, `1` on evaluation error. This mode is
pipe-friendly: scripts and pipelines can capture the output without filtering out
interactive chatter.

```bash
dart run artisan tinker --eval "1+1"   # prints: 2
echo $?                                 # 0
```

---

## Examples

```bash
# Interactive REPL session
dart run artisan tinker
# >>> Magic.find<MonitorController>().rxState.value
# MonitorState{...}
# >>> Ctrl+D
# Tinker session ended.

# One-shot eval (pipe-friendly)
dart run artisan tinker --eval "DateTime.now().toIso8601String()"
# 2026-05-19T10:30:00.000Z
```

---

## VM Service Evaluate

Expression evaluation routes through `VmServiceClient.evaluate`, which opens a
WebSocket to the DDS endpoint recorded in `~/.artisan/state.json`. On each
evaluation, the client calls `getVM()` for a fresh isolate ID (no cache, so
device-target switches and app restarts do not produce stale isolate references),
then resolves the isolate's root library ID and delegates to the VM Service
`evaluate` RPC. Expressions containing `await` are automatically wrapped in an
async IIFE (`(() async => <expr>)()`) so callers do not need to reason about
await-awareness. The `InstanceRef` response is unwrapped and passed through the
`Tinker.casters` chain for pretty-printing before it reaches stdout.

---

## MCP Surface

artisan ships `artisan_tinker` as a substrate MCP tool. When `mcp:serve` runs, any MCP
client (Claude Code, Cursor, Windsurf, etc.) can call `artisan_tinker` with an `eval`
argument to evaluate Dart in the running app. This is the same evaluation path as
`dart run fluttersdk_artisan tinker --eval "..."` but accessible to AI agents over
stdio JSON-RPC; the dispatcher uses the same lazy-reconnect to the VM Service that
the CLI form uses, and the result returns as MCP text content.

See [mcp:serve](mcp-serve) and the [MCP tool reference](../mcp/tool-reference.md) for
the full input schema, filter precedence, and the substrate vs plugin separation.

---

## Related

- [start](start): boot the Flutter app and write the VM Service URI to the state file.
- [status](status): confirm the app is running and inspect the recorded state.
