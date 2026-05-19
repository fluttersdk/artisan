# consumer:scaffold

Write the canonical native Flutter consumer wrapper into the current project
so `plugin:install`, `plugins:refresh`, `make:command`, and the dev-loop
commands all integrate without manual `bin/artisan.dart` edits.

## Table of contents

- [Basic Usage](#basic-usage)
- [Synopsis](#synopsis)
- [What It Writes](#what-it-writes)
- [Pubspec Injection](#pubspec-injection)
- [Idempotency](#idempotency)
- [Examples](#examples)
- [Related](#related)

## Basic Usage

```bash
dart run fluttersdk_artisan consumer:scaffold
```

Run this once from the root of a native Flutter project that consumes
`fluttersdk_artisan` directly (without a Magic dependency). The command
reads `pubspec.yaml` for the package name, scaffolds three source files,
and injects a `fluttersdk_artisan` dependency into `pubspec.yaml`.

## Synopsis

```
consumer:scaffold {--force}
```

| Token | Kind | Description |
|-------|------|-------------|
| `--force` | flag | Overwrite files even when they already exist. Without this flag the command prints `Skipped (exists): <path>` for each pre-existing file. |

## What It Writes

Three files are created (or overwritten when `--force` is active):

**`bin/artisan.dart`** : the package-aware entry-point wrapper. Imports
`lib/app/commands/_index.g.dart` (consumer commands) and
`lib/app/_plugins.g.dart` (plugin providers), passes both to `runArtisan`
via `baseProviders`. The package name from `pubspec.yaml` is substituted
into the barrel imports at scaffold time. After this file exists, use the
short alias for all artisan invocations: `dart run artisan <command>`.

**`lib/app/_plugins.g.dart`** : the empty plugin-provider barrel. Exports
`autoDiscoveredProviders()` returning an empty list. `plugin:install` and
`plugins:refresh` regenerate this file from `.artisan/plugins.json`.

**`lib/app/commands/_index.g.dart`** : the empty command-index barrel.
Exports a `commands` getter returning an empty `List<ArtisanCommand>`.
`make:command` and `commands:refresh` regenerate it as commands are added.

## Pubspec Injection

After writing the three files, the command ensures `fluttersdk_artisan`
is listed as a direct dependency in `pubspec.yaml`. The generated barrels
import from `package:fluttersdk_artisan/artisan.dart`; without a direct
dep the analyzer flags each barrel with `depend_on_referenced_packages`.

Detection reads `.dart_tool/package_config.json`. Two routing modes:

**monorepo / path-dep** (local checkout): the command locates the
`fluttersdk_artisan` entry in `package_config.json` and inspects `rootUri`.
When it is a relative path (not a `file://` or pub-cache location), artisan
is resolved from a local monorepo checkout. The path is rebased relative to
`pubspec.yaml` and injected as a `path:` dependency:

```yaml
dependencies:
  fluttersdk_artisan:
    path: ../fluttersdk_artisan
```

**pub.dev fallback** (no `package_config.json`, or artisan in pub-cache):
injects a bare constraint so `pub get` resolves against the parent plugin:

```yaml
dependencies:
  fluttersdk_artisan: any
```

Both branches are idempotent: re-running when `fluttersdk_artisan` is
already listed under `dependencies:` is a safe no-op.

## Idempotency

All four steps (three file writes plus the pubspec dep injection) are safe
to repeat:

- Each file write checks `File.existsSync()` before writing. An existing
  file is left untouched unless `--force` is passed.
- The pubspec injection early-returns when `fluttersdk_artisan` is already
  present under `dependencies:`.

On exit the command reports: `Consumer scaffold complete (N written, N skipped).`

## Examples

**Fresh scaffold** (new project, no existing scaffold files):

```bash
dart run fluttersdk_artisan consumer:scaffold
# Created: bin/artisan.dart
# Created: lib/app/_plugins.g.dart
# Created: lib/app/commands/_index.g.dart
# Consumer scaffold complete (3 written, 0 skipped). ...
```

**Force overwrite** (reset scaffold files to canonical state):

```bash
dart run fluttersdk_artisan consumer:scaffold --force
# Created: bin/artisan.dart
# Created: lib/app/_plugins.g.dart
# Created: lib/app/commands/_index.g.dart
# Consumer scaffold complete (3 written, 0 skipped). ...
```

## Related

- [make:command](make-command) : scaffold a new `ArtisanCommand` subclass
  and auto-update `lib/app/commands/_index.g.dart`.
- [plugin:install](plugin-install) : register a third-party plugin and
  regenerate `lib/app/_plugins.g.dart`.
- [Getting started: installation](../getting-started/installation) : first-run
  setup covering when to use `consumer:scaffold` vs `magic:install`.
