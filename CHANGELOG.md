# Changelog

All notable changes to this project will be documented in this file.

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). Entries follow the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) shape.

---

## [Unreleased]

### Breaking

- **`consumer:scaffold` renamed to `install`**: the command `consumer:scaffold` no longer exists. Consumers must use `dart run fluttersdk_artisan install` going forward.
- **`bin/artisan.dart` renamed to `bin/dispatcher.dart`**: the scaffold output path has changed. Migration: re-run `dart run fluttersdk_artisan install --force` to scaffold the new file layout, then update any scripts or CI steps that reference `bin/artisan.dart`.
- **Old stub removed**: `consumer_artisan_bin.dart.stub` is gone; the replacement stub is `dispatcher.dart.stub`.

### Added

- **`install` auto-chains `make:fast-cli`**: after writing the consumer entry and barrels, `install` automatically runs `make:fast-cli` so `bin/fsa` (the AOT-compiled fast startup wrapper) is ready without a separate manual step.
- **New stub `dispatcher.dart.stub`**: replaces the former `consumer_artisan_bin.dart.stub`; rendered to `bin/dispatcher.dart` during `install`.

### Removed

- **`consumer:scaffold` command**: superseded by `install`. Old invocations (`dart run fluttersdk_artisan consumer:scaffold`) must be updated.
- **`consumer_artisan_bin.dart.stub`**: removed alongside the command it served; replaced by `dispatcher.dart.stub`.

### Added

- **`artisan start --cdp-port=N` opt-in flag** (`lib/src/commands/start_command.dart`): when set, pre-launches Chrome with `--remote-debugging-port=N --remote-allow-origins=* --user-data-dir=/tmp/dusk-chrome-N`, runs `flutter run -d web-server --web-port=N --web-experimental-hot-reload` (silent remap from `--device=chrome`), scrapes vmServiceUri from DWDS log, then sends `Page.navigate` to the served URL via inline CDP. Writes `chromePid` + `cdpPort` + `tmpProfileDir` to `~/.artisan/state.json`. Default flow (no `--cdp-port`) unchanged. Gates the branch on `flutter --version --machine` >= 3.30.0 with an actionable upgrade error.
- **`artisan stop` Chrome cleanup**: when `state['chromePid'] != null`, sends SIGTERM, waits the grace period, escalates to SIGKILL if the process is still alive, deletes `tmpProfileDir`. Inlines the SIGTERM-grace-SIGKILL pattern from `fluttersdk_dusk/lib/src/utils/chrome_reaper.dart:216-264` to avoid inverting the plugin dependency direction (see Deferred Ideas: V1.x consolidation).
- **`artisan doctor` Flutter SDK gate**: new check `flutter sdk >= 3.30.0 (for --cdp-port)` registered in the existing `_Check` list. Advisory `_cdpUpgradeWarning` writeln (mirrors `_checkStaleMcpJson` pattern) surfaces an upgrade message when the SDK is too old. Required for `flutter/flutter#170612` (DWDS WebSocket hot reload on `-d web-server`).
- **`StateFile` schema**: new `cdpPort` field (int | null, --cdp-port value passed to start; null when CDP not enabled). Roundtrip test added.
- **GitHub Release auto-creation in `publish.yml`**: new `github-release` job (depends on the OIDC `publish` job) extracts the `## [<version>] - <date>` block from `CHANGELOG.md` via `awk` and creates a matching GitHub Release using `softprops/action-gh-release@v2`. Falls back to a stub body linking to `CHANGELOG.md` when the section is missing.
- **`make:fast-cli` builtin command + `bin/fsa` wrapper** (`lib/src/commands/make_fast_cli_command.dart`, `assets/stubs/bin_fsa.sh.stub`): scaffold a POSIX shell wrapper that compiles `bin/artisan.dart` into an AOT binary via `dart build cli`, cached at `.artisan/cli-bundle/`. Wrapper auto-detects staleness (pubspec.lock SHA256 + Dart SDK version + pubspec.yaml mtime greater than pubspec.lock) and re-compiles transparently. Result: ~50ms startup for `./bin/fsa <cmd>` vs ~3s for `dart run fluttersdk_artisan <cmd>` (no "Running build hooks..." overhead). Idempotent on re-run; `--force` overwrites the wrapper. POSIX-only V1 (macOS + Linux); Windows .cmd variant deferred. The existing `dart run fluttersdk_artisan` path is unchanged and remains the canonical CLI entry.

### Known limitations

- **MCP schema drift for `artisan_start`**: the hand-authored `_commandInputSchema('start')` at `lib/src/mcp/mcp_server.dart` does NOT advertise the new `--cdp-port` flag. The substrate dispatch still routes CLI args through correctly, but agents driving `artisan_start` via MCP cannot discover the flag from the schema. V1.x backlog: auto-derive the schema from `ArtisanCommand.signature` / `configure(ArgParser)` so it cannot drift.

### Changed

- **`publish.yml` triggers** narrowed to `push.tags` and `workflow_dispatch`. Removed the `release.types: [published]` trigger to avoid release/publish recursion (the workflow creates the release itself now). Tag-first flow: `git tag X.Y.Z && git push origin X.Y.Z` -> validate -> pub.dev publish via OIDC -> GitHub Release with CHANGELOG-driven notes.

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
