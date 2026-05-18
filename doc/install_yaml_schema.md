# install.yaml schema (v1)

`install.yaml` is the declarative manifest every fluttersdk_artisan plugin author
ships at the root of their package (or under `assets/install.yaml`). The
manifest tells the `plugin:install` command WHAT to install: which pubspec
dependencies to add, which stubs to publish, which Magic providers to register,
which native bits to wire on each platform, which env vars to define, which
post-install commands to run.

Every section maps 1:1 onto a `PluginInstaller` chain method (Wave 3). The
`ManifestParser` (Step 27) reads this file into a typed `InstallManifest` and
the `ManifestInstaller` (Step 28) walks the sections in a fixed order, applying
each via the matching chain method, then commits the transaction.

Schema version: **v1**. The shape is locked. Future revisions land under a new
schema version with a side-by-side parser; nothing in v1 is deprecated in-place.

## Top-level keys

| Key                | Required | Type           | Maps to                                                                |
|--------------------|----------|----------------|------------------------------------------------------------------------|
| `plugin_name`      | yes      | String         | `PluginInstaller(pluginName: ...)`                                     |
| `dependencies`     | no       | Map            | `addDependency` / `addDevDependency` / `addPubspecAsset`               |
| `publish`          | no       | Map            | `publishConfig`                                                        |
| `json_merge`       | no       | Map            | `mergeJson`                                                            |
| `magic`            | no       | Map            | `injectProvider` / `injectConfigFactory` / `injectRoute`               |
| `native`           | no       | Map            | `inject*Android* / inject*Ios* / inject*Macos* / inject*Web*`          |
| `env`              | no       | Map            | `injectEnvVar`                                                         |
| `prompts`          | no       | List           | `ask` / `confirm` / `choice` (IMMEDIATE, before any chain method runs) |
| `placeholders`     | no       | Map            | Render-time substitutions passed to `publishConfig(replacements: ...)` |
| `post_install`     | no       | Map            | `runShell` / `askToRunShell` + a final info message                    |
| `bootstrap_command`| no       | String         | Plugin-defined follow-up command (e.g. `example:bootstrap`)            |

Every section is **independent**. Omitting any section is valid and is a silent
no-op for that section's installer phase.

## `plugin_name` (REQUIRED)

```yaml
plugin_name: example_plugin
```

- MUST match `^[a-z_][a-z0-9_]*$`.
- Threads into `.artisan/installed/<plugin_name>.json` (the install record).
- MUST match the plugin's `pubspec.yaml` `name:` field. Mismatch causes the
  consumer's `plugin:install` lookup to fail.

## `dependencies`

```yaml
dependencies:
  pubspec:
    intl: ^0.20.0
    crypto: ^3.0.0
  dev_pubspec:
    mocktail: ^1.0.0
  pubspec_assets:
    - assets/example/
    - assets/lang/en.json
```

- `pubspec` → `addDependency(name, version)` for each entry.
- `dev_pubspec` → `addDevDependency(name, version)`.
- `pubspec_assets` → `addPubspecAsset(path)` for each entry (appends to
  `flutter.assets`).

## `publish`

```yaml
publish:
  install/example_config.dart.stub: lib/config/example.dart
  install/example_routes.dart.stub: lib/routes/example.dart
```

- Map of `stub_name` → `target_path`.
- `stub_name` is the logical stub name (relative to the plugin's
  `assets/stubs/`). `target_path` is relative to the consumer project root.
- The render uses the resolved `placeholders` map as the `replacements`
  parameter (see `placeholders` below).

## `json_merge`

```yaml
json_merge:
  assets/lang/en.json:
    source: install/lang/en.json
    additive: true
```

- Map of `target_path` (in the consumer project) → `{source, additive}`.
- `source` is the stub key whose content is parsed as JSON.
- `additive` defaults to `true`: existing keys in the target are preserved; only
  missing keys land. Setting `false` overwrites conflicting keys.

## `magic`

```yaml
magic:
  provider: ExampleServiceProvider
  config_factory: exampleConfig
  routes: registerExampleRoutes
```

- `provider` → `injectProvider(ExampleServiceProvider)`. Adds an import to
  `lib/config/app.dart` and appends `(app) => ExampleServiceProvider(app),` to
  the `providers: [...]` list. The provider name MUST match
  `^[A-Z][A-Za-z0-9]*$` (PascalCase).
- `config_factory` → `injectConfigFactory(exampleConfig)`. Adds an import to
  `lib/main.dart` and appends `() => exampleConfig,` to the
  `configFactories: [...]` list.
- `routes` → `injectRoute(registerExampleRoutes)`. Calls
  `registerExampleRoutes();` in
  `lib/app/providers/route_service_provider.dart#boot()`.

All three are optional; any combination may be omitted.

## `native`

```yaml
native:
  android:
    permissions:
      - android.permission.INTERNET
    meta_data:
      io.flutter.embedded_views_preview: "true"
    gradle:
      plugins:
        - id: com.example.gradle.plugin
          version: "1.0.0"
      dependencies:
        - scope: implementation
          notation: "com.example:lib:1.0.0"
  ios:
    info_plist:
      NSExampleUsageDescription: "Reason shown in iOS permission dialog"
      UIBackgroundModes: ["fetch"]
    entitlements:
      com.apple.security.keychain: true
    podfile:
      platform_version: "13.0"
      pods:
        - "ExamplePod"
  macos:
    # same shape as ios
  web:
    head_scripts:
      - '<script src="example.js"></script>'
    meta_tags:
      - {name: "description", content: "Example plugin metadata"}
```

- `android.permissions` → `injectAndroidPermission(...)` per entry.
- `android.meta_data` → `injectAndroidMetaData(name: k, value: v)`.
- `android.gradle.plugins` → `injectGradlePlugin(pluginId, version)`.
- `android.gradle.dependencies` → `injectGradleDependency(scope, notation)`.
- `ios.info_plist` / `macos.info_plist` → `injectInfoPlistKey(key, value,
  platform: 'ios'|'macos')`. Value may be String, bool, or List of Strings.
- `ios.entitlements` / `macos.entitlements` → `injectEntitlement(...)`.
- `ios.podfile.platform_version` → reserved (informational; no chain method
  in v1).
- `ios.podfile.pods` → `injectPodfileLine(platform: 'ios', line: "pod 'X'")`.
- `web.head_scripts` → `injectIntoWebHead(content)`.
- `web.meta_tags` → `addWebMetaTag(attributes)`.

Each platform sub-section is independent; omit any platform that does not
apply. The dispatcher (Wave 3) silently skips native ops when the consumer
project lacks the matching platform directory.

## `env`

```yaml
env:
  EXAMPLE_KEY:
    default: example_value
    comment: "Example plugin runtime config"
```

- Map of env var name → `{default, comment}`.
- Translates to `injectEnvVar(key: K, value: defaultValue, comment: comment)`.
- The `comment` is preserved for forward-compatibility; the v1 dispatcher
  ignores it (the `.env` writer does not yet emit comment lines).

## `prompts`

```yaml
prompts:
  - {key: configPath, type: string, default: "~/.example.conf", question: "Config file path?"}
  - {key: mode, type: choice, options: [dev, staging, prod], default: dev, question: "Deployment mode?"}
  - {key: enableFeature, type: bool, default: false, question: "Enable optional feature?"}
```

- Array of prompt specs. Each entry MUST declare `key`, `type`, `question`.
- `type` is one of `string` / `choice` / `bool`. `choice` requires `options`.
- `default` is shown in brackets at the prompt; ENTER picks it.
- Prompts run IMMEDIATELY at the start of `install()`, before any chain
  method enqueues an op. The captured answers feed `placeholders`.
- Prompt keys MUST be unique across the array.
- When the install runs `--non-interactive`, every prompt returns its default.

## `placeholders`

```yaml
placeholders:
  configFilePath: "{{ prompts.configPath }}"
  runtimeMode: "{{ prompts.mode }}"
```

- Map of placeholder key (used in stub bodies) → value template.
- Values may reference prompt answers via `{{ prompts.KEY }}` (with optional
  surrounding whitespace).
- Every `{{ prompts.X }}` reference MUST resolve to an existing prompt key,
  otherwise the parser throws `ManifestValidationException`.
- The resolved placeholder map is passed verbatim to every `publishConfig`
  call's `replacements:` parameter.

## `post_install`

```yaml
post_install:
  run:
    - cmd: dart
      args: [format, lib/config/example.dart]
  ask_to_run:
    - prompt: "Run pub get now?"
      cmd: flutter
      args: [pub, get]
  message: |
    example_plugin installed.
    Next steps: see the plugin's own README.
```

- `run` → `runShell(command: cmd, args: args)` for each entry. Always runs at
  commit phase.
- `ask_to_run` → `askToRunShell(prompt, command: cmd, args: args)`. Prompts
  IMMEDIATELY at install time; on yes the shell call is deferred to commit.
- `message` is emitted via `output.info(message)` after a Success result.

## `bootstrap_command`

```yaml
bootstrap_command: example:install
```

- Optional plugin-specific command name. After a successful install,
  `plugin:install` (Step 29) chains into this command unless the caller passed
  `--no-bootstrap`.

## Execution order

`ManifestInstaller.install()` runs the sections in this fixed order:

1. `prompts` (IMMEDIATE; before any chain method)
2. `placeholders` (pure resolution, no I/O)
3. `dependencies` (pubspec / dev_pubspec / pubspec_assets)
4. `publish`
5. `json_merge`
6. `magic.provider` → `magic.config_factory` → `magic.routes`
7. `native.android.*` → `native.ios.*` → `native.macos.*` → `native.web.*`
8. `env`
9. `post_install.run` + `post_install.ask_to_run`

Then a final `commit(dryRun: ..., force: ...)` runs the
`InstallTransaction` (atomic `.tmp` swap + record write).

The order matches Spatie's `InstallCommand` `processX` ordering: native
mutations land AFTER pubspec mutations so Gradle / Pod files reflect the new
dependency state.

## Uninstall semantics

Uninstall is **automatic**. There is no `uninstall` block in `install.yaml`.
`ManifestInstaller.uninstall()` reads
`.artisan/installed/<plugin_name>.json` (the install record persisted at
commit time) and derives the reverse op for each recorded operation. The
mapping:

| Forward op                 | Reverse op                                  |
|----------------------------|---------------------------------------------|
| `AddDependency`            | `RemoveDependency`                          |
| `AddPathDependency`        | `RemoveDependency`                          |
| `AddPubspecAsset`          | warning + skip (v1 limitation)              |
| `PublishFile`              | `DeleteFile(targetPath)`                    |
| `WriteFile`                | `DeleteFile(targetPath)`                    |
| `CopyFile`                 | `DeleteFile(targetPath)`                    |
| `DeleteFile`               | warning + skip (no reverse possible)        |
| `MergeJson`                | warning + skip (v1 limitation)              |
| `InjectImport`             | warning + skip (v1 limitation)              |
| `InjectBeforePattern`      | warning + skip (v1 limitation)              |
| `InjectAfterPattern`       | warning + skip (v1 limitation)              |
| `InjectMainDartImport`     | warning + skip (v1 limitation)              |
| `InjectIntoMainDart`       | warning + skip (v1 limitation)              |
| `InjectRouteRegistration`  | warning + skip (v1 limitation)              |
| `InjectAndroidPermission`  | warning + skip (v1 limitation)              |
| `InjectAndroidMetaData`    | warning + skip (v1 limitation)              |
| `InjectInfoPlistKey`       | warning + skip (v1 limitation)              |
| `InjectEntitlement`        | warning + skip (v1 limitation)              |
| `InjectPodfileLine`        | warning + skip (v1 limitation)              |
| `InjectGradlePlugin`       | warning + skip (v1 limitation)              |
| `InjectGradleDependency`   | warning + skip (v1 limitation)              |
| `InjectIntoWebHead`        | warning + skip (v1 limitation)              |
| `AddWebMetaTag`            | warning + skip (v1 limitation)              |
| `InjectEnvVar`             | warning + skip (v1 limitation)              |
| `RunShell`                 | warning + skip (no reverse possible)        |

The "warning + skip" entries are a v1 trade-off: the install record currently
persists only the type tag for these ops (the `PluginInstaller`
`_serializeOp` carries full payload only for `WriteFile` / `DeleteFile` /
`CopyFile`). v2 widens the record payload so every reverse can be derived
mechanically.

For now: uninstall removes every published file (the dominant case) and
prints a warning summary for every skipped op so the operator knows what to
clean up by hand. The `.artisan/installed/<plugin_name>.json` record is
deleted on a Success result.

When the record file is absent, `uninstall()` returns an `Error` result so
the operator does not silently believe the plugin was removed.

## Validation

`ManifestParser.validate()` enforces:

- `plugin_name` is present, non-empty, and matches `^[a-z_][a-z0-9_]*$`.
- Every `prompts[*].key` is unique.
- Every `placeholders[*]` value's `{{ prompts.X }}` references resolve to a
  prompt key defined in the same manifest.
- `magic.provider`, when present, matches `^[A-Z][A-Za-z0-9]*$`.

Any failure throws `ManifestValidationException` (subclass of
`InstallException`) with a human-readable message.

## Sample files

Two reference manifests live under `doc/samples/`:

- `install.minimal.yaml`: the smallest valid manifest (plugin_name + one
  publish + one magic.provider).
- `install.full.yaml`: every section populated with generic placeholder
  identifiers (e.g. `example_plugin`, `ExampleServiceProvider`). Use this as
  the copy-and-trim starting point when authoring a new plugin manifest.

Both samples are parsed by `manifest_parser_test.dart` to verify schema
completeness.
