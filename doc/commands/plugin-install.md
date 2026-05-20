# plugin:install

Register a third-party artisan plugin into the consumer project. After adding a
package to `pubspec.yaml` and running `flutter pub get`, `plugin:install` wires
the plugin's `ArtisanServiceProvider` without requiring manual edits to
`bin/artisan.dart` or `lib/app/_plugins.g.dart`.

---

<a name="basic-usage"></a>
## Basic Usage

```bash
dart run fluttersdk_artisan plugin:install <name>
```

`<name>` is the plugin's pubspec package name (e.g. `magic_logger`). The
package must be listed in `pubspec.yaml` and resolved via `flutter pub get`
before this command runs.

Pre-flight checks (`lib/src/commands/plugin_install_command.dart:197-241`):
`bin/artisan.dart` must exist, the package must appear in `pubspec.yaml`, and
`.dart_tool/package_config.json` must contain the package name. Any failure
exits with code `1` before any write is attempted.

---

<a name="synopsis"></a>
## Synopsis

Full signature as declared in
`lib/src/commands/plugin_install_command.dart:67`:

```
plugin:install
  {name                  : Plugin pubspec package name (e.g. magic_logger)}
  {--provider=           : Override the auto-derived provider class name}
  {--bootstrap-command=  : Plugin install sub-command to chain after registration}
  {--use-yaml-only       : Fail if install.yaml not found instead of falling back to legacy injection}
  {--force               : Bypass conflict detection (inherited from ArtisanInstallCommand)}
  {--dry-run             : Print staged ops without writing (inherited)}
  {--non-interactive     : Skip prompts, use defaults (inherited)}
  {--no-bootstrap        : Skip post-install bootstrap hint message (inherited)}
```

The four inherited flags come from `ArtisanInstallCommand.baseFlags` and are
available on every install command, not only `plugin:install`.

| Flag | Effect |
|---|---|
| `--provider=ClassName` | Overrides `<PascalCaseName>ArtisanProvider` convention (Mode 3 only). |
| `--bootstrap-command=cmd` | Overrides the post-registration bootstrap hint (e.g. `logger:install`). |
| `--use-yaml-only` | Error out when no `install.yaml` found; no Mode 2 or Mode 3 fallback. |
| `--force` | Bypass conflict detection; overwrite user-modified files. |
| `--dry-run` | Print every staged op without touching disk. |
| `--non-interactive` | Skip interactive prompts; use defaults. Required in non-TTY environments. |
| `--no-bootstrap` | Suppress the post-install bootstrap hint message. |

---

<a name="three-routing-modes"></a>
## Three Routing Modes

The core of `handle` dispatches through three distinct code paths
(`lib/src/commands/plugin_install_command.dart:130-181`). The selection logic
runs in strict priority order: Mode 1 wins when an `install.yaml` manifest is
present; Mode 2 wins when the canonical scaffold barrel exists; Mode 3 is the
final fallback.

### Mode 1: install.yaml Manifest Flow

**Condition**: `resolveInstallYaml(name)` returns a non-null path. The resolver
checks `<plugin_root>/install.yaml` first, then `<plugin_root>/assets/install.yaml`
(`lib/src/commands/plugin_install_command.dart:110-127`).

`ManifestParser.parseFile` parses the YAML into an `InstallManifest`.
`ManifestInstaller` stages `InstallOperation` objects on an `InstallTransaction`.
`InstallTransaction.commit` writes every file to a `.tmp` path first; on full
success, all `.tmp` files are renamed atomically. Any `.tmp` write failure deletes
all staged temps and returns `Error(rolledBack: true)`. On `Success`, the plugin
entry is written to `.artisan/plugins.json` and `PluginsRefreshCommand` regenerates
`lib/app/_plugins.g.dart` in-process.

Preferred authoring path: declarative, conflict-checked, dry-run-capable, and
partially reversible via `plugin:uninstall` (V1 limitations; see Reversibility).

### Mode 2: Canonical Scaffold Fast Path

**Condition**: No `install.yaml` found AND `lib/app/_plugins.g.dart` exists at
the project root (`lib/src/commands/plugin_install_command.dart:172-178`).

`_registerArtisanProvider` runs directly: writes a `PluginEntry` to
`.artisan/plugins.json` and regenerates `_plugins.g.dart`. No `bin/artisan.dart`
edit occurs. Covers plugins without a manifest whose consumers used
`install`. Naming convention: `my_plugin` maps to
`package:my_plugin/cli.dart` and class `MyPluginArtisanProvider`.

### Mode 3: Legacy bin/artisan.dart Injection

**Condition**: No `install.yaml` found AND `lib/app/_plugins.g.dart` does not
exist (`lib/src/commands/plugin_install_command.dart:180`).

1. `import 'package:<name>/cli.dart';` is appended to `bin/artisan.dart` via
   `ConfigEditor.addImportToFile` (idempotent; skips when already present).
2. `registry.registerProvider(<ProviderClass>());` is inserted after the
   `registry.registerAll(auto.commands, ...)` anchor, or before the
   `ArtisanApplication` construction line when the anchor is absent.
3. Provider class defaults to `<PascalCaseName>ArtisanProvider`; override with
   `--provider=ClassName`.

Retained for backward compatibility with plugins predating the `install.yaml`
schema. Pass `--use-yaml-only` to error out instead of reaching this fallback.

---

<a name="examples"></a>
## Examples

### 1. Manifest-based plugin install (Mode 1)

```bash
flutter pub add magic_logger
dart run fluttersdk_artisan plugin:install magic_logger
```

Output:
```
Success: applied 4 ops; record at .artisan/installed/magic_logger.json
Bootstrap with: artisan logger:install
```

### 2. Canonical scaffold, no install.yaml (Mode 2)

```bash
flutter pub add awesome_plugin
dart run fluttersdk_artisan plugin:install awesome_plugin
```

Output:
```
Registered "awesome_plugin" via canonical scaffold (no install.yaml needed).
```

### 3. Dry-run preview

```bash
dart run fluttersdk_artisan plugin:install magic_logger --dry-run
```

Output:
```
DryRun: previewed 4 ops; no changes written
  WriteFile           lib/config/logger.dart
  InjectImport        lib/main.dart
  InjectAfterPattern  lib/app/providers/app_service_provider.dart
  AddPubspecAsset     assets/logging/
```

---

<a name="idempotency"></a>
## Idempotency

Re-running `plugin:install` for the same plugin is safe in all three modes.
`PluginsRegistryFile.addPlugin` replaces by name so `.artisan/plugins.json`
always contains exactly one entry per plugin. `ConfigEditor.addImportToFile`
and `insertCodeAfterPattern` skip injection when the target content is already
present. Mode 3's `registerProvider` line is also checked before insertion
(unless `--force` is passed).

All `InstallTransaction` file writes use `.tmp` + atomic rename: concurrent
readers never observe partial state. A mid-commit `.tmp` write failure deletes
all staged temps and returns `Error(rolledBack: true)` before any rename occurs.

---

<a name="reversibility"></a>
## Reversibility

`plugin:uninstall <name>` is the complement to `plugin:install`. A Mode 1
manifest commit writes `.artisan/installed/<name>.json` listing every op and
content hash. V1 reversibility is partial: `WriteFile` ops are fully reversed
(tamper-check then delete); `InjectImport`, `InjectBeforePattern`, and
`InjectAfterPattern` ops are logged as `[skipped]` (no anchor-bracketed markers
in V1; operator must reverse by hand). Mode 2 and Mode 3 installs write no
record, so `plugin:uninstall` cannot auto-reverse them. Full bidirectional
reversibility is planned for V1.1.

---

<a name="related"></a>
## Related

- [plugin:uninstall](./plugin-uninstall.md): removes a plugin registered via
  `plugin:install`, using the `.artisan/installed/<name>.json` record.
- [plugins:refresh](./plugins-refresh.md): regenerates `lib/app/_plugins.g.dart`
  from `.artisan/plugins.json` when the codegen barrel drifts out of sync.
- [install.yaml schema](../plugins/install-yaml.md): full reference for the
  declarative manifest format consumed by Mode 1.
