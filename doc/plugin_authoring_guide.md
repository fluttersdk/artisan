# Plugin Authoring Guide

A complete guide to writing, testing, and publishing a `fluttersdk_artisan`
plugin. Artisan plugins are ordinary Dart packages that ship one or more
`ArtisanCommand` subclasses plus optional install and uninstall commands wired
through the `PluginInstaller` DSL.

---

## 1. Overview

`fluttersdk_artisan` gives plugin authors the same install-automation primitives
that Laravel package developers have through service providers and auto-discovery,
adapted for the Dart and Flutter ecosystem.

A plugin typically does four things:

1. **Ships commands.** Each command is a subclass of `ArtisanCommand` (for
   general commands) or `ArtisanGeneratorCommand` (for `make:*` generators).
2. **Declares them through an `ArtisanServiceProvider`.** The provider exposes a
   `List<ArtisanCommand>` that consumers register in one line in their
   `bin/artisan.dart`.
3. **Installs itself.** An install command (or a declarative `install.yaml`)
   adds pubspec dependencies, publishes config stubs, injects service providers
   into the consumer's `lib/config/app.dart`, wires native permissions, and runs
   `flutter pub get`, all atomically with conflict detection.
4. **Uninstalls itself.** A companion uninstall command reads the install record
   written on success and reverses every file-level operation.

Everything in this guide uses the public barrel: `package:fluttersdk_artisan/artisan.dart`.
No internal imports are needed.

---

## 2. Quick Start

### Scaffold the skeleton

```bash
dart run fluttersdk_artisan make:plugin foo_bar
```

This generates 11 files under `packages/foo_bar/`:

```
packages/foo_bar/
├── pubspec.yaml
├── install.yaml
├── lib/
│   ├── cli.dart                            # ArtisanServiceProvider barrel
│   ├── foo_bar.dart                        # runtime barrel
│   └── src/
│       ├── foo_bar_artisan_provider.dart   # FooBarArtisanProvider
│       └── commands/
│           ├── install_command.dart        # foo_bar:install
│           └── uninstall_command.dart      # foo_bar:uninstall
├── assets/stubs/install/
│   └── foo_bar_config.dart.stub           # sample config stub
└── test/
    ├── install_command_test.dart
    └── uninstall_command_test.dart
```

### Register in the consumer project

In the consumer's `bin/artisan.dart`:

```dart
import 'package:foo_bar/cli.dart';

// inside main():
registry.registerProvider(FooBarArtisanProvider());
```

### Run the install command

```bash
dart run artisan foo_bar:install
```

The install command (or `install.yaml`) adds the pubspec dependency, publishes
the config stub, injects the service provider, and records the result in
`.artisan/installed/foo_bar.json`.

---

## 3. The install.yaml Schema

`install.yaml` is the declarative alternative to writing a Dart install command
from scratch. Most plugins only need a handful of sections and can ship zero Dart
install logic.

Full schema: [install_yaml_schema.md](install_yaml_schema.md)

### Minimal example

```yaml
plugin_name: foo_bar

dependencies:
  runtime:
    - name: some_dep
      version: "^2.0.0"

publish:
  - stub: install/foo_bar_config.dart.stub
    target: lib/config/foo_bar.dart

magic:
  providers:
    - FooBarServiceProvider
```

### Execution order

`ManifestInstaller` applies sections in a fixed sequence regardless of the order
they appear in the YAML file:

1. Prompts (IMMEDIATE, before any deferred ops)
2. Dependencies
3. Pubspec assets
4. Publish (file stubs)
5. JSON merges
6. Magic injections (providers, config factories, routes)
7. Native injections (Android, iOS, macOS)
8. Web injections
9. Env vars
10. Post-install shell commands

---

## 4. The PluginInstaller Fluent Builder

Use `PluginInstaller` inside a Dart install command when you need logic that
goes beyond what `install.yaml` supports: conditional ops, loops, var
substitution from prompt answers, or any operation that reads runtime state.

### Basic shape

```dart
import 'package:fluttersdk_artisan/artisan.dart';

// Inside your install command's handle():
final ctx = InstallContext.real(artisanContext);
final result = await PluginInstaller(ctx, pluginName: 'foo_bar')
    .startWith((c) => c.artisanContext.output.info('Installing foo_bar...'))
    .addDependency('intl', '^0.20.0')
    .publishConfig(
      stubName: 'install/foo_bar_config.dart.stub',
      targetPath: 'lib/config/foo_bar.dart',
    )
    .injectProvider('FooBarServiceProvider')
    .askToRunShell(
      prompt: 'Run flutter pub get now?',
      command: 'flutter',
      args: ['pub', 'get'],
    )
    .endWith((c) => c.artisanContext.output.success('foo_bar installed.'))
    .commit(dryRun: false, force: false);
```

`PluginInstaller` is one-shot: construct a new instance per install pass.
Calling `commit()` twice on the same instance throws `StateError`.

### Method catalog

#### Pubspec

| Method | What it does |
|--------|-------------|
| `addDependency(name, version)` | Adds to `dependencies:` |
| `addDevDependency(name, version)` | Adds to `dev_dependencies:` |
| `addPathDependency(name, path)` | Adds a relative-path dependency |
| `removeDependency(name)` | Removes from either map (idempotent) |
| `addPubspecAsset(assetPath)` | Appends to `flutter.assets` |

#### File

| Method | What it does |
|--------|-------------|
| `publishConfig(stubName:, targetPath:, replacements:)` | Loads a stub, substitutes placeholders, writes the result |
| `writeFile(targetPath:, content:)` | Writes raw content verbatim |
| `deleteFile(targetPath)` | Deletes a file (idempotent) |
| `copyFile(sourcePath:, targetPath:)` | Copies source to destination |
| `mergeJson(targetPath:, sourceData:, additive:)` | Deep-merges a map into an existing JSON file |

#### Inject (Dart code)

| Method | What it does |
|--------|-------------|
| `injectImport(targetFile:, importStatement:)` | Appends an import to any Dart file |
| `injectBefore(targetFile:, pattern:, code:)` | Inserts code before the first pattern match |
| `injectAfter(targetFile:, pattern:, code:)` | Inserts code after the first pattern match |
| `injectMainDartImport(importStatement)` | Appends an import to `lib/main.dart` |
| `injectBeforeMagicInit(code)` | Inserts code before `Magic.init(...)` |
| `injectAfterMagicInit(code)` | Inserts code after `Magic.init(...)` |
| `wrapRunApp(wrapperName)` | Wraps `runApp`'s argument in a widget |
| `injectProvider(className, {package})` | Adds provider to `lib/config/app.dart` |
| `injectConfigFactory(factoryName, {package})` | Adds a config factory to `lib/main.dart` |
| `injectRoute(registerFunctionName)` | Calls a route-registration function in `RouteServiceProvider.boot()` |

#### Native

| Method | What it does |
|--------|-------------|
| `injectAndroidPermission(permission)` | Adds a `<uses-permission>` to `AndroidManifest.xml` |
| `injectAndroidMetaData(name:, value:)` | Adds a `<meta-data>` element inside `<application>` |
| `injectInfoPlistKey(key:, value:, platform:)` | Sets a plist key (`String`, `bool`, or `List<String>`) |
| `injectEntitlement(platform:, key:, value:)` | Sets a value in `Runner.entitlements` |
| `injectPodfileLine(platform:, line:)` | Appends a pod declaration to the `target 'Runner'` block |
| `injectGradlePlugin(pluginId:, version:)` | Adds to `plugins { }` in `build.gradle.kts` |
| `injectGradleDependency(scope:, notation:)` | Adds a Gradle dependency |

#### Web

| Method | What it does |
|--------|-------------|
| `injectIntoWebHead(content)` | Inserts raw HTML before `</head>` in `web/index.html` |
| `addWebMetaTag(attributes)` | Adds a `<meta>` element to `web/index.html` |

#### Env

| Method | What it does |
|--------|-------------|
| `injectEnvVar(key:, value:)` | Writes `KEY=value` to `.env` (creates the file when absent) |

#### Interactive (IMMEDIATE)

These methods run synchronously at the point of the call. The captured answer
is available via `installer.vars['varName']` for subsequent chain methods.

| Method | What it does |
|--------|-------------|
| `ask(varName:, question:, defaultValue:, validator:)` | Prompts for a string answer |
| `confirm(varName:, question:, defaultValue:)` | Prompts yes/no; stores `'true'` or `'false'` |
| `choice(varName:, question:, options:, defaultValue:)` | Prompts for one of the listed options |

#### Shell

| Method | What it does |
|--------|-------------|
| `runShell(command:, args:, workingDir:)` | Runs an external process after commit |
| `askToRunShell(prompt:, command:, args:)` | Prompts immediately; enqueues shell op when confirmed |

#### Hooks

| Method | When it fires |
|--------|--------------|
| `startWith(hook)` | Immediately before the ops dispatch (even on failure) |
| `endWith(hook)` | Only after `Success` |

### IMMEDIATE vs. DEFERRED

Chain methods fall into two categories that determine when their effect is
visible.

**IMMEDIATE** methods run synchronously when called: `ask`, `confirm`, `choice`,
`startWith`, `endWith`, `askToRunShell` (the prompt half). Use the `vars` getter
after an IMMEDIATE call to branch on the captured answer:

```dart
installer
    .confirm(varName: 'enableX', question: 'Enable feature X?')
    // vars is readable immediately after confirm():
    .addDependency('feature_x', '^1.0.0'); // always added, regardless of answer
// Branch after the chain using vars:
if (installer.vars['enableX'] == 'true') {
  installer.publishConfig(
    stubName: 'install/feature_x_config.dart.stub',
    targetPath: 'lib/config/feature_x.dart',
  );
}
```

**DEFERRED** methods enqueue an `InstallOperation`; nothing touches the
filesystem until `commit()` is called.

---

## 5. InstallContext + Testing Patterns

`InstallContext` is the dependency-injection container handed to every install
operation. It has two named constructors:

- `InstallContext.real(artisanContext)` wires production drivers.
- `InstallContext.test(fs:, prompt:, stubs:)` accepts explicit fakes for
  in-memory tests.

### Writing a unit test

```dart
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  test('install publishes config and injects provider', () async {
    final fs = InMemoryFs();
    // Seed the file the install command will inject into.
    fs.write(
      '/test/lib/config/app.dart',
      "final config = {'providers': []};\n",
    );

    final ctx = InstallContext.test(
      fs: fs,
      prompt: FakePromptDriver(answers: ['y']),
      stubs: FakeStubDriver({'install/foo_bar_config.dart.stub': '// config'}),
    );

    final result = await PluginInstaller(ctx, pluginName: 'foo_bar')
        .publishConfig(
          stubName: 'install/foo_bar_config.dart.stub',
          targetPath: 'lib/config/foo_bar.dart',
        )
        .injectProvider('FooBarServiceProvider')
        .commit(dryRun: false, force: false);

    expect(result, isA<Success>());
    expect(fs.read('/test/lib/config/foo_bar.dart'), '// config');
  });
}
```

### Key test doubles

| Double | Purpose |
|--------|---------|
| `InMemoryFs` | Replaces real filesystem reads and writes |
| `FakePromptDriver` | Replays pre-seeded answers (`ask` / `confirm` / `choice`) |
| `FakeStubDriver` | Returns pre-seeded stub content by name |

### Note on helper-backed ops

Several ops (`injectProvider`, `injectConfigFactory`, `injectAndroidPermission`,
native ops, env ops) use legacy helper classes that write through `dart:io`
directly, bypassing `InMemoryFs`. Tests for those ops must point `projectRoot`
at a real temporary directory created with `Directory.systemTemp.createTempSync()`.
See `test/` in the scaffolded skeleton for the pattern.

---

## 6. Conflict Handling and the User-Modified-File Flow

### What counts as a conflict

The `InstallTransaction` runs a conflict pre-flight before touching any file. A
file is considered user-modified when:

- The target already exists, AND
- Its content differs from the known original (tracked via the install record),
  OR no install record exists for that file (first install or manually edited).

### Default behavior

On conflict the transaction returns a `Conflict` result (not `Error`). No files
are written. The conflict report lists each file with a one-line diff summary.
The consumer can then:

1. Resolve manually and re-run the install command, OR
2. Re-run with `--force` to overwrite.

### When to use `--force`

Use `--force` when you own the conflict: for example, when re-running an install
on a fresh CI environment where the "user-modified" flag was set by a previous
failed install, not by a human editor.

### When NOT to use `--force`

Never document `--force` as the default recovery path for end users. When a
plugin install modifies a file the user intentionally customized, overwriting
silently destroys that work. Instead, design your stubs so that the critical
install-time content lives in a separate file the user is not expected to edit
(a config stub), and use injection methods (`injectProvider`, `injectAfter`) for
the minimal changes to existing files.

### Designing for zero conflicts

The lower the surface area of your install, the less likely conflicts become:

- Publish config to a new file, never to an existing one.
- Use `injectAfter` / `injectBefore` for small surgical additions; do not
  rewrite entire sections.
- Avoid publishing to `lib/main.dart` directly when `injectProvider` or
  `injectConfigFactory` suffice.

---

## 7. Uninstall: Manifest-Driven Reverse + Record/Replay

### How uninstall works

`plugin:uninstall foo_bar` performs these steps in order:

1. Verifies `.artisan/installed/foo_bar.json` exists. Without a record, there
   is no install plan to reverse.
2. Resolves and parses the plugin's `install.yaml` (the package must still be
   a pubspec dep at uninstall time).
3. Prompts for confirmation unless `--force` or `--non-interactive` is set.
4. On `--dry-run`, prints the planned reverse ops and exits without writing.
5. Delegates to `ManifestInstaller.uninstall`, which derives reverse operations
   from the record and commits a fresh reverse transaction.
6. Removes the plugin's import line and `registerProvider` line from
   `bin/artisan.dart`.

### V1 limitation

The install record persists the full typed payload for EVERY op subclass
(WriteFile, CopyFile, PublishFile, AddDependency, AddPathDependency,
RemoveDependency, AddPubspecAsset, MergeJson, InjectImport,
InjectBeforePattern, InjectAfterPattern, InjectAndroidPermission,
InjectAndroidMetaData, InjectInfoPlistKey, InjectEntitlement,
InjectPodfileLine, InjectGradlePlugin, InjectGradleDependency, InjectEnvVar,
InjectIntoWebHead, AddWebMetaTag, InjectMainDartImport, InjectIntoMainDart,
InjectRouteRegistration, RunShell). Reconstruction is therefore lossless.

The V1 trade-off lives in `reverseOf`: only file-creating ops have a typed
reverse op available.

| Recorded op | V1 reverse | Action required |
|-------------|------------|-----------------|
| `WriteFile` / `CopyFile` / `PublishFile` | `DeleteFile(targetPath)` | None, auto-reversed. |
| `AddDependency` / `AddPathDependency` | `RemoveDependency(name)` | None, auto-reversed. |
| `RemoveDependency` | none | Manual: re-add via pubspec. |
| `DeleteFile` | none | Manual: re-create the file from VCS. |
| `MergeJson` | none | Manual: revert via VCS or hand-edit. |
| `AddPubspecAsset` | none | Manual: remove the entry from `flutter.assets`. |
| `InjectImport` / `InjectBeforePattern` / `InjectAfterPattern` | none | Manual: remove the injected lines. |
| `InjectMainDartImport` / `InjectIntoMainDart` | none | Manual: remove the injected lines from `lib/main.dart`. |
| `InjectRouteRegistration` | none | Manual: remove the `registerXRoutes()` call from `route_service_provider.dart`. |
| `InjectAndroidPermission` | none | Manual: remove the `<uses-permission>` line from `AndroidManifest.xml`. |
| `InjectAndroidMetaData` | none | Manual: remove the `<meta-data>` line from `AndroidManifest.xml`. |
| `InjectInfoPlistKey` / `InjectEntitlement` | none | Manual: remove the key+value pair from the plist / entitlements file. |
| `InjectPodfileLine` | none | Manual: remove the `pod '...'` line from the platform Podfile. |
| `InjectGradlePlugin` / `InjectGradleDependency` | none | Manual: remove the plugin / dependency line from `build.gradle(.kts)`. |
| `InjectEnvVar` | none | Manual: remove the `KEY=VALUE` line (and any preceding `# comment`) from `.env`. |
| `InjectIntoWebHead` / `AddWebMetaTag` | none | Manual: remove the markup from `web/index.html`. |
| `RunShell` | none | Manual: side effects are unknowable. |

`ManifestInstaller.uninstall` surfaces a single warning line listing every
skipped op so the operator knows exactly which manual cleanup steps to perform.
Auto-reverse for the non-`Delete*`/`Remove*` ops lands in V1.x once `removeX`
helpers exist on each editor (`XmlEditor.removeAndroidPermission`,
`MainDartEditor.removeImport`, `EnvEditor.removeKey`, etc.). Plugin authors
should document the manual cleanup steps inside their README under a
"Manual uninstall" section so end users have a single source of truth for
their plugin specifically.

### The `bootstrap_command` pattern

When your plugin ships a secondary setup step that the end user must run after
the base install (for example, `foo_bar:setup --interactive`), declare it in
`install.yaml` as:

```yaml
bootstrap_command: foo_bar:setup
```

`plugin:install` prints a "Next: run `dart run artisan foo_bar:setup`" banner
after success, guiding the user to the next step without baking the interactive
step into the install flow itself. This keeps the install command idempotent and
CI-friendly.

---

## 8. Common Recipes

### Recipe 1: Config-only plugin

A plugin that only publishes a config file and injects a service provider.
No native wiring, no env vars.

**install.yaml:**

```yaml
plugin_name: foo_bar

dependencies:
  runtime:
    - name: foo_bar
      version: "^1.0.0"

publish:
  - stub: install/foo_bar_config.dart.stub
    target: lib/config/foo_bar.dart

magic:
  providers:
    - FooBarServiceProvider
```

**Consumer result after install:**

- `lib/config/foo_bar.dart` created from stub.
- `lib/config/app.dart` has `(app) => FooBarServiceProvider(app),` injected.
- `flutter pub get` prompted.

### Recipe 2: Native permissions plugin (camera, microphone, etc.)

```dart
final ctx = InstallContext.real(artisanContext);
final result = await PluginInstaller(ctx, pluginName: 'foo_camera')
    .addDependency('camera', '^0.10.0')
    .injectAndroidPermission('android.permission.CAMERA')
    .injectInfoPlistKey(
      key: 'NSCameraUsageDescription',
      value: 'Required to capture images.',
      platform: 'ios',
    )
    .injectInfoPlistKey(
      key: 'NSCameraUsageDescription',
      value: 'Required to capture images.',
      platform: 'macos',
    )
    .askToRunShell(
      prompt: 'Run flutter pub get now?',
      command: 'flutter',
      args: ['pub', 'get'],
    )
    .commit(dryRun: false, force: false);
```

Each native op is silently skipped on platforms where the target directory is
absent, so the same install command works on single-platform and multi-platform
consumer projects.

### Recipe 3: ServiceProvider-injecting plugin

A plugin that registers a Magic `ServiceProvider` into the consumer's
`lib/config/app.dart`. The consumer's `app.dart` must declare the providers
list as a Dart map literal with a `'providers': [...]` key.

```dart
final ctx = InstallContext.real(artisanContext);
final result = await PluginInstaller(ctx, pluginName: 'foo_bar')
    .addDependency('foo_bar', '^1.0.0')
    .publishConfig(
      stubName: 'install/foo_bar_config.dart.stub',
      targetPath: 'lib/config/foo_bar.dart',
    )
    // Adds import + provider closure in one call:
    .injectProvider('FooBarServiceProvider')
    // Also inject a config factory in main.dart:
    .injectConfigFactory('fooBarConfig')
    .commit(dryRun: false, force: false);
```

`injectProvider` generates:

```dart
// Added to lib/config/app.dart:
import 'package:foo_bar/foo_bar.dart';
// Inside 'providers': [...]
    (app) => FooBarServiceProvider(app),
```

If the consumer's `app.dart` does not follow the expected shape, the
after-pattern injection silently no-ops and the install still reports Success.
Document this requirement in your plugin README.

---

## 9. Contributing MCP Tools (`mcpTools()`)

Artisan ships a built-in MCP (Model Context Protocol) server: the same binary that runs CLI commands also serves stdio JSON-RPC tools to Claude / Cursor / Windsurf via `dart run fluttersdk_artisan:mcp`. Plugins contribute tools through the same `ArtisanServiceProvider` that registers commands.

### The contract

`ArtisanServiceProvider` defines a default-empty `mcpTools()` method. Override it to return a list of `McpToolDescriptor`s. The MCP server collects descriptors from every registered provider at `initialize` time and surfaces them to the client. No separate registration step is required.

```dart
class AwesomePluginArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'fluttersdk_awesome';

  @override
  List<ArtisanCommand> commands() => [AwesomePingCommand()];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
        McpToolDescriptor(
          name: 'awesome_ping',
          description: 'Ping the awesome service and return latency.\n'
              '\n'
              'Calls the running app\'s `ext.awesome.ping` VM Service '
              'extension with the provided URL and returns the measured '
              'latency in milliseconds. Use to verify connectivity from '
              'the running Flutter app without rebuilding the UI.\n'
              '\n'
              'Usage:\n'
              '- Required: `url` (string). Must include scheme.\n'
              '- Returns: `{latency_ms: <int>, status: <code>}`.\n'
              '- Errors when the app has no `ext.awesome.ping` handler '
              'registered; the plugin\'s runtime must call '
              '`registerExtension(\'ext.awesome.ping\', handler)` during '
              '`AwesomePlugin.install()`.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'url': <String, dynamic>{
                'type': 'string',
                'description':
                    'Target URL including scheme (e.g. `https://api.example.com`).',
              },
            },
            'required': <String>['url'],
          },
          extensionMethod: 'ext.awesome.ping',
        ),
      ];
}
```

### Description format

Tool descriptions follow Claude Code's canonical format: imperative opening sentence + brief context paragraph + `Usage:` bullet list + constraint-forward language. Put the critical info first; CC truncates MCP descriptions at 2,048 chars. Per-property `inputSchema` descriptions should include defaults + concrete examples so the model picks the right argument shape without guessing. The artisan substrate's own `artisan_start` / `artisan_doctor` / `artisan_logs` descriptions (in `lib/src/mcp/mcp_server.dart`) are the canonical reference.

### Dispatch

Plugin tools route through `ext.*` VM Service extensions: when the MCP client invokes the tool, the server calls `vmClient.callServiceExtension(extensionMethod, isolateId, args)` and wraps the result in `CallToolResult(content: [TextContent(text: jsonEncode(result))])`. The plugin's runtime side (typically a `XxxPlugin.install()` method called from the app's `main.dart`) must register the matching extension method. Errors propagate as `CallToolResult(isError: true)` so the client model can self-correct.

For a substrate-command-style tool that does NOT need a running app (a tool that dispatches to in-process Dart code), use a sentinel `extensionMethod` like `local:<tool-name>` and add a routing branch in your plugin's own MCP wrapping; artisan does not currently expose a public hook for non-VM-Service dispatch outside the substrate `artisan_*` allowlist.

### Filtering

The 3-layer filter (`.artisan/mcp.json` file + env vars + CLI flags) applies to plugin tools the same way it applies to substrate tools. A user can deny your entire plugin via `--exclude-package fluttersdk_awesome` or a specific tool via `--exclude-tool awesome_ping`. Provider name as reported by `ArtisanServiceProvider.providerName` is the filter key for package-level deny; tool name (from `McpToolDescriptor.name`) is the key for tool-level deny.

### Testing

Plugin tools are unit-testable via the same `_FakeMcpProvider` pattern used in `references/fluttersdk_artisan/test/mcp/mcp_server_test.dart`. Build an `ArtisanRegistry`, call `registerMcpToolsFor(_FakeMcpProvider(providerName: 'x', tools: [_tool('awesome_ping')]))`, spawn `McpServer.test(channel: ..., registry: registry, filter: McpFilterConfig.empty(), vmClientFactory: (_) => _StubVmServiceClient(...), stateReader: () async => ...)`, then drive it through a real `MCPClient` over an in-memory `StreamChannelController` pair. The pattern is documented in the existing test file; copy-paste the stub + harness for your plugin's test suite.

### Consumer-side wiring

Once your plugin ships `mcpTools()`, the consumer app's `bin/artisan.dart` wrapper needs to register your `ArtisanServiceProvider` (uncomment or add the `registry.registerProvider(AwesomePluginArtisanProvider())` line). The MCP server picks up the tools automatically on the next `mcp:serve` invocation; the user reconnects their MCP client via `/mcp reconnect fluttersdk` to refresh the tool manifest.

---

## 10. Anti-Patterns

### Do not bypass `InstallTransaction`

Writing to the filesystem directly inside your install command (using `File`,
`FileHelper.writeFile`, or any `dart:io` surface) bypasses the conflict
pre-flight, the atomic `.tmp` swap, and the install record. If the command
crashes mid-run, the consumer project is left in a partially modified state with
no record to uninstall from.

Always go through `PluginInstaller` chain methods or `install.yaml` so that
every mutation is staged, conflict-checked, and recorded.

```dart
// Bad: writes directly, no conflict detection, no record.
File('lib/config/foo_bar.dart').writeAsStringSync('...');

// Good: staged through the DSL.
installer.writeFile(targetPath: 'lib/config/foo_bar.dart', content: '...');
```

### Do not skip conflict detection with blanket `--force`

Passing `force: true` to `commit()` unconditionally is tempting when writing
early versions of your install command. Resist it. Conflict detection is the
mechanism that prevents your plugin from destroying user customizations. Use
`force: true` only when you have asked the user explicitly via a `confirm` call
and they acknowledged the consequences.

### Do not hard-code `projectRoot`

Never assume the project root is the current directory. Use
`InstallContext.real(artisanContext)` in production and
`InstallContext.test(projectRoot: '/test')` in tests. The
`FileHelper.findProjectRoot()` call inside `InstallContext.real` walks up from
`Directory.current` to find the nearest `pubspec.yaml`, which is correct for
both `dart run artisan` from the project root and `dart run :artisan` from a
subdirectory.
