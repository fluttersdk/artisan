# Installation

- [Requirements](#requirements)
- [Installation](#installation-step)
- [Basic Setup](#basic-setup)
- [Verify Installation](#verify-installation)

Getting started with fluttersdk_artisan requires a few steps to wire the CLI binary and codegen scaffolding into your project.

<a name="requirements"></a>
## Requirements

Before adding fluttersdk_artisan to your project, ensure your environment meets these minimum version requirements. We recommend staying on the latest stable Dart SDK for the best experience.

fluttersdk_artisan is a pure Dart package. Flutter is optional: it is only required when you intend to drive a running Flutter app (hot reload, Dusk gestures, Telescope inspection). Projects that only need scaffolding, code generation, or the MCP server can run on any Dart 3.4+ environment.

| Dependency | Minimum Version | Recommended |
|:-----------|:----------------|:------------|
| Dart       | `>= 3.4.0`      | `3.6.0+`    |
| Flutter    | optional        | `3.27.0+`   |

<a name="installation-step"></a>
## Installation

Add `fluttersdk_artisan` to your project using the Dart CLI:

```bash
dart pub add fluttersdk_artisan
```

Alternatively, add it manually to your `pubspec.yaml`:

```yaml
dependencies:
  fluttersdk_artisan: ^0.0.1
```

Then fetch dependencies:

```bash
dart pub get
```

<a name="basic-setup"></a>
## Basic Setup

After installing the package, run the scaffold command to create the canonical consumer wrapper in your project:

```bash
dart run fluttersdk_artisan consumer:scaffold
```

This command writes three files into your project:

| File | Purpose |
|:-----|:--------|
| `bin/artisan.dart` | The runnable entry point. `dart run artisan <cmd>` dispatches here. |
| `lib/app/_plugins.g.dart` | Generated plugin provider list. Updated by `plugin:install` and `plugins:refresh`. |
| `lib/app/commands/_index.g.dart` | Generated command index. Updated by `make:command` and `commands:refresh`. |

The command is idempotent: re-running it skips files that already exist. Pass `--force` to overwrite:

```bash
dart run fluttersdk_artisan consumer:scaffold --force
```

### Dependency injection into pubspec.yaml

`consumer:scaffold` also ensures `fluttersdk_artisan` is listed as a direct dependency in your `pubspec.yaml`. The generated barrel files at `lib/app/_plugins.g.dart` and `lib/app/commands/_index.g.dart` import from `package:fluttersdk_artisan/artisan.dart`, so the analyzer requires a direct dep to pass `depend_on_referenced_packages`.

The injection is automatic and follows two modes:

- **Monorepo / path-dep workflow**: when your project already resolves `fluttersdk_artisan` via a local path (detected from `.dart_tool/package_config.json`), the scaffold injects a `path:` reference pointing to the same checkout. This avoids a pub.dev fetch against a version that may not yet be published.
- **pub.dev workflow**: when no local resolution is found, the scaffold injects the `any` constraint and lets pub resolve the version transitively. Replace `any` with a pinned range (e.g. `^0.0.1`) before committing.

<a name="verify-installation"></a>
## Verify Installation

Run the built-in `list` command to confirm the scaffold is wired correctly:

```bash
dart run artisan list
```

The output lists all registered commands grouped by namespace. A fresh scaffold with no additional plugins shows 21 built-in commands organized across these namespaces:

| Namespace | Commands |
|:----------|:---------|
| (root)    | `help`, `list` |
| `artisan` | `start`, `stop`, `status`, `logs`, `restart`, `reload`, `hot-restart`, `doctor` |
| `commands` | `commands:refresh` |
| `consumer` | `consumer:scaffold` |
| `make` | `make:command`, `make:plugin` |
| `mcp` | `mcp:serve`, `mcp:install`, `mcp:uninstall` |
| `plugin` | `plugin:install`, `plugin:uninstall` |
| `plugins` | `plugins:refresh` |
| `tinker` | `tinker` |

If the list prints without errors, the installation is complete.
