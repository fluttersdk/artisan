# make:plugin

Scaffold a new `fluttersdk_artisan` plugin skeleton under `packages/<name>/` (or a
custom target directory). Produces a fully wired, immediately testable plugin package
in a single command.

---

## Table of contents

- [Basic Usage](#basic-usage)
- [Synopsis](#synopsis)
- [Two Modes](#two-modes)
- [8-Phase Pipeline](#8-phase-pipeline)
- [Output Layout](#output-layout)
- [Examples](#examples)
- [Workspace Enrollment](#workspace-enrollment)
- [Related](#related)

---

## Basic Usage

```bash
dart run fluttersdk_artisan make:plugin <name>
```

`<name>` must be a valid Dart package name: snake_case, starts with a lowercase
letter, contains only `[a-z0-9_]`. Writes to `<projectRoot>/packages/<name>/` by
default and enrolls the new plugin into the parent Flutter app's pub workspace when
one is detected.

---

## Synopsis

```
make:plugin {name} {--path=} {--target=} {--magic} {--bootstrap-command=}
```

| Argument / Option | Description |
|---|---|
| `name` | Plugin package name in snake_case (required). |
| `--path=<dir>` | Target directory. Takes precedence over `--target` when both are set. |
| `--target=<dir>` | Target directory (alias for `--path`). |
| `--magic` | Scaffold a magic-aware plugin: adds `install.yaml`, Magic ServiceProvider, install/uninstall commands, and the `magic` dep to `pubspec.yaml`. Entirely optional. |
| `--bootstrap-command=<cmd>` | Override the default bootstrap command name (default: `<commandPrefix>:install`). |

---

## Two Modes

### Generic mode (default)

Running without `--magic` produces a Magic-free plugin. Stubs sourced from
`assets/stubs/make_plugin/generic/`:

`pubspec.yaml`, `bin/<name>.dart`, `lib/cli.dart`, `lib/<name>.dart`,
`lib/src/<name>_artisan_provider.dart`, `test/<name>_artisan_provider_test.dart`,
`README.md`.

The generic plugin exposes a single `ArtisanServiceProvider` subclass with an empty
`mcpTools()` override. No dependency on `magic` or any other framework is added.

### Magic mode (`--magic`)

When `--magic` is passed (or auto-detected because `magic:install` is in the running
registry), four generic stubs are replaced by variants from
`assets/stubs/make_plugin/magic/` (`pubspec.yaml`, `cli.dart`, `runtime.dart`,
`provider.dart`), and six additional files are written from the same directory:

| Stub | Written to |
|---|---|
| `install_command.dart` | `lib/src/commands/install_command.dart` |
| `uninstall_command.dart` | `lib/src/commands/uninstall_command.dart` |
| `install.yaml` | `install.yaml` |
| `config_stub.dart` | `assets/stubs/install/<name>_config.dart.stub` |
| `install_command_test.dart` | `test/cli/install_command_test.dart` |
| `service_provider.dart` | `lib/src/<name>_service_provider.dart` |

Magic mode wires a `ManifestInstaller`-compatible `install.yaml` manifest, a
Magic-aware `ServiceProvider`, and install/uninstall commands with test
scaffolds. The parent app's `plugin:install` can then resolve the manifest
automatically.

---

## 8-Phase Pipeline

1. **Validate name.** Reject empty or non-snake_case names with an actionable error.
   Mirrors Dart's pubspec `name:` rule.

2. **Resolve target directory.** Flag precedence: `--path` wins over `--target`; both
   override the default `<projectRoot>/packages/<name>/`.

3. **Spawn `flutter create --template=package`.** Lays down the baseline package:
   `pubspec.yaml`, `LICENSE`, `CHANGELOG.md`, `.gitignore`, `.metadata`,
   `analysis_options.yaml`, `lib/<name>.dart`, `test/<name>_test.dart`, `README.md`.

4. **Render generic stubs.** Seven files from `assets/stubs/make_plugin/generic/`
   overwrite `flutter create`'s defaults. Placeholders (`{{ name }}`,
   `{{ pascalName }}`, `{{ artisanPath }}`, `{{ commandPrefix }}`) are substituted at
   render time. In magic mode, four stubs are sourced from `assets/stubs/make_plugin/magic/`
   instead.

5. **Render magic add-ons (magic mode only).** Six additional files from
   `assets/stubs/make_plugin/magic/` are written. The `{{ magicPath }}` placeholder
   (relative path to the `magic` package root) is only available in this phase.

6. **Detect parent Flutter app.** `WorkspaceEnroller.detectParentFlutterApp` walks up
   from the target directory looking for a parent Flutter app `pubspec.yaml`.

7. **Enroll in workspace (when parent detected).** Adds `resolution: workspace` to the
   plugin's `pubspec.yaml` and appends the plugin's relative path to the parent app's
   `workspace:` list.

8. **Print success banner.** Reports the scaffolded path, `cd <target> && dart pub get
   && dart test`, and whether the parent app's `pubspec.yaml` was modified.

---

## Output Layout

```
packages/<name>/
├── bin/
│   └── <name>.dart                        # CLI entry point
├── lib/
│   ├── <name>.dart                        # Runtime barrel
│   ├── cli.dart                           # CLI barrel
│   └── src/
│       ├── <name>_artisan_provider.dart   # ArtisanServiceProvider subclass
│       ├── <name>_service_provider.dart   # [magic] Magic ServiceProvider
│       └── commands/
│           ├── install_command.dart       # [magic]
│           └── uninstall_command.dart     # [magic]
├── assets/stubs/install/
│   └── <name>_config.dart.stub            # [magic] config template
├── test/
│   ├── <name>_artisan_provider_test.dart
│   └── cli/
│       └── install_command_test.dart      # [magic]
├── install.yaml                           # [magic] ManifestInstaller manifest
├── pubspec.yaml
└── README.md
```

Items without `[magic]` are present in both modes.

---

## Examples

**Generic plugin at the default location:**

```bash
dart run fluttersdk_artisan make:plugin fluttersdk_logger
```

Writes to `packages/fluttersdk_logger/`. Strips the `fluttersdk_` prefix:
`commandPrefix=logger`, bootstrap command defaults to `logger:install`.

**Magic-aware plugin:**

```bash
dart run fluttersdk_artisan make:plugin fluttersdk_logger --magic
```

Same layout plus `install.yaml`, `service_provider.dart`, install/uninstall commands,
a config stub, and the `magic` path dependency in `pubspec.yaml`.

**Plugin at a custom path:**

```bash
dart run fluttersdk_artisan make:plugin my_analytics --path=/workspace/plugins/my_analytics
```

Writes to the absolute path. Workspace enrollment still runs: if a parent Flutter app
is found above that path, the plugin is enrolled.

---

## Workspace Enrollment

When the target directory lives inside or adjacent to a Flutter application,
`WorkspaceEnroller` walks the directory tree upward. On finding a parent
`pubspec.yaml` that declares a Flutter dependency:

1. The plugin's `pubspec.yaml` gains `resolution: workspace`.
2. The parent app's `pubspec.yaml` gains a `workspace:` entry pointing to the
   plugin's relative path.

After enrollment, a single `flutter pub get` in the parent app resolves all workspace
members together. When no parent Flutter app is detected, the plugin is left as a
standalone package and the success banner reports the outcome.

---

## Related

- [make:command](index.md): scaffold a single `ArtisanCommand` subclass inside an
  existing consumer project or plugin.
- [plugins:refresh](index.md): regenerate `lib/app/_plugins.g.dart` from
  `.artisan/plugins.json` after manually editing the registry.
- [plugin:install](plugin-install): register a third-party plugin (resolves
  `install.yaml` manifests produced by `make:plugin --magic`).
