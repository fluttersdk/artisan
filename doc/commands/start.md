# start

- [Basic Usage](#basic-usage)
- [Synopsis](#synopsis)
- [Options](#options)
- [Behavior](#behavior)
- [State File](#state-file)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Related](#related)

The `start` command spawns `flutter run` as a detached background process, scrapes the VM Service URI from its output, and writes `~/.artisan/state.json` so that every downstream tool (MCP server, `stop`, `restart`, `dusk:snap`, `tinker`, etc.) knows where the running app lives.

<a name="basic-usage"></a>
## Basic Usage

```bash
dart run artisan start
```

Launches a Chrome web dev session on port `3100` with the VM Service listener on port `8181`. The command exits as soon as the URI is confirmed; the Flutter process continues running in the background.

<a name="synopsis"></a>
## Synopsis

```
dart run artisan start [--device=<target>] [--port=<n>] [--vm-service-port=<n>]
                       [--[no-]dds] [--[no-]profile-static]
```

`start` accepts no positional arguments. All configuration is done via named options and flags declared in `configure(ArgParser)` (see `lib/src/commands/start_command.dart:38`).

<a name="options"></a>
## Options

| Option | Type | Default | Description |
|:-------|:-----|:--------|:------------|
| `--device` | string | `chrome` | Flutter device target. Accepts `chrome`, `macos`, `linux`, `windows`, an iOS UDID, or an Android serial number. |
| `--port` | int | `3100` | Web server port passed as `--web-port` to `flutter run`. Ignored for non-Chrome targets. |
| `--vm-service-port` | int | `8181` | VM Service listener port. Recorded in `state.json`; used by `mcp:serve` and connected-mode tools to open the WebSocket. |
| `--dds` | flag | `false` | Enable Dart Development Service. When absent (default), `--no-dds` is forwarded to `flutter run` so dusk and tinker connect directly to the VM Service. |
| `--profile-static` | flag | `false` | Tag the session as a static-profile run. Sets `profile: "static"` in `state.json`; otherwise `"debug"`. |

<a name="behavior"></a>
## Behavior

**FIFO stdin channel.** Before launching Flutter, `start` calls `mkfifo` to create a named pipe at `~/.artisan/flutter-dev.fifo`. A background `tail -f /dev/null` process holds the write end of the FIFO open permanently, preventing `flutter run`'s stdin from receiving EOF when no keystroke sender is active. `flutter run` is then launched with the FIFO as its stdin, so the `reload` and `hot-restart` commands can send `r` or `R` into the pipe and trigger flutter_tools' own handler. This approach works on every device target (web, desktop, mobile) because it routes through `flutter_tools` rather than raw VM Service RPCs, which the Chrome `dwds` bridge rejects.

**Detached spawn and URI scrape.** The shell one-liner run by `start` launches both background processes (`tail` holder and `flutter run`) and echoes their PIDs in `HOLDER=<n>` / `FLUTTER=<n>` format. `start` captures those PIDs from the wrapper's stdout, then polls the log file at `~/.artisan/flutter-dev.log` every 250 ms until it finds a line matching either the web format (`Debug service listening on ws://...`) or the desktop/mobile format (`Dart VM Service on <Platform> is available at: http://...`). `http://` and `https://` URIs are normalized to their `ws://` and `wss://` equivalents and a `/ws` suffix is appended when missing.

**State file write.** After the URI is confirmed, `start` writes `~/.artisan/state.json` atomically (`.tmp` + rename) with the full process inventory: PIDs, FIFO path, VM Service URI, web port, device target, profile mode, project root, and a UTC `startedAt` timestamp. The MCP server (`mcp:serve`) reads this file at startup to discover the running app; `stop` reads it to send SIGTERM; `status` reads it to report the live process.

<a name="state-file"></a>
## State File

`start` writes `~/.artisan/state.json` atomically after a successful spawn. The schema (from `lib/src/state/state_file.dart:13-24`):

```json
{
  "pid": 12345,
  "stdinPipe": "/Users/you/.artisan/flutter-dev.fifo",
  "stdinHolderPid": 12344,
  "vmServiceUri": "ws://127.0.0.1:8181/AbCdEfGhIjK=/ws",
  "webPort": 3100,
  "vmServicePort": 8181,
  "startedAt": "2026-05-19T10:00:00.000Z",
  "profile": "debug",
  "projectRoot": "/Users/you/Code/my-app",
  "device": "chrome",
  "chromePid": null,
  "tmpProfileDir": null
}
```

Field reference:

| Field | Type | Notes |
|:------|:-----|:------|
| `pid` | int | PID of the `flutter run` process. Used by `stop` to send SIGTERM. |
| `stdinPipe` | string | Absolute path to the FIFO. `reload` and `hot-restart` write `r\n` / `R\n` here. |
| `stdinHolderPid` | int | PID of the `tail -f /dev/null` holder that keeps the FIFO write-end open. Killed alongside `pid` by `stop`. |
| `vmServiceUri` | string | Canonical `ws://host:port/<token>/ws` URI. All connected-mode tools open this WebSocket. |
| `webPort` | int | `--web-port` value forwarded to Flutter. Chrome only; ignored for other targets. |
| `vmServicePort` | int | Informational; the port embedded in `vmServiceUri`. |
| `startedAt` | string | ISO 8601 UTC timestamp of the `start` invocation. |
| `profile` | string | `"debug"` or `"static"` (set by `--profile-static`). |
| `projectRoot` | string | Absolute path to the working directory at invocation time. |
| `device` | string | The `--device` value passed to this run. |
| `chromePid` | int or null | Reserved for D6 Chrome capture (V1.x). Always `null` in V1. |
| `tmpProfileDir` | string or null | Reserved for D6 Chrome capture (V1.x). Always `null` in V1. |

<a name="examples"></a>
## Examples

**Chrome web session (default):**

```bash
dart run artisan start
```

Equivalent to `dart run artisan start --device=chrome --port=3100 --vm-service-port=8181`.

**macOS desktop session:**

```bash
dart run artisan start --device=macos
```

`--port` is ignored for non-Chrome targets. Flutter receives `--no-dds` (the default) so the Dusk and Tinker tools connect directly to the VM Service socket.

**Custom web port with DDS enabled:**

```bash
dart run artisan start --device=chrome --port=4000 --dds
```

Starts the Chrome session on port `4000` and omits `--no-dds`, letting the Dart Development Service run. Use this when your tooling requires DDS (for example, a secondary IDE debugger).

<a name="troubleshooting"></a>
## Troubleshooting

**Port already in use (`--port` collision).** If another process holds the web port, `flutter run` exits immediately and the log file shows `Error: Address already in use`. Pick a free port with `--port=<n>` or stop the occupying process with `lsof -ti:<port> | xargs kill`.

**`mkfifo` permission denied.** `start` creates the FIFO at `~/.artisan/flutter-dev.fifo`. If `~/.artisan/` was created by a previous run with different ownership or mode bits, `mkfifo` fails. Fix with `rm -rf ~/.artisan && dart run artisan start`. Note: `start` is POSIX-only (macOS/Linux). It will not work on Windows.

**VM Service URI never appears (90-second timeout).** If `flutter run` stalls before printing the URI (for example, the Chrome binary is missing, the Flutter SDK is not on `PATH`, or a Dart compilation error occurs), `start` throws `StateError: Timed out after 90s...`. Inspect the log at `~/.artisan/flutter-dev.log` for the underlying Flutter output. Common causes: wrong `--device` value, missing `CHROME_EXECUTABLE` env var for headless environments, or a syntax error in the app's entry point.

<a name="related"></a>
## Related

- [stop](index.md): send SIGTERM to the running Flutter process and delete `state.json`.
- [restart](index.md): full stop + start cycle; preserves the prior session's `--cdp-port` (read from `state.json` before `stop` deletes it, then forwarded into `start`). An explicit `--cdp-port` on the `restart` invocation wins.
- [reload](index.md): send `r\n` to the FIFO for a hot reload without a full restart.
- [hot-restart](index.md): send `R\n` to the FIFO for a hot restart that resets app state.
- [mcp:serve](mcp-serve.md): start the stdio JSON-RPC MCP server; reads `~/.artisan/state.json` to discover the running app.
