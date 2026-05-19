# Changelog

All notable changes to this project will be documented in this file.

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). Entries follow the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) shape.

---

## [Unreleased]

### Changed

- **Documentation site**: subdomain `artisan.fluttersdk.com` replaced with path-style `fluttersdk.com/artisan`
  across `pubspec.yaml` (homepage, documentation), `README.md`, `llms.txt`, the awesome_plugin example
  README, and the generic make:plugin README stub.
- **`pubspec.yaml` description** rewritten for pub.dev SEO without comparison-language; pub.dev topics
  swapped from `artisan` to `mcp-server` to capture the 2026 differentiator.
- **`README.md` rewrite**: 691 lines reduced to 383 lines, Wind-paralel structure, all internal links point
  at `https://fluttersdk.com/artisan/X/Y` with descriptive labels (`MCP setup guide`, `commands catalog`,
  `signature DSL reference`, `install.yaml schema`, `PluginInstaller DSL reference`, `tool reference`). Logo
  switched to the Magic SVG via raw GitHub URL. Alpha banner removed; CHANGELOG is the canonical place for
  version-stability communication.
- **Project memory (`CLAUDE.md`) rewritten** for the current state. New `## Golden Rules` section codifies six
  per-change invariants: doc sync, skill sync, 80% line-coverage floor, README sync on significant changes,
  CHANGELOG-always under `[Unreleased]`, green-gate plus TDD. `.claude/rules/tests.md` updated with `##
  Coverage discipline` subsection wiring the floor to the `coverage/lcov.info` flow; baseline bumped to
  1060+ tests.

### Removed

- **`example_magic/` dev playground**: Magic-managed example retired (Magic ships its own example).
- **`doc/install_yaml_schema.md` and `doc/plugin_authoring_guide.md` from the old layout**: superseded by
  the new `doc/plugins/install-yaml.md` and `doc/plugins/authoring.md` under the URL-routable tree.
- **Magic-style stubs in `assets/stubs/`** (18 top-level + `assets/stubs/install/`): duplicated in
  `references/magic/assets/stubs/` and loaded by Magic's own provider. `lib/src/stubs/install_stubs.dart` +
  `test/stubs/install_stubs_test.dart` removed (test-only public API with no command-surface caller).

### Added

- **GitHub Actions CI** (`.github/workflows/ci.yml`): runs on push to master + pull requests against
  master. Steps: `dart pub get` -> `dart format --set-exit-if-changed lib/ test/ bin/` -> `dart analyze
  lib/ test/ bin/` -> `dart pub global run coverage:test_with_coverage --out=coverage` -> awk-based 80%
  line-coverage floor enforcement (fails the build under 80%) -> codecov upload -> `dart pub publish
  --dry-run` archive validation. Pure Dart (uses `dart-lang/setup-dart`); no Flutter toolchain pulled in.
- **GitHub Actions publish workflow** (`.github/workflows/publish.yml`): triggers on SemVer tag push
  (`[0-9]+.[0-9]+.[0-9]+*`), GitHub release publication, and manual `workflow_dispatch`. Validates
  format + analyze + tests + dry-run archive, then publishes to pub.dev via the official
  `dart-lang/setup-dart/.github/workflows/publish.yml@v1` reusable workflow with OIDC authentication
  (no PUB_DEV_PUBLISH_ACCESS_TOKEN secret required). Pub.dev must have "Automated publishing from
  GitHub Actions" enabled on the package admin page with the repository pinned to `fluttersdk/artisan`.
- **Dependabot config** (`.github/dependabot.yml`): weekly pub updates for the root package and
  `example/`, plus weekly GitHub Actions version bumps. PR limits: 5 per pub directory, 3 for actions.
- **Issue templates** (`.github/ISSUE_TEMPLATE/`): structured `bug_report.yml`, `feature_request.yml`,
  `documentation.yml`, plus a `config.yml` that disables blank issues and routes the Question /
  Discussion contact link to GitHub Discussions and the Documentation link to fluttersdk.com/artisan.
  Bug + feature templates use a 14-option Subsystem dropdown matching the actual `lib/src/` layout
  (Console, Commands, Lifecycle, Scaffolding, Plugin Management, MCP Server, MCP Tools, install.yaml,
  PluginInstaller DSL, Helpers, State, Tinker, Codegen barrels, Documentation). Bug template includes
  the V1 macOS / Linux / Windows platform note and asks for the exact `dart run fluttersdk_artisan ...`
  invocation that triggered the bug.
- **`artisan_tinker` as the 10th substrate MCP tool**: the `tinker` command is now allowlisted in
  `lib/src/mcp/mcp_server.dart` alongside the lifecycle quartet plus status / logs / doctor / list. The
  dispatcher detects `CommandBoot.connected`, builds `ArtisanContext.connected` with the lazy-reconnected VM
  Service client, and surfaces the tool with an `eval` (string, required) input schema. The legacy
  `magic_tinker` package's `tinker_eval` plugin descriptor is now obsolete; `artisan_tinker` replaces it.
- **`doc/` documentation tree** (17 files): URL-routable Markdown tree mirroring `references/wind/doc/`'s
  structure. Sub-folders: `getting-started/`, `commands/`, `mcp/`, `plugins/`, `reference/`. Maps to
  `https://fluttersdk.com/artisan/X/Y` per file path. README and llms.txt link into it with descriptive
  labels.
- **`llms.txt`** at repo root per llmstxt.org spec: under 2 KB, links use `.md` extensions for direct
  Markdown fetch by AI agents.
- **`skills/fluttersdk-artisan/`**: LLM-agent skill (SKILL.md + 5 reference files: commands.md,
  install-yaml-schema.md, installer-dsl.md, mcp-server.md, plugin-authoring.md) mirroring the
  magic-framework pattern. The cached SKILL.md covers the 12 core laws, command surface by group, MCP
  integration, plugin install protocol; references load on demand.
- **`tinker --eval=<expr>`**: one-shot evaluation flag for the `tinker` command. When provided, evaluates the
  expression against the connected VM Service and prints the result to stdout (exit 0 on success, 1 on
  `VmServiceClient` error). The interactive REPL still launches when `--eval` is absent. Covered by 3 new
  tests in `test/commands/tinker_command_test.dart`.
- **`consumer:scaffold` monorepo path-dep detection**: `scaffoldInto({root, force, ctx})` static entry point lets
  other commands (notably `dusk:install`) invoke the scaffolder programmatically without spawning a subprocess.
  When the consumer's `.dart_tool/package_config.json` resolves `fluttersdk_artisan` to a local sibling
  (monorepo / path-dep workflow), the scaffolder writes `bin/artisan.dart` + injects a `path:` dependency
  pointing at the resolved sibling. Falls back to `any` for pub.dev workflows. Covered by 11 new tests in
  `test/commands/consumer_scaffold_command_test.dart`.

---

## [0.0.1] - 2026-05-18

First public release. Symfony-Console-grade CLI framework for Dart and Flutter. One `artisan` binary unifies every fluttersdk command surface (`make:*`, `plugin:*`, `plugins:*`, `commands:*`, `consumer:*`, dev-loop, `tinker`) and any plugin that ships an `ArtisanServiceProvider`.

### Built-in Commands (19)

**Consumer setup**
- `consumer:scaffold`: write the canonical Magic-free consumer wrapper (`bin/artisan.dart` + `lib/app/_plugins.g.dart` + `lib/app/commands/_index.g.dart`). Idempotent; pass `--force` to overwrite.

**Plugin lifecycle**
- `make:plugin <name>`: scaffold a new plugin package under `packages/<name>/`. Generic 7-file scaffold by default; auto-upgrades to magic-mode with 5 add-ons when `magic:install` is in the registry. Enrolls the plugin into the parent app's pub `workspace:` list and deletes the flutter-create-default `test/<name>_test.dart` to keep `flutter analyze` clean on first run.
- `plugin:install <name>`: three routing modes. (1) `install.yaml` present then `ManifestInstaller` + `.artisan/plugins.json` write + `_plugins.g.dart` refresh. (2) no manifest but canonical scaffold present then direct registry write + refresh (Magic-free fast path). (3) neither then legacy `bin/artisan.dart` injection.
- `plugin:uninstall <name>`: reverse the recorded install ops. V1 reverses `WriteFile`; logs `[skipped]` for `InjectImport` and `InjectAfterPattern`.
- `plugins:refresh`: regenerate `lib/app/_plugins.g.dart` from `.artisan/plugins.json` (idempotent, byte-identical across runs).

**Code generators**
- `make:command <Name>`: context-aware `ArtisanCommand` scaffold. Detects plugin vs consumer-app context via `lib/src/*_artisan_provider.dart` presence; writes to `lib/src/commands/` (plugin) or `lib/app/commands/` (consumer); idempotent suffix handling (`Hello` and `HelloCommand` both produce `HelloCommand`); auto-prefixes signature with plugin name in plugin context; auto-registers the command in the nearest `ArtisanServiceProvider` (empty-list fallback supported).
- `commands:refresh`: regenerate the consumer's `lib/app/commands/_index.g.dart` auto-discovery index.

**Development loop**
- `start [--device=<id>]`: spawn `flutter run -d <device>` detached, record VM Service URI to `~/.artisan/state.json`.
- `stop`: SIGTERM the recorded `flutter run` process, delete `state.json`.
- `restart`: `stop` + `start`.
- `status`: print the recorded process status as JSON.
- `logs [--follow]`: print or tail the captured `flutter run` log.
- `reload`: send `r` (hot reload) to the running `flutter run` stdin.
- `hot-restart`: send `R` (hot restart, drops Dart state, keeps process).

**Inspection**
- `tinker`: connected REPL that evaluates Dart expressions against the running Flutter VM (Magic facade autocomplete + Eloquent model casting when the magic_tinker integration is loaded).
- `doctor`: preflight checks (flutter + dart on PATH, default port availability).
- `list`: every registered command grouped by `:` namespace.
- `help <cmd>`: detailed help for a single command.

**MCP Server**
- `mcp:serve [--include-tool <name>] [--exclude-tool <name>] [--include-package <pkg>] [--exclude-package <pkg>]`: start the MCP server (stdio JSON-RPC). Each flag is repeatable. Merges three filter layers: `.artisan/mcp.json` (file), `ARTISAN_MCP_TOOLS_*` / `ARTISAN_MCP_PACKAGES_*` (env), CLI flags. Cargo-style replace on the allow lists (CLI replaces env+file), union on the deny lists, deny wins over allow at every layer.
- `mcp:install [--path <file>]`: write (or update) the `mcpServers.fluttersdk` entry in `.mcp.json` (default: `.mcp.json` in cwd). Idempotent; preserves other server entries.
- `mcp:uninstall [--path <file>]`: remove the `mcpServers.fluttersdk` entry from `.mcp.json` (default: `.mcp.json` in cwd).

### MCP Server

Artisan absorbs `fluttersdk_mcp` into its core. The same binary that runs CLI commands now also serves Model Context Protocol (dart_mcp) tools over stdio JSON-RPC. No separate process or extra package is required.

**dart_mcp adoption**: the MCP server is built on the `dart_mcp` SDK. `mcp:serve` starts the JSON-RPC stdio server; `mcp:install` writes the client config entry; `mcp:uninstall` removes it. After install, reconnect the client once (`/mcp reconnect fluttersdk` in Claude Desktop).

**Plugin-contributed tool catalog**: every `ArtisanServiceProvider` subclass may override `mcpTools()` (default: empty list) to contribute tools. The server collects tools from all registered providers at startup. No manual registration step is required.

**Two tool layers**:

- **Substrate tools (9 always-on)**: a curated subset of artisan's own CLI commands surfaces as MCP tools via `McpServer._artisanCommandTools()` so an MCP client can bootstrap the Flutter app without ever leaving the chat. Dispatch runs in-process via the registry; no VM Service required. The 9: `artisan_start`, `artisan_stop`, `artisan_status`, `artisan_logs`, `artisan_restart`, `artisan_reload`, `artisan_hot_restart`, `artisan_doctor`, `artisan_list`. Per-command `inputSchema` is byte-verified against the underlying command's `configure(ArgParser)` declarations so the wire contract cannot drift from the CLI surface.
- **Plugin tools (up to 11 V1)**: contributed by `ArtisanServiceProvider.mcpTools()` overrides. Dispatch routes through `ext.*` VM Service extensions.
  - `fluttersdk_dusk` (6 tools): `dusk_snap`, `dusk_tap`, `dusk_screenshot`, `dusk_hover`, `dusk_drag`, `dusk_type`.
  - `fluttersdk_telescope` (4 tools): `telescope_tail`, `telescope_requests`, `telescope_clear`, `telescope_exceptions`.
  - `magic_tinker` (1 tool): `tinker_eval`.

**Soft-fail server lifecycle**: when `~/.artisan/state.json` is absent at `initialize` time (no Flutter app running), the server stays online with the 9 substrate tools available + 0 plugin tools registered. On the next `tools/call` requiring VM Service, the server lazy-reconnects via a memoized in-flight future (race-guarded so two concurrent calls share one connect attempt). This lets MCP clients survive the natural dev cycle of starting and stopping the Flutter app without ever reconnecting the server. Tool calls without a running app return `CallToolResult(isError: true)` whose text contains `Run \`artisan start\` to launch the Flutter app, then retry the tool call.` so the client model can self-correct.

**`bin/mcp.dart` canonical entry**: `dart run fluttersdk_artisan:mcp`. Forces `delegateToConsumer: false` so the substrate's complete builtin list (including `mcp:serve` itself) owns dispatch even when the cwd has a consumer `bin/artisan.dart` wrapper that might be missing the new `mcp:*` commands.

**Tool descriptions in canonical Claude Code format**: imperative opening sentence + brief context paragraph + `Usage:` bullet list + constraint-forward language. Per-property `inputSchema` descriptions carry defaults + concrete examples. Critical info first because CC truncates MCP descriptions at 2KB chars (`MAX_MCP_DESCRIPTION_LENGTH`). Pattern adopted from CC's built-in tool descriptions (Read / Write / Edit / Bash / Glob / AskUserQuestion).

**Three-layer filter** (Cargo-style precedence; deny wins at every layer):
1. File: `.artisan/mcp.json` `packages.deny` / `packages.allow` (lowest priority).
2. Env: `ARTISAN_MCP_TOOLS_DENY` / `ARTISAN_MCP_TOOLS_ALLOW` comma-separated tool names.
3. CLI: `--include-tool` / `--exclude-tool` / `--include-package` / `--exclude-package` flags on `mcp:serve` (highest priority; each repeatable).

Worked example: `.artisan/mcp.json` `{"packages":{"deny":["fluttersdk_telescope"]}}` removes 4 tools. `ARTISAN_MCP_TOOLS_DENY=dusk_snap` additionally removes `dusk_snap` regardless of the file. `--exclude-tool tinker_eval` on `mcp:serve` removes `tinker_eval` for that session. Result: 5 tools exposed.

### Plugin Contract Extension

`ArtisanServiceProvider` gains a new default-empty method `mcpTools()` that returns `List<McpToolDescriptor>`. Existing providers that do not override it continue to work without any change. Providers that want to expose MCP tools override the method and return their descriptor list (each carries `name`, `description`, `inputSchema` as a JSON Schema Map, and `extensionMethod` for VM Service dispatch); the MCP server collects these at startup automatically and routes tool calls through the matching `ext.*` VM Service extension.

`ArtisanRegistry` gains `mcpTools` getter (immutable view), `registerMcpToolsFor(provider)` (mirrors `registerAll` collision pattern), and `providerNameFor(toolName)` (filter attribution lookup). A new `ArtisanMcpToolCollisionException` mirrors the existing `ArtisanCommandCollisionException` shape: when two plugins declare the same tool name the registry throws with both provider names in the message so the operator knows which packages clashed (instead of dart_mcp's unattributed `StateError`).

`runArtisan(args, ...)` gains an optional `collectMcpTools: false` parameter and `delegateToConsumer: true` parameter. CLI invocations (`dart run :artisan list`) skip MCP collection entirely (no cost overhead). MCP server entry (`bin/mcp.dart`) opts in via `collectMcpTools: true` and opts out of consumer delegation via `delegateToConsumer: false`.

### Removed Packages: fluttersdk_mcp (absorbed into artisan core)

`fluttersdk_mcp` is retired as a standalone package. Its functionality (MCP server, tool catalog, filter pipeline) now lives in `fluttersdk_artisan` core under `lib/src/mcp/`. Consumer apps that previously added `fluttersdk_mcp` as a dependency should remove it; all MCP surface is available via `fluttersdk_artisan` alone.

### Plugin Protocol

- **Declarative `install.yaml` manifest**: `publish`, `magic.provider`, `magic.configFactory`, `magic.routes`, `native.android` (permissions, metaData, gradle plugins / dependencies), `native.ios` / `native.macos` (plistEntries), `native.web` (headInjections, metaTags), `env` (env var declarations with defaults + comments), `prompts` (interactive install prompts), `placeholders` (token resolution from prompt answers), `bootstrap_command` (post-install hint).
- **Procedural escape hatch**: subclass `ArtisanInstallCommand` and drive `PluginInstaller` directly for plugins that need runtime branching the YAML schema cannot express.

### PluginInstaller DSL

Fluent builder for install operations:
- File ops: `publishConfig`, `writeFile`, `mergeJson`.
- Source-injection ops: `injectImport`, `injectBefore`, `injectAfter`, `injectProvider`, `injectConfigFactory`, `injectRoute`.
- Native ops: `injectAndroidPermission`, `injectAndroidMetaData`, `injectAndroidGradlePlugin`, `injectAndroidGradleDependency`, `injectIosPlistEntry`, `injectIosPodEntry`, `injectMacosPlistEntry`, `injectMacosPodEntry`, `injectIntoWebHead`, `addWebMetaTag`.
- Env ops: `injectEnvVar`.

### Idempotency + Atomicity

- `ConflictDetector` runs against planned ops before commit; flags `unmanaged-file` when a target exists outside any recorded install (with `--force` override + scaffold-fingerprint heuristic that auto-allows default Flutter counter app overwrite).
- `InstallTransaction` writes via `.tmp` + atomic rename so concurrent readers never observe partial state.
- `ConfigEditor.insertCodeAfterPattern` + `insertCodeBeforePattern` skip when the target code is already present (no duplicate injections on re-install).
- `PluginInstaller.injectProvider` + `injectConfigFactory` append at the END of the list using lookahead-anchored regex (`(?=\s*\n\s*\])`); new entries surface where readers expect them; 6-space indent matches the scaffold style.

### Reversibility

`InstallTransaction` records every applied op to `.artisan/installed/<plugin>.json` (op type, target path, content hash for tamper detection on uninstall). `plugin:uninstall` walks the record in reverse: V1 reverses `WriteFile` (delete + restore via stub hash); logs `[skipped]` for `InjectImport` and `InjectAfterPattern` (manual reverse pending V1.1 with anchor-bracketed inject markers).

### VM Service Hooks

- `tinker` connects to the running Flutter app's VM Service, evaluates Dart expressions against the live isolate.
- `reload` / `hot-restart` write `r` / `R` to the `flutter run` process's stdin via FIFO bridge so detached processes still receive interactive commands.

### Context-Aware Generators

- `make:command` detects whether it is running inside a plugin (presence of `lib/src/*_artisan_provider.dart`) and routes the output + signature + registration accordingly.
- `make:plugin` detects whether `magic:install` is in the registry and renders the magic-mode add-ons (install.yaml + ServiceProvider + install/uninstall procedural commands) on top of the generic 7-file scaffold.
- Both generators leave commit history intact when re-run (idempotent file writes + idempotent provider list injection).

### Magic-Free Path

`consumer:scaffold` writes the canonical wrapper for plain Flutter projects that do not want a Magic framework dependency. After scaffold:
- `make:command` works against `lib/app/commands/` with `_index.g.dart` codegen.
- `plugin:install <name>` works against generic plugins (no `install.yaml` required) via direct registry write + `_plugins.g.dart` refresh.
- No manual `bin/artisan.dart` edit is required for any plugin once the scaffold is present.

Magic-managed consumers continue to get the equivalent wiring from `magic:install`.

### Testable Primitives

- `VirtualFs` interface + `InMemoryFs` implementation. Every installer pathway is unit-testable without touching the host filesystem.
- `InstallContext.test(fs, prompt, stubs, clock, projectRoot)` fixture builder.
- `ArtisanContext.bare(MapInput, BufferedOutput)` for command-level tests.
- `BufferedOutput` captures `info` / `success` / `warning` / `error` lines for assertion.
- `_TestablePluginInstallCommand` pattern (subclass-with-override) for pinning project root + manifest resolver in command tests.

### Programmatic API

- `runArtisan(args, baseProviders:, delegateToConsumer:)`: universal entry point. `delegateToConsumer: true` walks up looking for the consumer's wrapper and forwards execution (default for the `magic:artisan` binary).
- Single barrel: `package:fluttersdk_artisan/artisan.dart` exposes the full public surface (Application + Command + Input / Output + ServiceProvider + Context + VmServiceClient + StateFile + Stub system + Helpers + Installer + Registry).

### Documentation

- `README.md` with two-path Quick Start (Plain Flutter via `consumer:scaffold`, Magic-managed via `magic:install`) and the validated 5-step plugin authoring flow.
- `doc/install_yaml_schema.md`: every section + every key of the install.yaml manifest.
- AI agent integration via the `fluttersdk-artisan` skill (teaches signature DSL + plugin authoring + install.yaml + PluginInstaller DSL).

### Compatibility

- Dart `>=3.4.0 <4.0.0` (pub workspaces support requires `>=3.6.0` for the parent app; the artisan package itself stays on 3.4 for broader compatibility).
- Flutter required only for plugins that consume Flutter SDK APIs; the artisan core is pure Dart.
