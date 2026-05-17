# Changelog

All notable changes to this project will be documented in this file.

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.0.1-alpha.6] - 2026-04-07

### 🔧 Improvements

- **Route Page Titles**: Add `.title('Welcome')` to generated welcome route for browser tab titles

---

## [0.0.1-alpha.5] - 2026-04-07

### ✨ New Features

- **Routing Config**: Generate `config/routing.dart` with URL strategy setting during `magic install` — enables clean web URLs via `url_strategy: 'path'`

---

## [0.0.1-alpha.4] - 2026-04-06

### ✨ New Features

- **Broadcasting Support**: Add `--without-broadcasting` flag to `install` command with `config/broadcasting.dart` stub and Reverb connection config
- **Conditional Env Vars**: Broadcasting env vars (`BROADCAST_CONNECTION`, `REVERB_*`) only generated when broadcasting is enabled

### 🔧 Improvements

- **Documentation**: Update homepage URL to Magic website package page, add "Website" link to README, update CLI Commands link in welcome view stub

---

## [0.0.1-alpha.3] - 2026-03-24

### ✨ New Features

- **Install Command Rewrite**: Full project scaffold with welcome page, configs, providers, routes, and `main.dart` bootstrap
- **Install Stubs**: External `.stub` templates for all install-generated files (configs, kernel, providers, welcome view, env)
- **New Generators**: `make:enum`, `make:event`, `make:listener`, `make:request` commands registered and functional
- **StubLoader**: Multi-strategy stub resolution via `package_config.json`, `Platform.script` walk-up, and env var override
- **Deep Merge Utilities**: `JsonEditor` with additive deep merge mode for config file editing
- **StubLoader Export**: `StubLoader` now available in public barrel export for plugin consumers
- **Welcome View**: Animated welcome page with hero logo (bounce) and heart (pulse) generated on install

### 🐛 Bug Fixes

- **Auth Config**: Wrapped auth configuration under `'auth'` key and fixed provider boot order
- **Install Cross-Platform**: `magic install` now produces a working app on all platforms
- **Stub Placeholders**: Fixed double-async injection, missing replacements, and placeholder casing issues
- **main.dart Bootstrap**: Correctly makes `main()` async when injecting `await Magic.init()`
- **Command Help**: Fixed `--help` flag being blocked by global help check on namespaced commands
- **Generated Code Quality**: All generated code now passes `dart analyze` on clean projects
- **StubLoader Paths**: Removed hardcoded developer paths and `FLUTTER_TEST` branch that broke CI on Ubuntu

### 🔧 Improvements

- **Stub Extraction**: Migrated all static Dart string constants to external `.stub` template files
- **Code Quality**: Multi-line collections, catch comments, param docblocks, type safety fixes
- **Integration Tests**: Kernel dispatch and key:generate flow tests
- **make:model Flags**: Composite generation with `-mcfsp` and `--all` flags (migration + controller + factory + seeder + policy)
- **Barrel Export**: Updated `magic_cli.dart` with complete public API surface
- **CI/CD**: Bumped `actions/checkout` to v6 and `codecov/codecov-action` to v5
- **Project Infra**: Added CLAUDE.md, GitHub issue templates, dependabot config, release workflow, and `.claude/rules/`

---

## [0.0.1-alpha.2] - 2026-03-15

### 🔧 Improvements

- **CI/CD**: GitHub Actions integration with automated testing, linting, and formatting
- **Dependencies**: Fixed `flutter_test` compatibility constraints
- **Linter**: Updated rules for CI environment compliance
- **README**: Added CI status badge
- **Tests**: All 118 tests passing with automated test suite

---

## [0.0.1-alpha.1] - 2026-03-14

### 🎉 First Alpha Release

Magic CLI v0.0.1-alpha.1 is the first public preview — an Artisan-inspired CLI for scaffolding Magic Framework projects.

### ✨ Core Features

**Generators:**
- `make:model` — Eloquent-style models with typed getters/setters
- `make:controller` — Controllers with optional resource actions (`--resource`)
- `make:view` — Views with stateful option (`--stateful`)
- `make:migration` — Timestamped database migrations
- `make:seeder` — Database seeders
- `make:factory` — Model factories
- `make:policy` — Authorization policies
- `make:lang` — Translation JSON files
- `make:provider` — Service providers
- `make:middleware` — Middleware classes

**Utilities:**
- `install` — Initialize Magic in a Flutter project with configurable feature flags
- `key:generate` — Generate application encryption key

### 🔧 Quality & Infrastructure

- **Kernel Architecture**: Command registry with namespace grouping and auto-help
- **GeneratorCommand Base**: Reusable stub loading and placeholder replacement
- **StringHelper**: Case conversion (pascal, snake, camel), pluralization, nested path parsing
- **ConsoleStyle**: ANSI-colored output, tables, interactive prompts
- **FileHelper**: File I/O, YAML operations, project root detection
- **ConfigEditor**: pubspec.yaml and Dart file programmatic editing

### 📦 Dependencies

- `args: ^2.7.0` — CLI argument parsing
- `path: ^1.9.0` — Cross-platform path manipulation
- `yaml: ^3.1.3` — YAML reading
- `yaml_edit: ^2.2.3` — YAML writing

---

## Previous Versions

See [full commit history](https://github.com/fluttersdk/magic_cli/commits/master) for detailed changes.
