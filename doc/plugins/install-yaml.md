# install.yaml Schema Reference

Canonical schema for the declarative `install.yaml` manifest consumed by `plugin:install`'s manifest flow.

- [Overview](#overview)
- [Top-Level Fields](#top-level-fields)
- [plugin_name](#plugin_name)
- [pubspec / dev_pubspec / pubspec_assets (dependencies:)](#dependencies)
- [publish](#publish)
- [json_merge](#json_merge)
- [magic](#magic)
- [native](#native)
  - [native.android](#nativeandroid)
  - [native.ios](#nativeios)
  - [native.macos](#nativemacos)
  - [native.web](#nativeweb)
- [env](#env)
- [prompts](#prompts)
- [placeholders](#placeholders)
- [post_install](#post_install)
- [bootstrap_command](#bootstrap_command)
- [Complete Example](#complete-example)

## Overview

`install.yaml` is the declarative manifest that drives `plugin:install`'s manifest flow. The file is parsed by `ManifestParser` (`lib/src/installer/manifest_parser.dart`) into a typed `InstallManifest` (`lib/src/installer/install_manifest.dart`) and consumed by `ManifestInstaller`, which translates each section into deferred `InstallOperation`s on the `PluginInstaller` transaction. Nothing writes to disk until `commit(dryRun:, force:)` fires.

The schema is intentionally tolerant: every section except `plugin_name` is optional, every section factory returns a sensible empty default when absent, and partial manifests parse cleanly. Schema violations raise `ManifestValidationException`; raw YAML syntax errors raise `FormatException`.

## Top-Level Fields

| Field | Type | Required | Default | Source |
|-------|------|----------|---------|--------|
| `plugin_name` | string | yes | (none) | `manifest_parser.dart:112` |
| `dependencies` | map | no | empty | `manifest_parser.dart:124` |
| `publish` | map | no | empty | `manifest_parser.dart:127` |
| `json_merge` | map | no | empty | `manifest_parser.dart:128` |
| `magic` | map | no | empty | `manifest_parser.dart:129` |
| `native` | map | no | empty | `manifest_parser.dart:132` |
| `env` | map | no | empty | `manifest_parser.dart:135` |
| `prompts` | list | no | empty | `manifest_parser.dart:136` |
| `placeholders` | map | no | empty | `manifest_parser.dart:137` |
| `post_install` | map | no | empty | `manifest_parser.dart:138` |
| `bootstrap_command` | string | no | `null` | `manifest_parser.dart:141` |

## plugin_name

The plugin's pubspec package name. Used to scope `.artisan/installed/<plugin>.json` reversibility records, the `plugins.json` registry entry, and the generated `lib/app/_plugins.g.dart` import line.

**Validation regex** (`manifest_parser.dart:31`):

```
^[a-z_][a-z0-9_]*$
```

The value must start with a lowercase letter or underscore, followed by any number of lowercase letters, digits, or underscores. An empty string raises `ManifestValidationException('plugin_name must not be empty.')`.

```yaml
plugin_name: example_plugin
```

## dependencies

Pubspec mutations. The `dependencies:` map (note the YAML key is plural, but the typed model is `PubspecDeps`) carries three sub-keys, all optional.

| Sub-key | Type | Translates to |
|---------|------|---------------|
| `pubspec` | `Map<String, String>` | `dependencies:` entries in the consumer's `pubspec.yaml` |
| `dev_pubspec` | `Map<String, String>` | `dev_dependencies:` entries |
| `pubspec_assets` | `List<String>` | Paths appended under `flutter.assets:` |

Empty maps and missing keys are interchangeable; both produce an empty `PubspecDeps`.

```yaml
dependencies:
  pubspec:
    intl: ^0.20.0
  dev_pubspec:
    mocktail: ^1.0.0
  pubspec_assets:
    - assets/example/
```

## publish

Stub-name to target-path mapping. Each entry becomes a `publishConfig` operation: the named stub is read from the plugin's `install/` directory, placeholder-substituted, and written to the target path inside the consumer project.

| Key shape | Value shape |
|-----------|-------------|
| Stub name (string) | Target path (string) |

Non-string values raise `FormatException('publish entry "<key>" must map to a String target path; got <type>.')`.

```yaml
publish:
  install/example_config.dart.stub: lib/config/example.dart
```

## json_merge

Map of target JSON file path to merge spec. Each entry triggers a `mergeJson` operation: the source stub is parsed as JSON, then merged into the target file according to `additive`.

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `source` | string | yes | (none) | Stub key whose content is parsed as JSON. Missing or non-string raises `FormatException('json_merge entry missing required "source" string.')`. |
| `additive` | bool | no | `true` | When `true`, existing keys in the target file survive a collision. When `false`, source keys overwrite target keys. |

```yaml
json_merge:
  assets/lang/en.json:
    source: install/lang/en.json
    additive: true
```

## magic

Magic-framework integration block. Every slot is optional; the section defaults to an empty integration when absent.

| Field | Type | Translates to |
|-------|------|---------------|
| `provider` | string (PascalCase) | `injectProvider(provider)` |
| `config_factory` | string | `injectConfigFactory(name)` |
| `routes` | string | `injectRoute(name)` |

**Validation regex** for `provider` (`manifest_parser.dart:34`):

```
^[A-Z][A-Za-z0-9]*$
```

The value, when present, must be a PascalCase identifier (uppercase first letter, alphanumerics afterwards). A non-matching value raises `ManifestValidationException('magic.provider "<value>" does not match PascalCase regex ^[A-Z][A-Za-z0-9]*$.')`.

```yaml
magic:
  provider: ExampleServiceProvider
  config_factory: exampleConfig
  routes: registerExampleRoutes
```

## native

Per-platform native configuration. Each platform sub-section is independently optional.

### native.android

| Field | Type | Translates to |
|-------|------|---------------|
| `permissions` | `List<String>` | `<uses-permission>` entries in `AndroidManifest.xml` |
| `meta_data` | `Map<String, String>` | `<meta-data>` entries in `AndroidManifest.xml` |
| `gradle.plugins` | `List<{id, version?}>` | Gradle plugin block entries |
| `gradle.dependencies` | `List<{scope, notation}>` | Gradle dependency block entries |

Gradle plugin entries without `id` raise `FormatException('Gradle plugin missing required "id".')`. Gradle dependency entries without both `scope` and `notation` raise `FormatException('Gradle dependency entry requires both "scope" and "notation".')`.

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
```

### native.ios

| Field | Type | Notes |
|-------|------|-------|
| `info_plist` | `Map<String, Object>` | Values may be String, bool, num, or List. Runtime-type branching happens in the dispatcher. |
| `entitlements` | `Map<String, Object>` | Same shape as `info_plist`. |
| `podfile.platform_version` | string (optional) | Informational in v1: no chain method consumes it yet. |
| `podfile.pods` | `List<String>` | Pod declarations appended to `target 'Runner'`. |

```yaml
native:
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
```

### native.macos

Shape mirrors `native.ios` exactly. Same field set (`info_plist`, `entitlements`, `podfile.platform_version`, `podfile.pods`), same dispatcher rules. See the [Complete Example](#complete-example) for a macOS block in context.

### native.web

| Field | Type | Translates to |
|-------|------|---------------|
| `head_scripts` | `List<String>` | HTML snippets injected before `</head>` in `web/index.html` |
| `meta_tags` | `List<Map<String, String>>` | `<meta>` attribute maps appended to `web/index.html` |

```yaml
native:
  web:
    head_scripts:
      - '<script src="example.js"></script>'
    meta_tags:
      - {name: "description", content: "Example plugin metadata"}
```

## env

Environment variables to inject into the consumer's `.env`. Map of var name to spec.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `default` | scalar | yes | Default value written into `.env`. Coerced via `toString()`. Missing raises `FormatException('env entry missing required "default".')`. |
| `comment` | string | no | Advisory documentation. The v1 dispatcher does NOT emit the comment into the `.env` file. |

Non-map entries raise `FormatException('env entry "<key>" must be a map with "default" + optional "comment"; got <type>.')`.

```yaml
env:
  EXAMPLE_KEY:
    default: example_value
    comment: "Example plugin runtime config"
```

## prompts

Ordered list of prompts driven immediately at the start of install (before any deferred operation runs). Prompt answers populate the prompt-result map that `placeholders` interpolates.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `key` | string | yes | Unique within the prompts list. Duplicates raise `ManifestValidationException('Duplicate prompt key "<key>" in prompts list.')`. |
| `type` | string | yes | One of `string`, `bool`, `choice`. |
| `question` | string | yes | Human-readable question text. |
| `default` | scalar | no | Stored as a String regardless of `type` for uniform placeholder substitution. |
| `options` | `List<String>` | no | For `choice` prompts: the valid option set. Empty for non-choice types. |

Missing `key`, `type`, or `question` raises `FormatException('Prompt entry requires "key", "type", and "question" strings.')`.

```yaml
prompts:
  - {key: configPath, type: string, default: "~/.example.conf", question: "Config file path?"}
  - {key: mode, type: choice, options: [dev, staging, prod], default: dev, question: "Deployment mode?"}
  - {key: enableFeature, type: bool, default: false, question: "Enable optional feature?"}
```

## placeholders

Map of placeholder key to value template. Values may reference prompt answers via `{{ prompts.KEY }}`. Whitespace around the dotted reference is optional, so `{{prompts.x}}` and `{{ prompts.x }}` are both accepted.

**Reference regex** (`manifest_parser.dart:39`):

```
\{\{\s*prompts\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}
```

Every `{{ prompts.X }}` reference must resolve to a declared prompt key. Unknown references raise `ManifestValidationException('Placeholder "<placeholderKey>" references unknown prompt key "<referenced>".')`.

```yaml
placeholders:
  configFilePath: "{{ prompts.configPath }}"
  runtimeMode: "{{ prompts.mode }}"
```

## post_install

Post-install shell operations plus a final info message. Every sub-field is optional.

| Field | Type | Notes |
|-------|------|-------|
| `run` | `List<{cmd, args?}>` | Shell commands run unconditionally at commit phase. `cmd` is required; missing raises `FormatException('Shell spec missing required "cmd".')`. |
| `ask_to_run` | `List<{prompt, cmd, args?}>` | Shell commands run only after user confirmation. The prompt fires immediately at install time; on yes the shell call is deferred. Missing `prompt` or `cmd` raises `FormatException('ask_to_run entry requires "prompt" and "cmd" strings.')`. |
| `message` | string | Optional info message emitted after a Success result. |

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
```

## bootstrap_command

Optional plugin-specific bootstrap command name run after a Success result. Translates to a single `dart run <consumer>:artisan <name>` invocation deferred to the very end of the manifest flow.

```yaml
bootstrap_command: example:install
```

## Complete Example

The example below is the canonical `_fullYaml` test fixture from `test/installer/manifest_parser_test.dart`. Every section above appears here in context.

```yaml
plugin_name: example_plugin

dependencies:
  pubspec:
    intl: ^0.20.0
    crypto: ^3.0.0
  dev_pubspec:
    mocktail: ^1.0.0
  pubspec_assets:
    - assets/example/
    - assets/lang/en.json

publish:
  install/example_config.dart.stub: lib/config/example.dart
  install/example_routes.dart.stub: lib/routes/example.dart

json_merge:
  assets/lang/en.json:
    source: install/lang/en.json
    additive: true

magic:
  provider: ExampleServiceProvider
  config_factory: exampleConfig
  routes: registerExampleRoutes

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
    info_plist:
      NSExampleUsageDescription: "Reason shown in macOS permission dialog"
    entitlements:
      com.apple.security.network.client: true
    podfile:
      platform_version: "11.0"
      pods:
        - "ExamplePod"
  web:
    head_scripts:
      - '<script src="example.js"></script>'
    meta_tags:
      - {name: "description", content: "Example plugin metadata"}

env:
  EXAMPLE_KEY:
    default: example_value
    comment: "Example plugin runtime config"

prompts:
  - {key: configPath, type: string, default: "~/.example.conf", question: "Config file path?"}
  - {key: mode, type: choice, options: [dev, staging, prod], default: dev, question: "Deployment mode?"}
  - {key: enableFeature, type: bool, default: false, question: "Enable optional feature?"}

placeholders:
  configFilePath: "{{ prompts.configPath }}"
  runtimeMode: "{{ prompts.mode }}"

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

bootstrap_command: example:install
```
