# Changelog

All notable changes to this project will be documented in this file.

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). Entries follow the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) shape.

---

## [Unreleased]

### Added

- `start --timeout=<n>` option (default `90`): configures the maximum seconds the VM Service URI scrape loop waits for `flutter run` to print the debug URI in the log file. Previously the deadline was hardcoded to 90 s; cold starts on slow CI machines or after a fresh Flutter SDK install can exceed this limit. Setting `--timeout=120` (or higher) prevents false-timeout failures. The error message now reports the configured value rather than a literal "90s". Applies to the `--cdp-port` branch only; the non-CDP branch retains its own hardcoded deadline.
- `start --cdp-port=<n>` now probes the CDP port for availability BEFORE launching Chrome. When the port is already in use, the command exits 1 immediately with a clear message: "CDP port N is already in use; pass --cdp-port <free-port> or free it before running start." This replaces the previous misleading "Is Chrome installed?" catch-all that fired when Chrome failed to open the debug port it was asked to bind.

### Changed

- `plugin:install`'s `install.yaml` `bootstrap_command` now AUTO-RUNS after a successful manifest install instead of only printing a hint. Once the plugin is registered (`plugins.json` + `lib/app/_plugins.g.dart` regenerated), the declared command is spawned as a fresh dispatcher subprocess (`./bin/fsa <cmd> --non-interactive` when `bin/fsa` exists, else `dart run <consumer>:artisan <cmd> --non-interactive`), so the just-registered plugin command actually executes. `--non-interactive` is always forwarded so an interactive bootstrap (e.g. `starter:install`) cannot hang. `--bootstrap-command=<name>` overrides the manifest value; `--no-bootstrap` skips the auto-run and falls back to the hint. When no dispatcher resolves (no `bin/fsa`, no consumer pubspec name), the one-line `Bootstrap with: artisan <cmd>` hint is printed as before.

### Fixed

- `plugin:install` now surfaces a failing `bootstrap_command` instead of implying success. `BootstrapCommandRunner.run` returns a `BootstrapRunResult` carrying the subprocess exit code and captured stderr (it previously discarded the `ProcessResult`), and `plugin:install` warns with the exit code + stderr and prints the manual bootstrap hint when the chained command exits non-zero. A bootstrap that fails (stale fast-CLI bundle, unknown command, scaffold error) is no longer reported to the operator as if it had completed.
- `start --timeout=<n>` now rejects zero and negative values immediately with an actionable error ("--timeout must be a positive integer"), instead of silently passing a non-positive deadline to the VM Service scrape loop and producing a confusing "Timed out after 0s" failure.
- Passing an unknown option to any command now fails loudly instead of silently printing help and exiting as if help were requested (issue #12). The dispatcher writes `Unknown option: <flag>` to stderr (both long `--foo` and short `-x` forms), prints the command help, and exits non-zero. Other parse failures keep their original messages: a missing option value (`Missing argument for "..."`), a disallowed value, and a value given to a flag each surface their specific diagnostic unchanged. `--help` / `-h` and every valid invocation are unaffected. Because this is the shared dispatch path for every command, the fix benefits every plugin CLI built on the substrate.

## [0.0.8] - 2026-06-16

### Fixed

- `restart` now preserves the `--cdp-port` value from the previous session. Previously, `restart` ran stop then start, but stop deleted `state.json` before start could read the prior CDP port, silently dropping the Chrome remote-debugging setup. `RestartCommand` now reads `cdpPort` from state before stopping and forwards it into `StartCommand`. `RestartCommand` also declares the `--cdp-port` option, so an explicit `--cdp-port` on the `restart` invocation parses and wins over the forwarded value.
- `ManifestInstaller` now imports a published config factory from its consumer-relative `lib/config/<name>.dart` path instead of the plugin package barrel, so the injected `() => <name>Config` reference resolves after a `plugin:install` that publishes a config file.

### Documentation

- `doc/commands/start.md` now documents the `--cdp-port` option: synopsis, options table, the `state.json` schema (`cdpPort` / `chromePid` / `tmpProfileDir`), and a CDP example. The stale "Reserved for D6, always null in V1" field notes are corrected.
- Fixed 14 broken internal links across `doc/commands/*` and `doc/plugins/*` (dead deep-dive page links repointed to the command index), and synced the `restart` CDP-port behavior into `doc/commands/index.md` and the `state-and-recovery` skill reference.

## [0.0.7] - 2026-06-09

### Added

- `start --cdp-port` now fails fast with a clear, actionable error when the web port is already bound, instead of timing out after 90s. The error message names the busy port and suggests running `fsa stop` or selecting a different port via `--port` (issue #25).

### Fixed

- `start --cdp-port` now reaps the spawned Chrome process, flutter web-server, FIFO pipe, and temporary profile directory when launch fails after the port probe (issue #25). Previously, failed CDP sessions could leave orphaned processes and lingering files. Cleanup is best-effort; cleanup failures are ignored and never mask the original error.

## [0.0.6] - 2026-05-28

### Added

- `mcp:install --invocation=<exec>` option for plugin-aware `.mcp.json` fallback when `bin/fsa` is absent (writes `dart run <exec> mcp:serve`). Whitespace-only values are trimmed and treated as not provided, so `--invocation="  "` falls back to the `:dispatcher` shape rather than producing an invalid `dart run    mcp:serve` entry. Plugin wrappers (`fluttersdk_dusk`, `fluttersdk_telescope`) can now inject `--invocation=<plugin>` automatically so substrate-only consumers without `bin/fsa` get the correct MCP wiring.
- `skills/fluttersdk-artisan/SKILL.md` Section 8 (Community: star + issue, optional, once per session) plus a new `skills/fluttersdk-artisan/references/community.md` (156 lines). Trigger split: star fires after a task verified end-to-end against the running app or a clean `make:*` / `plugin:install` / `mcp:install` flow; issue fires only on a genuine artisan-side defect (malformed `artisan_*` JSON, substrate-allowlist registration failure, `.mcp.json` precedence broken, `artisan_tinker` crash on a valid expression, AOT staleness regression, hot-reload semantics inverted). Section 5 substrings (`No Flutter app detected`, `Pipe missing`, `Expression compilation error`, `Isolate sentinel`, `mkfifo failed (Windows ...)`, etc.) are explicitly excluded from the issue trigger because they are state / environment / expression-shape signals, not bugs. Both CTAs are prose-permission, never auto-executed, gated on `command -v gh && gh auth status`, URL-only fallback when `gh` is missing, and capped at one shot per session. `gh issue create` uses `--label bug` alone; the `agent-reported` label is not provisioned on the artisan repo yet, so the example deliberately omits it to avoid pre-creating labels on the user's account.

### Changed

- `mcp:install` now writes `.mcp.json` atomically via the `.tmp` + rename pattern (mirrors `StateFile.write` and `PluginsRegistryFile.write`), so concurrent MCP clients (Claude Code, Cursor, Windsurf) never observe a half-written file when the command is interrupted mid-write.
- Repo flow: adopted GitHub Flow (single long-lived `master`; retired the `develop` accumulator and all merged feature branches). `CLAUDE.md` now carries this as Golden Rule 7 plus a `## Branching` section documenting task-branch naming (`<type>/<kebab-case-topic>`), the squash-vs-rebase-vs-merge decision, the release shape (`release/X.Y.Z` PR bumps pubspec + promotes CHANGELOG, then tag fires `.github/workflows/publish.yml`), and the external-contributor fork-and-PR shape. `delete_branch_on_merge: true` enabled on origin so merged branches auto-cleanup.

### Fixed

- `artisan_tinker` MCP tool description and the `eval` input-schema example expression scrubbed of consumer-specific class names (`MonitorController.instance.refresh()`, `User.current.name`). Replaced with framework-neutral examples (`WidgetsBinding.instance.lifecycleState`, `MyService.instance.refresh()`) and tightened the scope language ("controllers, models, framework facades" -> "top-level functions, singletons, services"). Surfaces to every MCP client (Claude Code, Cursor, Windsurf, etc.) on `tools/list`, so the published 0.0.x docs no longer leak private consumer-app identifiers.
- **MCP `serverInfo.version` no longer drifts (continued from 0.0.5 NIT 7)**: the hardcoded `version: '0.0.5'` literal in `lib/src/mcp/mcp_server.dart` is manually synced to `'0.0.6'` as part of this release-cut commit. A future patch may switch to a build-time constant to eliminate manual drift recurrence (still deferred per scope).

## [0.0.5] - 2026-05-23

### Fixed

- **`./bin/fsa` AOT bundle staleness missed `lib/app/_plugins.g.dart` mtime (issue #9 GAP A)**: after `plugin:install` regenerated `lib/app/_plugins.g.dart`, subsequent `./bin/fsa` invocations kept running the stale cached bundle, so newly registered plugin commands silently did not surface. Fixed by two complementary changes: (a) appended condition-5 (`_plugins.g.dart -nt STAMP_FILE`) to `bin_fsa.sh.stub`'s `needs_build()` shell function so the shim self-heals on any plugin operation regardless of who mutated the file, and (b) added `CliBundleCache.purge(projectRoot)` to the legacy `plugin:install` success path, `plugin:uninstall` success path, and `plugins:refresh` success path so the cache invalidates as a direct side effect of artisan-managed plugin lifecycle events. Manifest-flow `plugin:install` delegates to `plugins:refresh` transitively, so a single purge call covers both. Migration: re-run `make:fast-cli --force` to pick up the new shim. No CI or publish changes.
- **MCP `dusk_evaluate` returned a sentinel string instead of evaluating (issue #9 GAP F)**: the host-side `ext.dusk.evaluate` handler in `fluttersdk_dusk` returns a no-op sentinel by design; the actual evaluation must run through `vm.evaluate`. `lib/src/mcp/mcp_server.dart` `_dispatch` now special-cases `dusk_evaluate` by tool name and routes through `VmServiceClient.evaluate(isolateId, expression)` directly, with 3-branch error handling per the VM Service spec (`InstanceRef` happy path; `ErrorRef` runtime exception surfaced as `isError: true`; `Sentinel` stale-isolate with actionable hint; `RPCError` code 113 compile error with details extracted). Coordinated bump pairing: `fluttersdk_dusk` 0.0.2 plans to bump the artisan constraint to `^0.0.5`.
- **MCP `serverInfo.version` no longer drifts (issue #9 NIT 7)**: the hardcoded `version: '0.0.1'` in `lib/src/mcp/mcp_server.dart` lagged the pubspec across four releases. This release manually syncs the literal to `'0.0.5'` as part of the release-cut commit. A future patch may switch to a build-time `_kArtisanVersion` constant to eliminate manual drift recurrence (deferred per scope). The `serverInfo.name` literal `fluttersdk_artisan_mcp` stays as-is; the MCP spec treats `serverInfo.name` as a display hint, and Claude Code derives tool prefixes from the `.mcp.json` key, not from the server-advertised name. See `doc/mcp/setup.md#server-identity` for the rationale.

## [0.0.4] - 2026-05-21

### Fixed

- **MCP server returns empty tools/list (issue #7, Bug A)**: `dispatcher.dart.stub` now forwards `collectMcpTools: args.isNotEmpty && args.first == 'mcp:serve'` to `runArtisan`, so plugin providers' `mcpTools()` collect into the registry when consumers invoke `./bin/fsa mcp:serve`. Migration: substrate-installed consumers re-run `dart run fluttersdk_artisan install --force` to regenerate `bin/dispatcher.dart`. Magic-installed consumers need a paired magic-side stub update (tracked separately) before `magic:artisan install --force` propagates the fix.
- **`mcp:install` writes the canonical post-install entry shape (issue #7, Bug B)**: `.mcp.json` entry branches between `./bin/fsa mcp:serve` (POSIX with `bin/fsa` present) and `dart run :dispatcher mcp:serve` (Windows or no-fsa fallback); the previous hardcoded `dart run fluttersdk_artisan:mcp` shape routed through the substrate standalone, which never loads consumer plugin providers. Migration: consumers must re-run `./bin/fsa mcp:install` (or `dart run fluttersdk_artisan mcp:install`).
- **Auto-delegation now resolves the canonical consumer wrapper**: `_defaultDelegate` at `lib/src/console/run_artisan.dart` previously emitted `dart run :artisan`, which resolves only to `bin/artisan.dart`. Post-0.0.2 the canonical wrapper is `bin/dispatcher.dart`. Fixed by prepending `:dispatcher` upstream of the delegate call (`(delegate ?? _defaultDelegate)([':dispatcher', ...args])`); `_defaultDelegate`'s body simplifies to `['run', ...args]`. Latent since 0.0.2; not caught by tests because the existing delegation tests mocked `delegate:` without asserting on the prefixed args.
- **`doctor` advisory extended for pre-Bug-B `.mcp.json`**: `doctor` now advisory-warns when `.mcp.json` still contains `fluttersdk_artisan:mcp` args, pointing the user at `./bin/fsa mcp:install` to upgrade. Does not affect exit code.
- **`./bin/fsa` rebuilt AOT bundle on every invocation**: the staleness check compared `pubspec.yaml` mtime against `pubspec.lock`. `dart pub add` updates `pubspec.yaml` after pub get writes the lock, leaving `pubspec.yaml` mtime newer than `pubspec.lock` for every freshly installed consumer; that tripped the check on every call. Compare against the build stamp file instead (written at the end of every successful compile), so `pubspec.yaml` newer than the stamp means the user actually edited it. Cached invocations now hit the ~50ms target. Discovered during A-Z e2e testing.
- **`make:command` crashed with "Stub file not found: artisan_command.stub"**: the stub asset never shipped in the publish archive even though `MakeCommandCommand.getStub()` declared it as the canonical scaffold name. Added the missing `assets/stubs/artisan_command.stub` with the canonical `final class ... extends ArtisanCommand` shape honoring `{{ className }}` / `{{ namespace }}` / `{{ commandName }}` placeholders. Discovered during A-Z e2e testing.

## [0.0.3] - 2026-05-21

### Changed

- **`xml` constraint downgraded `^7.0.0` -> `^6.5.0`** (`pubspec.yaml`): pub.dev resolution now intersects with `image ^4.0.0` (used by `fluttersdk_dusk`'s `ext_screenshot.dart` via `xml ^6.0.1`). The 0.0.2 cut pinned `xml ^7.0.0`, which made `fluttersdk_dusk` unresolvable as a hosted dep alongside `fluttersdk_artisan 0.0.2` because no `image 5.x` exists to satisfy the upper bound. Reverted the 8 `XmlName.parts('localname')` migration sites in `lib/src/helpers/plist_writer.dart` back to `XmlName('localname')` so the file compiles cleanly against xml 6.x (where `.parts` did not yet exist). xml 7 migration is deferred until `image` ships a release on the xml 7 line.

## [0.0.2] - 2026-05-20

### Breaking

- **`consumer:scaffold` renamed to `install`**: the command `consumer:scaffold` no longer exists. Consumers must use `dart run fluttersdk_artisan install` going forward.
- **`bin/artisan.dart` renamed to `bin/dispatcher.dart`**: the scaffold output path has changed. Migration: re-run `dart run fluttersdk_artisan install --force` to scaffold the new file layout, then update any scripts or CI steps that reference `bin/artisan.dart`.
- **Old stub removed**: `consumer_artisan_bin.dart.stub` is gone; the replacement stub is `dispatcher.dart.stub`.
- **`InstallCommand` -> `InstallArtisanCommand`**: the public class on the `package:fluttersdk_artisan/artisan.dart` barrel now carries the `Artisan` prefix so plugins exporting their own `InstallCommand` (notifications, deeplink, etc.) no longer collide with the substrate at import time.

### Added

- **`install` auto-chains `make:fast-cli`**: after writing the consumer entry and barrels, `install` automatically runs `make:fast-cli` so `bin/fsa` (the AOT-compiled fast startup wrapper) is ready without a separate manual step.
- **New stub `dispatcher.dart.stub`**: replaces the former `consumer_artisan_bin.dart.stub`; rendered to `bin/dispatcher.dart` during `install`.
- **`artisan start --cdp-port=N` opt-in flag** (`lib/src/commands/start_command.dart`): when set, pre-launches Chrome with `--remote-debugging-port=N --remote-allow-origins=* --user-data-dir=/tmp/dusk-chrome-N`, runs `flutter run -d web-server --web-port=N --web-experimental-hot-reload --host-vmservice-port=N` (silent remap from `--device=chrome`), waits for the "is being served at" log line, navigates Chrome to the served URL via inline CDP, then scrapes `vmServiceUri` from the DWDS log once the debugger client connected. Writes `chromePid` + `cdpPort` + `tmpProfileDir` to `~/.artisan/state.json`. Default flow (no `--cdp-port`) unchanged. Gates the branch on `flutter --version --machine` >= 3.30.0 with an actionable upgrade error.
- **`artisan stop` Chrome cleanup**: when `state['chromePid'] != null`, sends SIGTERM, waits the grace period, escalates to SIGKILL if the process is still alive, deletes `tmpProfileDir`. Inlines the SIGTERM-grace-SIGKILL pattern from `fluttersdk_dusk/lib/src/utils/chrome_reaper.dart:216-264` to avoid inverting the plugin dependency direction (see Deferred Ideas: V1.x consolidation).
- **`artisan doctor` Flutter SDK gate**: new check `flutter sdk >= 3.30.0 (for --cdp-port)` registered in the existing `_Check` list. Advisory `_cdpUpgradeWarning` writeln (mirrors `_checkStaleMcpJson` pattern) surfaces an upgrade message when the SDK is too old. Required for `flutter/flutter#170612` (DWDS WebSocket hot reload on `-d web-server`).
- **`StateFile` schema**: new `cdpPort` field (int | null, --cdp-port value passed to start; null when CDP not enabled). Roundtrip test added.
- **GitHub Release auto-creation in `publish.yml`**: new `github-release` job (depends on the OIDC `publish` job) extracts the `## [<version>] - <date>` block from `CHANGELOG.md` via `awk` and creates a matching GitHub Release using `softprops/action-gh-release@v2`. Falls back to a stub body linking to `CHANGELOG.md` when the section is missing.
- **`make:fast-cli` builtin command + `bin/fsa` wrapper** (`lib/src/commands/make_fast_cli_command.dart`, `assets/stubs/bin_fsa.sh.stub`): scaffold a POSIX shell wrapper that compiles `bin/dispatcher.dart` into an AOT binary via `dart build cli`, cached at `.artisan/cli-bundle/bundle/bin/dispatcher`. Wrapper auto-detects staleness (pubspec.lock SHA256 + Dart SDK version + pubspec.yaml mtime greater than pubspec.lock) and re-compiles transparently. Result: ~50ms startup for `./bin/fsa <cmd>` vs ~3s for `dart run fluttersdk_artisan <cmd>` (no "Running build hooks..." overhead). Idempotent on re-run; `--force` overwrites the wrapper. POSIX-only V1 (macOS + Linux); Windows .cmd variant deferred. The existing `dart run fluttersdk_artisan` path is unchanged and remains the canonical CLI entry.

### Changed

- **`plugin:install` preflight scope**: the wrapper-presence check (`bin/artisan.dart` must exist) moved out of the shared preflight into the legacy-injection branch only. Canonical-scaffold projects (`lib/app/_plugins.g.dart` present) now route through `.artisan/plugins.json` registration without tripping the legacy gate, even when the consumer never wrote a `bin/artisan.dart` file.
- **`artisan start --vm-service-port`** now plumbs through to `flutter run` as `--host-vmservice-port=N` and is recorded in `state.json` so downstream tools see the actual bound port. The option was declared but never read in 0.0.1.
- **`publish.yml` triggers** narrowed to `push.tags` and `workflow_dispatch`. Removed the `release.types: [published]` trigger to avoid release/publish recursion (the workflow creates the release itself now). Tag-first flow: `git tag X.Y.Z && git push origin X.Y.Z` -> validate -> pub.dev publish via OIDC -> GitHub Release with CHANGELOG-driven notes.

### Fixed

- **`start --cdp-port` ordering deadlock**: 0.0.1 scraped the VM Service URI before navigating Chrome, which deadlocked under DWDS (the URI emits only after a debugger client connects). Restructured the branch to wait for the "is being served at" log line, navigate Chrome to the served URL, then scrape. Three end-to-end Chrome / CDP automation issues fixed alongside: `--no-first-run` + `--no-default-browser-check` on the launch argv, `Page.navigate` now targets the page-level WebSocket from `/json` instead of the browser-level `/json/version`, automation-noise suppression flags added.
- **`start --cdp-port=<non-int>`** now returns exit 1 with an actionable error instead of silently falling through to the non-CDP path.
- **`stop`** no longer emits `Chrome SIGTERM sent...` unconditionally: the boolean from `Process.killPid` is checked and a `not delivered` warning surfaces when the signal could not land (process already gone, permission denied).
- **`doctor` SDK gate** now tolerates beta channel strings like `3.30.0-1.0.pre` and missing trailing segments (`3.30`), matching `StartCommand.compareSemver` exactly so the doctor cannot flag a version the start command would accept.
- **VM Service** retries once on the transient DWDS `WipError: Promise was collected` and on the stale-isolate sentinel from `callServiceExtension`, so a single device-target switch or DWDS hiccup does not surface to consumers.
- **`install` consumer-wrapper detection** accepts both `bin/dispatcher.dart` (canonical post-rename) and `bin/artisan.dart` (legacy) as valid wrappers for auto-delegation. `InstallArtisanCommand.scaffoldInto` auto-triggers `PluginsRefreshCommand` in-process when `<root>/.artisan/plugins.json` exists so the codegen barrel does not get overwritten with an empty list.
- **`bin/fsa` PID-aware lock recovery**: when a prior `./bin/fsa` invocation crashed mid-build the wrapper used to deadlock on `.artisan/.fsa.lock` for every subsequent run. The stub now reads the holder PID, verifies the process is still alive, and reclaims the lock when it is not.

### Known limitations

- **MCP schema drift for `artisan_start`**: the hand-authored `_commandInputSchema('start')` at `lib/src/mcp/mcp_server.dart` does NOT advertise the new `--cdp-port` flag. The substrate dispatch still routes CLI args through correctly, but agents driving `artisan_start` via MCP cannot discover the flag from the schema. V1.x backlog: auto-derive the schema from `ArtisanCommand.signature` / `configure(ArgParser)` so it cannot drift.

## [0.0.1] - 2026-05-19

Initial public release of `fluttersdk_artisan`. Pure Dart 3.4+ CLI framework and stdio MCP server for Flutter and Dart projects. Pana score 160 / 160 on first publish.

### Commands

21 builtin commands across 6 groups:

- **Lifecycle**: `start [--device]`, `stop`, `restart`, `status`, `logs [--follow]`, `reload`, `hot-restart`.
- **Scaffolding**: `consumer:scaffold` (canonical wrapper for plain Flutter), `make:plugin <name>` (plugin package skeleton with workspace enrollment + magic-mode upgrade detection), `make:command <Name>` (context-aware command scaffold for plugin or consumer).
- **Plugin management**: `plugin:install <name>` (manifest-driven, scaffold-aware, or legacy injection), `plugin:uninstall <name>`, `plugins:refresh`, `commands:refresh`.
- **MCP**: `mcp:serve` (stdio JSON-RPC server with three-layer filter), `mcp:install` (writes `.mcp.json` entry, idempotent), `mcp:uninstall`.
- **Introspection**: `doctor` (preflight checks), `list` (all registered commands grouped by `:` namespace), `help <cmd>`.
- **REPL**: `tinker [--eval=<expr>]` (VM Service evaluate against the running Flutter app; interactive mode falls back when `--eval` is absent).

### Stdio MCP server

- Built on `dart_mcp ^0.5.1`. Entry point: `dart run fluttersdk_artisan:mcp`.
- 10 substrate tools (always-on) surface artisan's own CLI as MCP tools so an LLM agent can bootstrap a Flutter app without leaving the chat: lifecycle quartet (`artisan_start` / `artisan_stop` / `artisan_restart` / `artisan_reload` / `artisan_hot_restart`) plus `artisan_status`, `artisan_logs`, `artisan_doctor`, `artisan_list`, `artisan_tinker`.
- Plugin tools register via `ArtisanServiceProvider.mcpTools()`. The MCP server collects them at startup; `ArtisanMcpToolCollisionException` attributes name clashes to specific providers.
- Three-layer Cargo-style filter: `.artisan/mcp.json` (file) + `ARTISAN_MCP_TOOLS_*` / `ARTISAN_MCP_PACKAGES_*` (env) + `--include-tool` / `--exclude-tool` / `--include-package` / `--exclude-package` CLI flags. Allow uses first-non-null; deny is the union; deny wins everywhere.
- Soft-fail at initialize when no Flutter app is running; lazy-reconnects to VM Service on the next tool call. Tool calls without a running app return an actionable `CallToolResult(isError: true)` so the model can self-correct.

### Plugin protocol

- **Declarative `install.yaml` manifest**: `publish`, `magic.provider`, `magic.configFactory`, `magic.routes`, `native.android` (permissions / metaData / gradle plugins / dependencies), `native.ios` / `native.macos` (plistEntries / podEntries), `native.web` (headInjections / metaTags), `env`, `prompts`, `placeholders`, `bootstrap_command`.
- **Procedural escape hatch**: subclass `ArtisanInstallCommand` and drive `PluginInstaller` for plugins that need runtime branching the schema cannot express.

### PluginInstaller DSL

Fluent builder for install operations across file ops (`publishConfig`, `writeFile`, `mergeJson`), source-injection ops (`injectImport`, `injectBefore`, `injectAfter`, `injectProvider`, `injectConfigFactory`, `injectRoute`), native ops (`injectAndroidPermission`, `injectAndroidMetaData`, `injectAndroidGradlePlugin`, `injectAndroidGradleDependency`, `injectIosPlistEntry`, `injectIosPodEntry`, `injectMacosPlistEntry`, `injectMacosPodEntry`, `injectIntoWebHead`, `addWebMetaTag`), and env ops (`injectEnvVar`). Operations enqueue against a sealed `InstallOperation` hierarchy with 26 final variants.

### Idempotency, atomicity, reversibility

- `ConflictDetector` flags `unmanaged-file` when a target exists outside any recorded install (`--force` override + scaffold-fingerprint heuristic auto-allows the default Flutter counter-app overwrite).
- `InstallTransaction` writes via `.tmp` + atomic rename; concurrent readers never observe partial state.
- `ConfigEditor.insertCodeAfterPattern` + `insertCodeBeforePattern` early-return when the target already contains the code (idempotent re-install).
- `PluginInstaller.injectProvider` + `injectConfigFactory` append to the END of the list using lookahead-anchored regex `(?=\s*\n\s*\])` so new entries appear where readers expect them (6-space indent matches the scaffold style).
- `InstallTransaction` records every applied op to `.artisan/installed/<plugin>.json` (op type, target path, content hash). `plugin:uninstall` reverses `WriteFile` (delete + stub-hash tamper check); `InjectImport` and `InjectAfterPattern` log `[skipped]` (anchor-bracketed inject markers pending V1.1).

### Signature DSL

Command surface declared inline: `String get signature => 'cmd:name {arg} {--flag=default}'`. `configure(ArgParser)` remains available as an explicit fallback. The MCP server's per-command `inputSchema` is verified against the underlying command's argument declarations so the wire contract cannot drift from the CLI surface.

### Codegen barrels

- `lib/app/commands/_index.g.dart` (consumer commands), regenerated by `make:command` and `commands:refresh`.
- `lib/app/_plugins.g.dart` (plugin providers), regenerated by `plugin:install <name>` and `plugins:refresh` from the `.artisan/plugins.json` registry.

Both write through `.tmp` + atomic rename; never hand-edit.

### VM Service hooks

- `tinker` evaluates Dart expressions against the connected isolate via the VM Service evaluate RPC. Magic facade autocomplete + Eloquent model casting come from the optional `magic_tinker` integration when registered.
- `reload` / `hot-restart` write `r` / `R` to the `flutter run` process's stdin via a POSIX FIFO bridge so detached processes still accept interactive commands.

### Testable primitives

- `VirtualFs` interface + `InMemoryFs` implementation. Every installer pathway is unit-testable without touching the host filesystem.
- `InstallContext.test(fs, prompt, stubs, clock, projectRoot)` fixture builder.
- `ArtisanContext.bare(MapInput, BufferedOutput)` for command-level tests.
- `BufferedOutput` captures `info` / `success` / `warning` / `error` lines for assertion.

### Programmatic API

- `runArtisan(args, baseProviders:, delegateToConsumer:, collectMcpTools:)`: universal entry point.
- Single barrel: `package:fluttersdk_artisan/artisan.dart` exposes the full public surface (`Application`, `Command`, `Input` / `Output`, `ServiceProvider`, `Context`, `VmServiceClient`, `StateFile`, stub system, helpers, installer, registry).

### CI + automated publishing

- **`.github/workflows/ci.yml`**: format + analyze + tests + 80 % line-coverage floor (via `coverage:format_coverage` + awk gate) + dry-run archive on every push to master and every pull request.
- **`.github/workflows/publish.yml`**: SemVer tag push triggers validate -> pub.dev publish via the official `dart-lang/setup-dart/.github/workflows/publish.yml@v1` reusable workflow with OIDC authentication (no long-lived secret stored). Requires "Automated publishing from GitHub Actions" enabled on the pub.dev package admin page with the repository pinned to `fluttersdk/artisan`.
- **`.github/dependabot.yml`**: weekly pub bumps (root + `example/`) plus weekly GitHub Actions version bumps.
- **`.github/ISSUE_TEMPLATE/`**: structured `bug_report.yml`, `feature_request.yml`, `documentation.yml`, plus a `config.yml` that disables blank issues. Bug + feature templates use a 14-option Subsystem dropdown matching the `lib/src/` layout.

### Documentation

- `README.md` two-path Quick Start (plain Flutter via `consumer:scaffold`; Magic-managed via `magic:install`).
- 17-file `doc/` tree under `https://fluttersdk.com/artisan/X/Y`: `getting-started/`, `commands/`, `mcp/`, `plugins/`, `reference/`.
- `skills/fluttersdk-artisan/`: LLM-agent skill (`SKILL.md` + 5 references: `commands.md`, `install-yaml-schema.md`, `installer-dsl.md`, `mcp-server.md`, `plugin-authoring.md`).
- `llms.txt` at repo root per llmstxt.org spec.

### Compatibility

- Dart SDK `>=3.4.0 <4.0.0`. Pure Dart core; Flutter optional (only required by plugins that consume Flutter SDK APIs).
- Platforms: Android, iOS, macOS, Linux, Windows. Web unsupported (relies on `dart:io`).
- V1 lifecycle commands (`start`, `stop`, `reload`, `hot-restart`) use POSIX FIFO stdin pipes via `mkfifo`. macOS and Linux only; Windows unsupported for the lifecycle quartet (other commands work).
