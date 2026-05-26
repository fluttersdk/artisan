# tinker_eval (artisan_tinker) deep reference

`artisan_tinker { eval: "<expr>" }` evaluates a Dart expression inside
the running Flutter app's main isolate via the VM Service `evaluate`
RPC. This file teaches the agent the constraints, the auto-await
wrapper, the four error paths, the scope rules, and a recipe pack
tuned for Magic-stack apps.

The handler is `lib/src/commands/tinker_command.dart:35`. The VM
client is `lib/src/vm/vm_service_client.dart`. The MCP dispatch path is
`lib/src/mcp/mcp_server.dart:794-820`.

## Wire model

```
MCP client (Claude Code)
  -> tools/call { name: "artisan_tinker", arguments: { eval: "<expr>" } }
       -> McpServer._dispatchArtisanCommand
            -> ArtisanContext.connected (lazy-reconnect if _vmClient == null)
                 -> TinkerCommand.handle(ctx)
                      -> ctx.evaluate(<expr>)
                           -> VmServiceClient.evaluate(isolateId, <expr>)
                                -> vm.getIsolate(isolateId)        # fetch fresh isolate
                                -> wrap if "await" in expr         # (() async => expr)()
                                -> vm.evaluate(isolateId, rootLibId, <wrapped>)
                                     -> InstanceRef | ErrorRef
                                <- result
                           <- formatInstanceRef(result)
                      <- text
                 <- CallToolResult
       <- json-rpc response
```

`getMainIsolateId()` calls `getVM()` on every dispatch (no isolate-id
cache), so device-target switches and hot restarts are transparent.

## Expression grammar (what `evaluate` accepts)

The VM Service `evaluate` RPC compiles a single Dart EXPRESSION. The
grammar does not accept:

| Construct | Result |
|---|---|
| Trailing `;` | `RPCError(code: 113)` compile error |
| Multi-statement block (`a; b;`) | compile error |
| `import 'dart:math';` | compile error (not parsable in expression context) |
| Top-level `var x = 1;` | compile error |
| Function definition (`void foo() {}`) | compile error |
| Class definition | compile error |
| Bare `await` | compile error WITHOUT auto-wrap (see below) |

The grammar accepts:

| Construct | Notes |
|---|---|
| Primitive expression (`1 + 1`, `'hello'`, `true`) | Returns `Instance` with `valueAsString`. |
| Top-level symbol access (`Magic`, `Config`, `User`) | Resolved against the root library scope. |
| Method call (`Foo.bar()`, `instance.method()`) | Returns the method's return value as `InstanceRef`. |
| Async expression with `await` | artisan auto-wraps in `(() async => <expr>)()` when the source contains `await`. |
| Cascade (`obj..method()`) | Allowed; returns the receiver. |
| Comma operator (`a, b`) | Allowed; returns the rightmost value. Useful for void side-effects. |
| Conditional expression (`a ? b : c`) | Allowed. |
| Collection literal (`[1, 2, 3]`, `{1: 'a'}`) | Returns the collection. |
| Closure invocation (`(() => 1)()`) | Allowed. The IIFE pattern is how artisan handles `await`. |

## The `await` auto-wrap

`lib/src/vm/vm_service_client.dart:155-157`:

```dart
final wrapped = expression.contains('await')
    ? '(() async => $expression)()'
    : expression;
```

This means:

```
eval: "await Magic.find<MonitorController>().refresh()"
       ↓
wrapped: "(() async => await Magic.find<MonitorController>().refresh())()"
       ↓
returned: Future<void> instance reference
```

`vm_service.evaluate()` returns the `Future` instance; artisan's
`VmServiceClient.evaluate` returns the `vm.Response` after the future
settles. The agent's tool result is the resolved value.

Caveats:

- The wrap fires on the SUBSTRING `await`, even inside string literals.
  This is usually fine, but `eval: "'no await here'"` would also be
  wrapped. Wrap is idempotent (an already-async IIFE re-wrapped is
  still valid), so it does not break.
- The closure has no positional or named arguments; you cannot pass in
  values. Use the host scope's identifiers directly.

## Scope rules

- **Target library**: the running app's root library (`getIsolate().rootLib`),
  typically `lib/main.dart`.
- **In scope**:
  - Top-level symbols of the root library (everything declared in
    `lib/main.dart` at top level).
  - Symbols transitively imported by `lib/main.dart`.
  - Public symbols (private `_foo` from other libraries are NOT
    accessible).
- **Not in scope**:
  - Symbols from libraries not imported by `lib/main.dart`.
  - `this` (no implicit receiver in expression eval).
  - Local variables of any function (there is no stack frame to
    inspect; that is `evaluateInFrame`'s domain, not what
    `artisan_tinker` uses).
- **Isolate**: the main isolate (`vm.isolates.first`). Flutter apps have
  one user isolate (plus a background service isolate); `.first`
  consistently resolves to the UI isolate.

For Magic-stack apps, the practical scope is everything the
`Magic.init()` boot chain registered: the singleton container, every
facade (`Magic`, `Http`, `Auth`, `Cache`, `Echo`, `Event`, `Gate`,
`Session`, `Storage`, `Crypt`, `Vault`, `Pick`, `Launch`, `MagicRoute`,
`Log`, `Lang`, `Config`, `Env`, `Carbon`), every registered model, and
every controller resolved via `Magic.find<T>()`.

## Return value formatting

`lib/src/tinker/tinker_formatter.dart:10-44` walks the
`Tinker.casters` chain first, falls through to a built-in
`InstanceRef` unwrap:

| Result type | Rendered as |
|---|---|
| Null | `null` |
| Bool | `true` / `false` |
| Int / Double | `<numeric literal>` |
| String | `'<quoted>'` |
| Primitive Pointer / Float32x4 / etc. | `<valueAsString>` |
| Complex object | `<ClassName#id>` (e.g. `<MonitorListState#a3f9>`) |
| Magic `Model` (via integration caster) | multi-line table with attributes |
| Future (from `await` wrap) | resolved value (artisan awaits before formatting) |

For non-primitive values that the default formatter renders as
`<ClassName#id>`, the agent MUST append `.toString()` INSIDE the
expression to get readable output:

```
artisan_tinker { eval: "Magic.find<MonitorController>().rxState.value" }
  -> <MonitorListState#a3f9>

artisan_tinker { eval: "Magic.find<MonitorController>().rxState.value.toString()" }
  -> 'MonitorListState(monitors: [...], total: 12)'
```

This is the single most important tinker idiom. Default `toString()`
implementations in Dart are noisy (`Instance of 'MonitorListState'`),
so production controllers in this repo override `toString()` to dump
meaningful state.

## Error paths (four distinct shapes)

The agent receives one of four shapes via the MCP error envelope
(`isError: true` + `### Error\n<message>`). Branch on the substring:

### 1. Compile error (`RPCError` code 113)

Trigger: bad syntax, unknown identifier, type mismatch, trailing `;`,
multi-statement block, `import` directive, top-level declaration.

Shape:

```
### Error
Expression compilation error: <compiler message>
```

Substring contract: `Expression compilation error`.

Recovery: rewrite the expression as a single valid Dart expression.
Strip `;`, collapse statements via cascade or comma operator.

### 2. Runtime exception (`ErrorRef` returned, NOT thrown)

Trigger: the expression compiled but threw at runtime.

Shape:

```
### Error
Runtime exception: <Dart exception message + class>
```

Substring contract: `Runtime exception`.

Recovery: read the exception class and message; the expression is
exercising a real bug in the running code. Fix the app code or change
the expression.

### 3. Stale isolate (`SentinelException`)

Trigger: hot restart minted a new isolate id between the agent's last
call and this one, and the auto-retry in
`callServiceExtension` failed to recover.

Shape:

```
### Error
Isolate sentinel (kind: Collected)
```

Substring contract: `Isolate sentinel`.

Recovery: the next call usually self-recovers (the retry path refreshes
the isolate id). If it persists, call `artisan_hot_restart` to force a
clean isolate, then retry.

### 4. Disconnected VM Service (no app, dead WS, DDS down)

Trigger: `~/.artisan/state.json` is absent, or the recorded
`vmServiceUri` no longer accepts a WebSocket.

Shape:

```
### Error
Not connected to a running Flutter app. Run `dart run fluttersdk_artisan start` first so `~/.artisan/state.json` records the VM Service URI.
```

Substring contract: `Not connected to a running Flutter app`.

Recovery: call `artisan_start`, then retry. Lazy-reconnect picks up the
new state.json on the next call.

## Recipe pack (Magic-stack apps)

### Inspect controller state

```
artisan_tinker { eval: "Magic.find<MonitorController>().rxState.value.toString()" }
artisan_tinker { eval: "Magic.find<MonitorController>().rxStatus.value.toString()" }
```

### Trigger a controller method

```
artisan_tinker { eval: "await Magic.find<MonitorController>().refresh()" }
```

The `await` is auto-wrapped. Returns the method's return value (often
`null` for `Future<void>`).

### Read state BEFORE and AFTER an action

```
artisan_tinker { eval: "Magic.find<MonitorController>().rxState.value.toString()" }
artisan_tinker { eval: "await Magic.find<MonitorController>().refresh()" }
artisan_tinker { eval: "Magic.find<MonitorController>().rxState.value.toString()" }
```

### Side-effect then read with cascade

```
artisan_tinker { eval: "(Magic.find<MonitorController>()..refresh()).rxState.value.toString()" }
```

The cascade returns the receiver; the wrapping parens give it expression
position; `.rxState.value.toString()` reads it. Synchronous side-effect
only (cascade does not await).

### Side-effect with comma operator

```
artisan_tinker { eval: "Event.dispatch(MyEvent()), 'event dispatched'" }
```

The comma operator evaluates both sides, returns the rightmost. Useful
for void side-effects whose return value is `null` (which would render
as `null` without the second clause; the literal string makes the
result self-describing).

### Read a config value

```
artisan_tinker { eval: "Config.get('app.name')" }
artisan_tinker { eval: "Env.get('APP_KEY')" }
```

### Check the current user

```
artisan_tinker { eval: "Auth.user?.toString()" }
artisan_tinker { eval: "Auth.check()" }
```

### Read a cached HTTP response

```
artisan_tinker { eval: "Cache.get('monitors:team_123')?.toString()" }
```

### Inspect the live route

```
artisan_tinker { eval: "MagicRoute.currentTitle" }
artisan_tinker { eval: "MagicRoute.currentPath" }
```

### Dispatch an app event

```
artisan_tinker { eval: "Event.dispatch(AppBooted()), 'dispatched'" }
```

### Probe a gate

```
artisan_tinker { eval: "Gate.allows('monitors.destroy', Magic.find<MonitorController>().rxState.value?.monitors.first).toString()" }
```

### Inspect form data in a stateful view

```
artisan_tinker { eval: "Magic.find<MagicFormData>().data.toString()" }
```

(Only when the view stored the form data in the container; many views
keep it local to their `State` class, in which case `dusk_observe`
with the `magicFormField:` enricher is the right tool.)

## When NOT to use tinker

- **Inspecting widgets or the UI tree**: use `dusk_snap` and
  `dusk_observe`. They walk the Semantics tree; tinker has no access to
  the BuildContext stack.
- **Driving gestures (tap, drag, type)**: use `dusk_*` tools. They
  enforce the 6-step actionability gate; tinker has no awareness of
  hit-test or input dispatch.
- **Multi-statement workflows with local variables and control flow**:
  write a test file under `test/` and run `dart test`. Tinker is a
  one-shot REPL, not a scripting host.
- **Inspecting the Telescope ring buffers**: use `telescope_requests`,
  `telescope_exceptions`, `telescope_console`. They format the buffers;
  reading them via tinker forces you to do the formatting manually.
- **Watching for state changes over time**: tinker has no streaming
  surface. Use `dusk_wait_for { expression: ... }` which polls every
  200ms on the running isolate, or set up a `telescope_*` watcher and
  read it back.

## Anti-patterns

- **Trailing semicolon**: `eval: "1 + 1;"` raises compile error 113.
  Strip the `;`.
- **Multi-statement**: `eval: "var x = 1; x + 1"` raises compile error.
  Use a closure: `eval: "(() { var x = 1; return x + 1; })()"`. (Note:
  the closure body is a block, but the OUTER expression is a single
  closure invocation, which is valid.)
- **Imports inside eval**: `eval: "import 'dart:math'; sqrt(4)"` raises
  compile error. If `dart:math` is already imported by `lib/main.dart`
  (rarely is in production), `eval: "sqrt(4)"` works directly. If not,
  add the import to a debug-only file and hot-reload.
- **Forgetting `.toString()` on complex objects**: `eval:
  "Magic.find<MonitorController>().rxState.value"` returns
  `<MonitorListState#a3f9>` (the default `valueAsString` for non-primitives
  is the class-name-and-id sentinel). Append `.toString()` for readable
  state.
- **Using tinker as a sleep / poll loop**: tinker is one-shot. Loop in
  the agent layer, not in the expression.

## Comparison: `artisan_tinker` vs `dusk_evaluate`

Both run on the VM Service; both accept a single Dart expression.
Differences:

| Capability | `artisan_tinker` | `dusk_evaluate` |
|---|---|---|
| Surfaces from | substrate (always available) | `fluttersdk_dusk` plugin (dispatcher path only) |
| Target library | root library of the running app | same |
| Auto-await wrap | yes | no (caller must wrap manually) |
| Default formatter | `Tinker.casters` chain (Magic-aware) | raw `InstanceRef` JSON |
| Failure shape | `Runtime exception` / `Expression compilation error` text | structured JSON with error type |
| Best for | live state inspection + action triggering in Magic-stack apps | low-level evaluate where the raw `InstanceRef` JSON matters |

Default: prefer `artisan_tinker` for inspect / mutate, `dusk_evaluate`
when you need the structured JSON envelope or when running a non-Magic
app that does not benefit from the caster chain.
