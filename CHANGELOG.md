# Changelog

All notable changes to this project will be documented in this file.

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). Entries follow the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) shape.

---

## [0.0.14] - 2026-09-01

### Fixed

- **`injectEntitlement` wrote a file Xcode never read.** The op set the key in `ios/Runner/Runner.entitlements` and stopped, so unless somebody had already opened Xcode and added the capability by hand, `CODE_SIGN_ENTITLEMENTS` was unset and the entitlement was inert. The op now also points the application target at that file. Concretely this is what made an installer-driven iOS push setup impossible: the plist was correct and the build ignored it.
- **`PlistWriter` and `PodfileEditor` refused to edit a file that did not exist yet**, which is every Flutter project's entitlements file until somebody opens Xcode, and every Swift Package Manager project's Podfile always. Both now create the file first. `PlistWriter` creates ONLY an `.entitlements` path: an absent `Info.plist` still throws, because that means the caller has the wrong path and inventing one would hide it.
- **A created Podfile is now shaped for the platform it is created for.** `PodfileEditor`'s creation path is reached from `setPlatformVersion`, `addPostInstallHook` and `addPodLine`, and all three accept macOS, so the first cut wrote one iOS-shaped file for both: `platform :ios, '12.0'` and `flutter_install_all_ios_pods`. On a macOS project with no Podfile that produced a file nothing could build. `setPlatformVersion(path, 'macos', v)` matches `platform :osx`, missed the `:ios` line the creation had just written, and took its prepend branch, so the file ended up carrying TWO `platform` declarations; and `flutter_install_all_ios_pods` is not defined by the macOS half of Flutter's `podhelper.rb`, so `pod install` failed with an undefined method. Creation now takes the platform from the caller and emits `platform :osx` with `flutter_install_all_macos_pods` for macOS, which is also what makes the following `setPlatformVersion` REPLACE that line instead of adding a second one. The mapping lives in one place now, so the created file and the regex that later edits it cannot disagree again. Worth stating plainly, because it is a regression this branch introduced and not an old bug: before create-if-absent, that same call threw and wrote nothing. This is a helper-backed write path the installer does not roll back, so a wrong file has no undo.
- **A created Podfile called four Flutter helper functions and defined none of them, so `pod install` failed on both platforms.** The file said `flutter_install_all_ios_pods` (or the macOS one) and stopped there. Those are Ruby methods from Flutter's `packages/flutter_tools/bin/podhelper.rb`, and a Podfile only has them after it requires that file, which it can only do once it knows where the Flutter SDK is. So the whole preamble Flutter's `templates/cocoapods/Podfile-*` carry is load-bearing rather than decoration: a `flutter_root` function that reads `FLUTTER_ROOT` out of the generated xcconfig (`ios/Flutter/Generated.xcconfig` on iOS, `macos/Flutter/ephemeral/Flutter-Generated.xcconfig` on macOS, each raising a named error when it is absent because `flutter pub get` has not run), the `require` of `podhelper` relative to it, and the `flutter_ios_podfile_setup` / `flutter_macos_podfile_setup` call. The created file now carries all of it, generated from Flutter 3.47's own two templates, along with the analytics opt-out, the `project 'Runner'` build-configuration map and a `post_install` block calling the platform's `flutter_additional_*_build_settings`. It diverges from the templates in exactly two places, both deliberate: the iOS `platform` line is written uncommented, because `setPlatformVersion` edits that line and a commented one would make the bump inert, and the nested `target 'RunnerTests'` block is omitted, because CocoaPods aborts on a target name its `Runner.xcodeproj` does not carry and a project without a Podfile need not have a test target. Worth stating plainly: before this, the created file could not `pod install` on EITHER platform. The macOS fix above corrected which helper was named; it was still a name nothing defined.

- **`addPodLine` and `addPostInstallHook` refuse to create a Podfile when the caller does not name a platform.** Both gained an optional `platform:` argument; without it an absent file throws `FileSystemException` exactly as it did before this branch. Neither method can infer the platform from its own arguments, and a Podfile is platform-shaped down to the podhelper function it calls, so guessing produces the broken file described above. Refusing to create one is the recoverable failure. `setPlatformVersion` already takes the platform and creates as before.

- **`InjectPodfileLine` creates an absent Podfile again.** The refusal above cost the op the capability it was given earlier on this branch: `InstallTransaction` called `addPodLine` without `platform:`, so on a project whose `ios/` or `macos/` directory holds no Podfile (every Swift Package Manager project, always) the op stopped with `Podfile not found` instead of writing one. It carries `op.platform` and now forwards it, so both platforms get a file of the right shape. It is the only `PodfileEditor` call site in `lib/` that mutates a file; the other reference, `ConflictDetector`, only computes the path.
- **A created Podfile no longer declares a deployment target three major versions below the project's own.** It said `platform :ios, '12.0'`, a constant with nothing behind it; the created file now declares iOS `15.0` and macOS `12.0`, the values Flutter 3.47's own `flutter create` templates carry (`templates/cocoapods/Podfile-ios` and `Podfile-macos`), and iOS `15.0` is also the `IPHONEOS_DEPLOYMENT_TARGET` of the consumer this work was driven by. Reading the project's real target would beat any constant, but it lives in `Runner.xcodeproj/project.pbxproj` and the helper is handed a Podfile path only. Under-declaring is the harmful direction: CocoaPods then resolves pod versions older than the project can use.

### Added

- **`XcodeProjectEditor.setEntitlementsPath()`**, a trivia-preserving OpenStep-plist reader and writer for `.pbxproj`, with one public setter and no general mutation API. Three properties are load-bearing rather than incidental. It scopes the write to the `PBXNativeTarget` whose `productType` is `com.apple.product-type.application`, reached through its `buildConfigurationList`: a stock Flutter project holds nine `XCBuildConfiguration` blocks and only three are the app's, so a naive sweep would put a signing entitlement on the test bundle and the project defaults. It parses, re-emits and compares byte for byte before touching disk, and refuses rather than writing a partially-edited project, because a truncated `.pbxproj` cannot be opened and the installer's helper-backed ops do not roll back. And it never REPOINTS a configuration that already names a different entitlements file: every macOS Flutter project carries `Runner/DebugProfile.entitlements` and `Runner/Release.entitlements`, and silently overwriting those would drop the sandbox grants they hold.

## [0.0.13] - 2026-08-20

### Documentation

- **The docs still told readers the session is one global file, in ten files.** 0.0.10 moved the session to `~/.artisan/sessions/<hash>/` and the code changed with it, but the skill, the MCP tool descriptions and the command pages kept describing `~/.artisan/state.json` as the place the running app is recorded. This is not cosmetic: a field report has an agent concluding it had corrupted a sibling's session, because the tooling it was reading said there was only one slot to corrupt. It had reasoned correctly from a document that was wrong.

  Swept `skills/fluttersdk-artisan/SKILL.md` (including law 2, which stated the old model as a rule), `references/mcp-tools.md`, `references/tinker-eval.md`, `references/state-and-recovery.md`, `doc/mcp/{overview,setup,tool-reference}.md`, `doc/getting-started/quickstart.md`, `doc/commands/{index,start,tinker,mcp-serve}.md`. The mentions that remain are the ones that are still true: the legacy pointer exists, is read as a fallback, and is what the hand-written recovery recipe targets.

  Also corrected while there: the recovery for "no app detected" said to remove `~/.artisan/state.json`, which clears the pointer and not the session; the troubleshooting table quoted two error strings that no longer exist; and neither carried the `booting: true` path. Skill version 0.0.5 -> 0.0.6.

## [0.0.12] - 2026-08-20

### Fixed

- **A `start` interrupted by its caller left the app running and unrecorded.** The session was written only after the VM Service URI was scraped, which is the last and longest thing `start` waits for. An MCP client kills a tool call at 60s and an iOS build routinely takes longer, so the app came up, the process survived (the wrapper detaches it), and nothing recorded it: `status` answered `running: false` about an app that was listening on 8183, `stop` had no pid to reap, and the operator had to hand-write the state file. Reported from the field on `device=50BAD9FA-...`.

  The session is now written as soon as the child PIDs are known, carrying the pid, the FIFO, the ports and the device, with `vmServiceUri: null` and `booting: true` saying the record is incomplete rather than wrong. The URI is filled in when the scrape lands. And a connected command that finds no URI reads the last one out of the session log and keeps it, so an interrupted start heals on the next call instead of needing a hand-written file.

- **`status` reported an unfinished start as a healthy session.** That is where the reported symptom chain started: the operator read `running: false` about an app that was serving, concluded the start had failed, and went looking for a recovery. It now reports `booting: true` alongside the record and says in plain words that the URI is not there yet and how it gets filled in.

- **`artisan_start`'s MCP description still told agents the state was one global file.** "writes ... to `~/.artisan/state.json`" and "ONLY ONE Flutter app per machine can be tracked at a time (single-slot state)" have both been false since 0.0.10, and an agent acting on them concluded it had corrupted a sibling's session when the two were never sharing one. The description now says sessions are per project, and adds the line the timeout above needed: if the call times out the app is probably still starting, call `artisan_status`, and do not hand-write the state file. Same correction in the skill reference, whose recovery section also carried the old error text.

- **The documented state schema omitted `stdinPipe`, so following it produced a file that could not hot restart.** The docblock is the recipe an operator reaches for precisely when `start` has failed them, and it listed eleven keys without the one `reload` and `hot-restart` need. Both now document `stdinPipe`, `stdinHolderPid` and `booting`.

- **`reload` and `hot-restart` blamed an old artisan for a missing `stdinPipe`.** "the app was started by an older artisan that pre-dates the FIFO refactor" is one cause; a state file hand-written from the schema above is the likelier one now, and the message said nothing about what the key holds. Both messages name both causes and describe the value.

## [0.0.11] - 2026-08-20

### Fixed

- **The per-project session was keyed on the working directory, not the project, so the isolation only held for callers standing in the repo root.** `sessionOwnershipError` deliberately blesses running from `backend/` or a package subdirectory, but `sessionPathFor` hashed the cwd: a command from there missed its own session file, fell back to the shared `~/.artisan/state.json` pointer, and with two apps up was then refused for driving somebody else's. A false refusal, and the defeat of the very isolation 0.0.10 shipped.

  `StateFile.projectRootFor` now walks up to the nearest ancestor holding a `pubspec.yaml`. Nearest rather than outermost, because that is the unit `artisan start` boots: two packages in one repository are two apps and want two sessions. No pubspec anywhere up the chain falls back to the directory itself, so non-Dart callers and the hand-written recovery recipe do not all land in one shared session. `start` records the same walked root in `projectRoot`, since a raw cwd there would make a start from a subdirectory record a root the ownership check then measures every later command against.

## [0.0.10] - 2026-08-20

### Added

- **`artisan start` now records its session per project, so two apps can be driven at once.** `~/.artisan/state.json` was one global slot: a second project's `start` silently took it, and every connected command from the first project then drove the second app, succeeding each time. The measured case had a worktree in another repository rewrite the file mid-session, and two commands later produced a screenshot of an entirely different product. The session is now a DIRECTORY at `~/.artisan/sessions/<sha256(projectRoot)[0:12]>/`, holding `state.json`, the log and the FIFO, because those last two collided for exactly the same reason and fixing one member of the set is not fixing the set. Keyed by a digest rather than a slugified path, since a project path can contain separators, spaces and non-ASCII.

  `~/.artisan/state.json` is still written, as a pointer to whichever session started last. That is an interop contract, not a shim: hand-writing that file is the documented recovery recipe when `start` cannot boot an app, and `read()` falls back to it when this project has no session of its own. Two projects still need distinct `--port`, `--vm-service-port` and `--cdp-port`; `start` fails fast when one is taken.

- **`--state=<path>` and `ARTISAN_STATE_FILE` name the session explicitly.** A global flag consumed before dispatch rather than a per-command option, because every connected command needs it and none of them owns it. The flag wins over the environment variable, and naming a session also bypasses the ownership check below, since the caller has already answered the question it asks.

- **`status` reports `ownedByThisProject` and `projectRoot`.** It reads rather than acts, so it surfaces a foreign session instead of refusing it, but it must not present one as this project's: an agent reading `running: true` from a checkout with nothing up would conclude its own app is live and act on that.

- **`sessionOwnershipError` refuses a command that would act on another project's app.** The legacy pointer describes whichever app started last, so a `stop` run from a project with nothing up reached across and killed a sibling's running app while reporting a clean success, and a connected command dialled the wrong VM Service. Wired into the connected-mode boot path, `stop`, `reload` and `hot-restart`. A working directory INSIDE the project passes, state with no recorded `projectRoot` passes (hand-written recovery state usually omits it), and an explicit `--state` passes.

### Fixed

- **`--state=<path>` never reached the command when a consumer wrapper owned the invocation.** The flag is consumed before dispatch into a static on this isolate, but a wrapper delegation spawns a SEPARATE Dart process, and the stripped args carried nothing across. `artisan stop --state=/x` from any project with a `bin/dispatcher.dart` therefore acted on the auto-resolved session instead, silently: the exact failure the flag exists to prevent, on the exact path most consumers take. The flag is now re-attached to the delegated args. `ARTISAN_STATE_FILE` was unaffected, since the child inherits the environment.

- **The ownership check ignored `ARTISAN_STATE_FILE`, so it refused the session that variable had just pointed it at.** `StateFile.path` honours the flag and the environment variable equally, and the two are documented as equivalent, but all five guard call sites read the flag alone. With the variable set and no flag, artisan read the named foreign session and then declined to drive it. `StateFile.explicitPath()` now answers "did the caller name a session", by either spelling.

- **`artisan restart` ignored `stop`'s refusal and relaunched on the other project's settings.** `restart` is `CommandBoot.none`, so the connected-mode guard never runs, and it discarded `StopCommand.handle`'s exit code. Run from project A while the pointer described B: stop printed the refusal and returned 1, restart carried on, and `sessionOverridesFrom` carried B's web port, VM Service port, CDP port and device into A's relaunch, reproducing the `Address already in use` this same release set out to fix. A non-zero stop now aborts the restart.

- **Two `artisan start` runs raced on the shared pointer's staging file.** Every write goes through `.tmp` + rename, but the legacy pointer is one path for every project, so both processes staged `~/.artisan/state.json.tmp` and the loser's rename threw `FileSystemException` after `flutter run` had already spawned, leaving an orphan with no state file to find it by. The staging name now carries the pid. The per-project session files were never affected; the mirror re-introduced the shared slot they exist to remove.

- **`StateFile.delete` compared paths exactly and deleted an unattributed pointer.** A `stop` from a subdirectory has no session file of its own, so the fallback root is that subdirectory and the pointer was left behind, still advertising a session that had just been stopped; the check now uses the same is-within rule as `sessionOwnershipError`. A pointer with no recorded `projectRoot` is now left alone: that is the hand-written recovery file the read path goes out of its way to honour, and deleting it took away the escape hatch people reach for precisely when `start` has already failed them.

- **`artisan restart` relaunched on the default web port, VM Service port and device, keeping only the CDP port.** Several worktrees run their own dev server at once, so 3100 is usually held by a sibling: the stop half succeeded, the relaunch failed with `Address already in use`, and the app being driven was simply gone. The error names a port that appears in no command the caller ran, so it reads as a machine problem rather than a missing flag. A restart onto the default web-server device is quieter and worse: nothing renders, and every screenshot after it comes back byte-identical. `restart` now carries the device and all three ports across, and declares each as a flag so an explicit value still wins.

- **`logs` looked for `flutter-dev.log` beside the state file**, which now resolves inside the session directory. It reads the session log and falls back to the shared `~/.artisan/flutter-dev.log` for an app started by an older artisan.

- **`artisan_start`'s tool description pointed agents at a tool that does not exist.** Two lines of the description listed `tinker_eval` among the tools that read `~/.artisan/state.json`; the tool is `artisan_tinker`. An agent taking the description at its word calls a name the server never registered and gets an unknown-tool error. Also corrected the same stale name in `McpToolDescriptor`'s own docstring example. (`lib/src/mcp/mcp_server.dart`, `lib/src/mcp/mcp_tool_descriptor.dart`, `skills/fluttersdk-artisan/references/mcp-tools.md`, `skills/fluttersdk-artisan/references/tinker-eval.md`)
- **The MCP server reported itself as `0.0.8` to every client.** The `Implementation.version` string in `McpServer` carries the comment "Keep in sync with pubspec.yaml `version:` on each release cut" and was missed on the 0.0.9 cut, so an MCP client's initialize handshake read a version one release behind while the package on disk was 0.0.9. Client-side version gating and bug reports both keyed on the wrong number. (`lib/src/mcp/mcp_server.dart`)

### Documentation

- **The registry dispatch fires on a published release now, not on every push that touches the skill.** Under the push trigger `fluttersdk/ai` climbed to v1.3.75, and most of those releases re-published identical skill content: a docs commit and a release commit each cost the registry a version. The registry version now tracks published artisan releases instead of counting commits. `workflow_dispatch` stays as the manual escape hatch when a skill fix has to reach users before the next release. (`.github/workflows/dispatch-to-registry.yml`)
- **The skill undercounted the builtin commands by one and the CLI-only set with it.** `make:fast-cli` landed in 0.0.2 and the counts were never rolled forward, so the skill promised "21 builtin CLI commands" and "11 CLI-only" against a real 22 and 12. Corrected in the frontmatter description, Core Law 6, the section 14 reference table, and the `references/cli-commands.md` title, intro, and `artisan_list` heading. Core Law 6's inline list was 11 items long against its own count of 12: `mcp:uninstall` was missing, and it is now in both the list and the exclusion-reason table. (`skills/fluttersdk-artisan/SKILL.md`, `skills/fluttersdk-artisan/references/cli-commands.md`)
- **`start --timeout=<seconds>` was undiscoverable from the skill.** 0.0.9 made the VM Service URI scrape window configurable, but the skill still presented 90s as a fixed property of `start` in three places, so an agent facing a slow cold boot had no documented way out and would conclude the boot was broken. The MCP schema exposes no timeout parameter, which makes this a CLI-only escape hatch worth naming explicitly. (`skills/fluttersdk-artisan/SKILL.md`, `skills/fluttersdk-artisan/references/mcp-tools.md`, `skills/fluttersdk-artisan/references/state-and-recovery.md`)
- The skill cited the substrate allowlist as `mcp_server.dart:871-882`; the range had drifted by two lines. Both citations now name the `_safeArtisanCommandNames` constant instead, which does not rot when the file moves. (`skills/fluttersdk-artisan/SKILL.md`, `skills/fluttersdk-artisan/references/mcp-tools.md`)
- Skill version 0.0.4, stamped against package 0.0.9. The previous stamp claimed 0.0.7, which predates the `--timeout` flag and the `restart` CDP-port preservation the skill now describes. (`skills/fluttersdk-artisan/SKILL.md`)

## [0.0.9] - 2026-07-29

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

---

[0.0.14]: https://github.com/fluttersdk/artisan/compare/0.0.13...0.0.14
[0.0.13]: https://github.com/fluttersdk/artisan/compare/0.0.12...0.0.13
[0.0.12]: https://github.com/fluttersdk/artisan/compare/0.0.11...0.0.12
[0.0.11]: https://github.com/fluttersdk/artisan/compare/0.0.10...0.0.11
[0.0.10]: https://github.com/fluttersdk/artisan/compare/0.0.9...0.0.10
[0.0.9]: https://github.com/fluttersdk/artisan/compare/0.0.8...0.0.9
[0.0.8]: https://github.com/fluttersdk/artisan/compare/0.0.7...0.0.8
[0.0.7]: https://github.com/fluttersdk/artisan/compare/0.0.6...0.0.7
[0.0.6]: https://github.com/fluttersdk/artisan/compare/0.0.5...0.0.6
[0.0.5]: https://github.com/fluttersdk/artisan/compare/0.0.4...0.0.5
[0.0.4]: https://github.com/fluttersdk/artisan/compare/0.0.3...0.0.4
[0.0.3]: https://github.com/fluttersdk/artisan/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/fluttersdk/artisan/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/fluttersdk/artisan/releases/tag/0.0.1
