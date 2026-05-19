# PluginInstaller Fluent DSL

The `PluginInstaller` class is the procedural escape hatch for plugin install logic that the
declarative `install.yaml` manifest cannot express.

## Table of Contents

- [When to Use](#when-to-use)
- [Two Phases: IMMEDIATE vs DEFERRED](#two-phases-immediate-vs-deferred)
- [DSL Method Reference](#dsl-method-reference)
  - [Prompts](#prompts)
  - [Pubspec Operations](#pubspec-operations)
  - [File Operations](#file-operations)
  - [Injection Operations](#injection-operations)
  - [Android Operations](#android-operations)
  - [iOS and macOS Operations](#ios-and-macos-operations)
  - [Web Operations](#web-operations)
  - [Environment Operations](#environment-operations)
  - [Shell Operations](#shell-operations)
  - [Lifecycle Hooks](#lifecycle-hooks)
- [Atomic Commit Semantics](#atomic-commit-semantics)
- [Example](#example)
- [Related](#related)

---

## When to Use

Prefer `install.yaml` for straightforward installs. Use the procedural DSL when:

- **Complex conditional logic**: the install plan branches on runtime values (platform detection,
  user input, env vars) that YAML conditions cannot evaluate at parse time.
- **Branching prompts**: the set of operations depends on answers collected during the install
  interaction (e.g. "Firebase or Amplitude?" selects different dependency blocks).
- **Programmatic file generation**: installed files are assembled from captured prompt answers
  rather than fixed stub templates.

When none of these apply, `install.yaml` + `ManifestInstaller` is simpler and preferred.

---

## Two Phases: IMMEDIATE vs DEFERRED

Every chain method falls into one of two categories. This split determines whether a method's
effect is visible during the chain or only after `commit()`.

### IMMEDIATE

IMMEDIATE methods run synchronously the moment they appear in the chain. They do not enqueue an
`InstallOperation`; they produce a side effect right now.

| Method | Effect |
|---|---|
| `ask(...)` | Drives `InstallContext.prompt.ask(...)`; stores the answer in `_vars` |
| `confirm(...)` | Drives `InstallContext.prompt.confirm(...)`; stores `'true'` or `'false'` |
| `choice(...)` | Drives `InstallContext.prompt.choice(...)`; stores the selected option |
| `startWith(hook)` | Registers a pre-commit callback (fires before op dispatch, every outcome) |
| `endWith(hook)` | Registers a post-Success callback (skipped on `DryRun`/`Conflict`/`Error`) |

Captured answers are readable via `installer.vars['key']` immediately, allowing the chain to
branch on user input before enqueuing ops.

### DEFERRED

DEFERRED methods append an `InstallOperation` to the internal queue. Nothing touches the
filesystem until `commit()`. Ops execute in enqueue order.

All `add*`, `inject*`, `write*`, `delete*`, `copy*`, `publish*`, `merge*`, `wrap*`, and
`runShell` methods are DEFERRED.

**Hybrid:** `askToRunShell` drives its prompt IMMEDIATELY but enqueues `RunShell` only when the
user confirms, so the shell command still executes deferredly during commit.

---

## DSL Method Reference

All methods return `this` (chainable) unless noted otherwise.

### Prompts

| Method | Description |
|---|---|
| `ask(varName:, question:, [defaultValue:, validator:])` | Free-text prompt; stores answer in `vars[varName]` |
| `confirm(varName:, question:, [defaultValue:])` | Yes/no prompt; stores `'true'` or `'false'` in `vars[varName]` |
| `choice(varName:, question:, options:, [defaultValue:])` | Pick-one-of prompt; stores selected option string in `vars[varName]` |

### Pubspec Operations

| Method | Operation | Description |
|---|---|---|
| `addDependency(name, version)` | `AddDependency` | Adds a runtime dependency to `pubspec.yaml` |
| `addDevDependency(name, version)` | `AddDependency(isDev: true)` | Adds a dev dependency to `pubspec.yaml` |
| `addPathDependency(name, path)` | `AddPathDependency` | Adds a relative-path dependency to `pubspec.yaml` |
| `removeDependency(name)` | `RemoveDependency` | Removes a dependency from `pubspec.yaml` (idempotent) |
| `addPubspecAsset(assetPath)` | `AddPubspecAsset` | Appends an asset path to `flutter.assets` in `pubspec.yaml` (idempotent) |

### File Operations

| Method | Operation | Description |
|---|---|---|
| `publishConfig(stubName:, targetPath:, [replacements:])` | `PublishFile` | Loads a stub, applies token replacements, writes to `targetPath` |
| `writeFile(targetPath:, content:)` | `WriteFile` | Writes raw programmatic content to `targetPath` |
| `deleteFile(targetPath)` | `DeleteFile` | Deletes `targetPath` if it exists (idempotent) |
| `copyFile(sourcePath:, targetPath:)` | `CopyFile` | Copies `sourcePath` to `targetPath` |
| `mergeJson(targetPath:, sourceData:, [additive:])` | `MergeJson` | Deep-merges `sourceData` into the JSON file at `targetPath` |

`mergeJson` defaults to additive mode (existing keys are preserved). Pass `additive: false` to
allow source values to overwrite conflicting target keys.

### Injection Operations

| Method | Operation | Description |
|---|---|---|
| `injectImport(targetFile:, importStatement:)` | `InjectImport` | Appends an import line to any Dart file (idempotent) |
| `injectBefore(targetFile:, pattern:, code:)` | `InjectBeforePattern` | Inserts code before the first match of `pattern` in `targetFile` |
| `injectAfter(targetFile:, pattern:, code:)` | `InjectAfterPattern` | Inserts code after the first match of `pattern` in `targetFile` |
| `injectMainDartImport(importStatement)` | `InjectMainDartImport` | Appends an import to `lib/main.dart` specifically (grouped in dry-run output) |
| `injectBeforeMagicInit(code)` | `InjectIntoMainDart(beforeInit)` | Inserts code before `Magic.init(...)` in `lib/main.dart` |
| `injectAfterMagicInit(code)` | `InjectIntoMainDart(afterInit)` | Inserts code after `Magic.init(...)` in `lib/main.dart` |
| `wrapRunApp(wrapperName)` | `InjectIntoMainDart(wrapRunApp)` | Wraps the `runApp(...)` argument with the named widget constructor |
| `injectProvider(providerClassName, [package:])` | composite | Adds import + appends `(app) => X(app),` to `lib/config/app.dart` providers list |
| `injectConfigFactory(factoryName, [package:])` | composite | Adds import + appends `() => XConfig,` to `lib/main.dart` configFactories list |
| `injectRoute(registerFunctionName)` | `InjectRouteRegistration` | Calls `registerFunctionName()` in `RouteServiceProvider.boot()` |

`injectProvider` and `injectConfigFactory` each enqueue two operations (one `InjectImport` + one
`InjectAfterPattern`) using a lookahead-anchored regex that targets the last entry before `]`.

### Android Operations

| Method | Operation | Description |
|---|---|---|
| `injectAndroidPermission(permission)` | `InjectAndroidPermission` | Adds `<uses-permission>` to `AndroidManifest.xml`; silently skipped on non-Android consumers |
| `injectAndroidMetaData(name:, value:)` | `InjectAndroidMetaData` | Adds `<meta-data>` inside `<application>` in `AndroidManifest.xml` |
| `injectGradlePlugin(pluginId:, [version:])` | `InjectGradlePlugin` | Adds a plugin entry to the `plugins { }` block in `build.gradle.kts` |
| `injectGradleDependency(scope:, notation:)` | `InjectGradleDependency` | Adds a dependency under `scope` in `android/app/build.gradle.kts` |

### iOS and macOS Operations

| Method | Operation | Description |
|---|---|---|
| `injectInfoPlistKey(key:, value:, [platform:])` | `InjectInfoPlistKey` | Sets a key in `ios/Runner/Info.plist` or `macos/Runner/Info.plist`; value may be `String`, `bool`, or `List<String>` |
| `injectEntitlement(platform:, key:, value:)` | `InjectEntitlement` | Sets a key in `Runner.entitlements` for `'ios'` or `'macos'` |
| `injectPodfileLine([platform:], line:)` | `InjectPodfileLine` | Appends a CocoaPods pod declaration to the `target 'Runner'` Podfile block |

Platform-scoped ops are silently skipped when the target platform directory is absent.

### Web Operations

| Method | Operation | Description |
|---|---|---|
| `injectIntoWebHead(content)` | `InjectIntoWebHead` | Inserts raw HTML before `</head>` in `web/index.html`; skipped on non-web consumers |
| `addWebMetaTag(attributes)` | `AddWebMetaTag` | Adds a `<meta>` element with the given attribute map to `web/index.html` |

### Environment Operations

| Method | Operation | Description |
|---|---|---|
| `injectEnvVar(key:, value:, [comment:])` | `InjectEnvVar` | Writes `KEY=value` to `.env`; creates the file when absent; an optional `comment` is written as `# <comment>` above the key line |

### Shell Operations

| Method | Phase | Description |
|---|---|---|
| `runShell(command:, [args:, workingDir:])` | DEFERRED | Enqueues a `RunShell` op that executes after all file mutations have landed |
| `askToRunShell(prompt:, command:, [args:])` | HYBRID | Prompts immediately; enqueues `RunShell` only when the user confirms |

Shell ops execute after all file mutations have landed. Non-zero exit surfaces as `Error`; the
install record from the preceding phase stays on disk so `plugin:uninstall` can reverse file
mutations independently.

### Lifecycle Hooks

| Method | Phase | Description |
|---|---|---|
| `startWith(hook)` | IMMEDIATE (registration); fires pre-commit | `void Function(InstallContext)` invoked before op dispatch, on every outcome |
| `endWith(hook)` | IMMEDIATE (registration); fires post-Success only | Invoked after `Success`; never fires on `DryRun`, `Conflict`, or `Error` |

---

## Atomic Commit Semantics

`commit()` delegates to `InstallTransaction.commit()` (see
`lib/src/installer/install_transaction.dart:132-234`), which executes in seven phases:

1. **Dry-run short-circuit** (line 144): `dryRun: true` renders staged ops and returns `DryRun`
   without touching disk.
2. **Conflict pre-flight** (line 152): detects user-modified target files. `force: true` bypasses.
3. **In-memory staging** (line 162): ops are reduced into `Map<String, String?>` where `null`
   marks a delete. No disk writes yet.
4. **Atomic `.tmp` writes** (line 173): each non-null entry is written to `<absPath>.tmp`. If any
   write throws, all successful temps are deleted and the method returns `Error(rolledBack: true)`.
5. **Rename into place** (line 193): `.tmp` files are renamed over their targets; deletes are
   applied. POSIX `rename(2)` is atomic, so readers never see partial state. Failures past this
   point surface as `Error(rolledBack: false)`.
6. **Install record** (line 213): `.artisan/installed/<plugin>.json` is written BEFORE shell ops
   so the install is always reversible even when a shell step fails later.
7. **Shell ops** (line 228): `RunShell` ops execute last. A non-zero exit returns `Error`; the
   record from phase 6 stays intact.

### One-shot guard

`PluginInstaller._committed` flips to `true` at the start of `commit()`. A second call throws
`StateError` regardless of the first call's outcome. Construct a fresh `PluginInstaller` per
install pass.

### V1 reversibility

`plugin:uninstall` reverses `WriteFile`, `DeleteFile`, and `CopyFile` (hash-verified). Injection
ops and helper-backed ops (pubspec, native, web, env) log `[skipped]` in V1. V1.1 will introduce
anchor-bracket markers for reversible injections.

---

## Example

Pattern from `assets/stubs/make_plugin/magic/install_command.dart.stub`, with a conditional
backend branch illustrating IMMEDIATE prompt + DEFERRED ops:

```dart
import 'package:fluttersdk_artisan/artisan.dart';

class AnalyticsInstallCommand extends ArtisanInstallCommand {
  @override
  String get signature => 'analytics:install $baseFlags';

  @override
  String get description => 'Install the Analytics plugin into the host project.';

  @override
  String pluginName(ArtisanContext ctx) => 'analytics';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final installer = PluginInstaller(buildContext(ctx), pluginName: pluginName(ctx));

    // 1. IMMEDIATE prompt: answer is readable in vars before any op is enqueued.
    installer.choice(
      varName: 'backend',
      question: 'Which analytics backend?',
      options: ['firebase', 'amplitude'],
      defaultValue: 'firebase',
    );

    // 2. Common DEFERRED ops.
    installer
        .publishConfig(
          stubName: 'install/analytics_config.dart',
          targetPath: '${buildContext(ctx).projectRoot}/lib/config/analytics.dart',
          replacements: {'BACKEND': installer.vars['backend']!},
        )
        .injectProvider('AnalyticsServiceProvider')
        .injectEnvVar(key: 'ANALYTICS_KEY', value: '', comment: 'Analytics write key.');

    // 3. Backend-specific ops (DEFERRED, conditional on captured answer).
    if (installer.vars['backend'] == 'firebase') {
      installer
          .addDependency('firebase_core', '^3.0.0')
          .addDependency('firebase_analytics', '^11.0.0')
          .injectAndroidPermission('android.permission.INTERNET')
          .mergeJson(targetPath: 'assets/lang/en.json',
              sourceData: {'analytics': {'title': 'Analytics'}});
    } else {
      installer.addDependency('amplitude_flutter', '^4.0.0');
    }

    // 4. Hybrid: prompt fires now; RunShell enqueued only when user confirms.
    installer.askToRunShell(prompt: 'Run "flutter pub get" now?',
        command: 'flutter', args: ['pub', 'get']);

    final result = await installer.commit(dryRun: isDryRun(ctx), force: isForce(ctx));
    return switch (result) { Success() => 0, DryRun() => 0, Conflict() => 1, Error() => 2 };
  }
}
```

## Related

- [install-yaml.md](install-yaml.md): declarative manifest schema; preferred for straightforward installs.
- [authoring.md](authoring.md): end-to-end plugin authoring guide (scaffold, provider registration, publish checklist).
