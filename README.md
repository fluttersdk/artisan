<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Magic Logo" />
</p>

<h1 align="center">Magic CLI</h1>

<p align="center">
  <strong>Artisan-inspired CLI for Flutter, powered by the Magic Framework.</strong><br/>
  Scaffold controllers, models, views, migrations, and more — with a single command.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_cli"><img src="https://img.shields.io/pub/v/magic_cli.svg" alt="pub package"></a>
  <a href="https://github.com/fluttersdk/magic_cli/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/magic_cli/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_cli/score"><img src="https://img.shields.io/pub/points/magic_cli" alt="pub points"></a>
  <a href="https://github.com/fluttersdk/magic_cli/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/magic_cli?style=flat" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://magic.fluttersdk.com/packages/magic-cli">Website</a> ·
  <a href="https://pub.dev/packages/magic_cli">pub.dev</a> ·
  <a href="https://github.com/fluttersdk/magic_cli/issues">Issues</a> ·
  <a href="https://github.com/fluttersdk/magic_cli/discussions">Discussions</a>
</p>

---

> **Alpha Release** — Magic CLI is under active development. APIs may change before stable. [Star the repo](https://github.com/fluttersdk/magic_cli) to follow progress.

## Why Magic CLI?

Flutter projects require a lot of boilerplate — models, controllers, migrations, views, policies, seeders, factories, providers. Creating each file manually means remembering directory conventions, import paths, and class structures every time.

**Magic CLI fixes this.** One command generates the correct file in the correct directory with the correct structure:

```bash
# Before — manual boilerplate
# Create file, remember the path, copy-paste template, fix imports, add to config...

# After — Magic way
magic make:model User -mcfsp
# ✓ Created: lib/app/models/user.dart
# ✓ Created: lib/database/migrations/m_20260324_120000_create_users_table.dart
# ✓ Created: lib/app/controllers/user_controller.dart
# ✓ Created: lib/database/factories/user_factory.dart
# ✓ Created: lib/database/seeders/user_seeder.dart
# ✓ Created: lib/app/policies/user_policy.dart
```

If you know Laravel's Artisan, you already know Magic CLI.

## Features

| | Feature | Description |
|:--|:--------|:------------|
| 🏗️ | **16 Generators** | `make:model`, `make:controller`, `make:view`, `make:migration`, `make:policy`, and 11 more |
| ⚡ | **Composite Scaffolding** | `make:model -mcfsp` generates model + migration + controller + factory + seeder + policy in one command |
| 📁 | **Nested Paths** | `make:controller Admin/Dashboard` → `lib/app/controllers/admin/dashboard_controller.dart` |
| 🔧 | **Project Initialization** | `magic install` sets up the full Magic directory structure and config files |
| 🔑 | **Key Generation** | `magic key:generate` creates secure encryption keys in `.env` |
| 🎨 | **Smart Suffixes** | `make:controller User` and `make:controller UserController` both work — no double-suffix bugs |
| 📝 | **Stub Templates** | Customizable `.stub` files with `{{ placeholder }}` syntax |

## Quick Start

### 1. Install

```bash
dart pub global activate magic_cli
```

Ensure `~/.pub-cache/bin` is in your PATH.

### 2. Initialize your project

```bash
cd my_flutter_app
magic install
```

### 3. Start scaffolding

```bash
magic make:model Post -mcf
magic make:view Dashboard --stateful
magic make:middleware Auth
magic make:enum Status
```

## Commands

### Project Setup

| Command | Description |
|---------|-------------|
| `magic install` | Initialize Magic in a Flutter project |
| `magic key:generate` | Generate a new application encryption key |

### Generators

| Command | Description |
|---------|-------------|
| `magic make:model Name` | Create an Eloquent model class |
| `magic make:controller Name` | Create a controller class |
| `magic make:view Name` | Create a view class |
| `magic make:migration name` | Create a database migration |
| `magic make:policy Name` | Create an authorization policy |
| `magic make:seeder Name` | Create a database seeder |
| `magic make:factory Name` | Create a model factory |
| `magic make:provider Name` | Create a service provider |
| `magic make:middleware Name` | Create a middleware class |
| `magic make:enum Name` | Create a string-backed enum |
| `magic make:event Name` | Create an event class |
| `magic make:listener Name` | Create an event listener |
| `magic make:request Name` | Create a form request with validation |
| `magic make:lang code` | Create a language JSON file |

## Command Details

### `magic install`

Initializes the Magic Framework in your Flutter project — creates directories, config files, providers, routes, and bootstraps `main.dart`.

```bash
magic install
magic install --without-database --without-auth
```

**Options:**

| Option | Description |
|--------|-------------|
| `--without-database` | Skip database setup |
| `--without-auth` | Skip authentication setup |
| `--without-network` | Skip network setup |
| `--without-cache` | Skip cache setup |
| `--without-events` | Skip events setup |
| `--without-localization` | Skip localization setup |
| `--without-logging` | Skip logging setup |
| `--without-broadcasting` | Skip broadcasting setup |

<details>
<summary><strong>Generated Structure</strong></summary>

```
lib/
├── config/
│   ├── app.dart
│   ├── auth.dart
│   ├── broadcasting.dart
│   ├── cache.dart
│   ├── database.dart
│   ├── logging.dart
│   ├── network.dart
│   ├── routing.dart
│   └── view.dart
├── app/
│   ├── controllers/
│   ├── models/
│   ├── policies/
│   ├── middleware/
│   └── providers/
│       ├── app_service_provider.dart
│       └── route_service_provider.dart
├── database/
│   ├── migrations/
│   ├── seeders/
│   └── factories/
├── resources/
│   └── views/
├── routes/
│   └── app.dart
├── main.dart
├── .env
└── .env.example
```

</details>

---

### `magic make:model`

Creates an Eloquent-style model with optional related files.

```bash
magic make:model User
magic make:model Post -mcf        # model + migration + controller + factory
magic make:model Comment -mcfsp   # all related files
magic make:model Comment --all    # same as -mcfsp
magic make:model Admin/Profile    # nested path
```

**Options:**

| Option | Short | Description |
|--------|-------|-------------|
| `--migration` | `-m` | Create a migration file |
| `--controller` | `-c` | Create a controller |
| `--factory` | `-f` | Create a model factory |
| `--seeder` | `-s` | Create a seeder |
| `--policy` | `-p` | Create a policy |
| `--all` | `-a` | Create all related files |
| `--force` | `-F` | Overwrite existing files |

---

### `magic make:controller`

Creates a controller class. Suffix `Controller` is auto-appended.

```bash
magic make:controller User                     # → lib/app/controllers/user_controller.dart
magic make:controller UserController           # Same result — smart suffix handling
magic make:controller Admin/Dashboard          # → lib/app/controllers/admin/dashboard_controller.dart
magic make:controller Post --resource          # Resource controller with CRUD methods
magic make:controller Post --resource --model Post  # Resource with model binding
```

**Options:**

| Option | Short | Description |
|--------|-------|-------------|
| `--resource` | `-r` | Generate CRUD methods (index, show, store, update, destroy) |
| `--model` | `-m` | Specify the model for resource controller |

---

### `magic make:view`

Creates a view class. Suffix `View` is auto-appended.

```bash
magic make:view Login                 # → lib/resources/views/login_view.dart
magic make:view Auth/Register         # → lib/resources/views/auth/register_view.dart
magic make:view Dashboard --stateful  # Stateful view with lifecycle hooks
```

**Options:**

| Option | Description |
|--------|-------------|
| `--stateful` | Generate a stateful view with lifecycle hooks |

---

### `magic make:migration`

Creates a timestamped migration file.

```bash
magic make:migration create_users_table
magic make:migration create_posts_table --create=posts
magic make:migration add_email_to_users --table=users
```

**Options:**

| Option | Short | Description |
|--------|-------|-------------|
| `--create` | `-c` | The table to be created (uses create stub) |
| `--table` | `-t` | The table to migrate |

**Output:** `lib/database/migrations/m_YYYYMMDDHHMMSS_create_users_table.dart`

---

### `magic make:policy`

Creates an authorization policy. Suffix `Policy` is auto-appended.

```bash
magic make:policy Post                       # → lib/app/policies/post_policy.dart
magic make:policy Post --model=Post          # With model binding
magic make:policy Admin/Dashboard            # Nested path
```

**Options:**

| Option | Short | Description |
|--------|-------|-------------|
| `--model` | `-m` | The model the policy applies to |

---

### Other Generators

All generators support `--force` to overwrite existing files and nested paths via `/` separator.

```bash
# Service provider — auto-appends ServiceProvider suffix
magic make:provider App                      # → lib/app/providers/app_service_provider.dart

# Seeder — auto-appends Seeder suffix
magic make:seeder User                       # → lib/database/seeders/user_seeder.dart

# Factory — auto-appends Factory suffix
magic make:factory User                      # → lib/database/factories/user_factory.dart

# Form request — auto-appends Request suffix
magic make:request StoreUser                 # → lib/app/requests/store_user_request.dart

# Middleware
magic make:middleware Auth                   # → lib/app/middleware/auth_middleware.dart

# Enum with value/label and selectOptions
magic make:enum Status                       # → lib/app/enums/status.dart

# Event class
magic make:event UserRegistered              # → lib/app/events/user_registered_event.dart

# Event listener
magic make:listener SendWelcomeEmail         # → lib/app/listeners/send_welcome_email_listener.dart

# Language file
magic make:lang tr                           # → assets/lang/tr.json
```

---

### `magic key:generate`

Generates a secure encryption key and writes it to `.env`.

```bash
magic key:generate
```

Updates your `.env` file with:
```
APP_KEY=base64:randomGeneratedKey...
```

## Authoring a Plugin

Run `dart run fluttersdk_artisan make:plugin foo_bar` (where `foo_bar` is your
snake_case package name) to scaffold a complete 11-file plugin skeleton under
`packages/foo_bar/`. The skeleton includes a `pubspec.yaml`, CLI barrel, runtime
barrel, `ArtisanServiceProvider`, install and uninstall commands, an
`install.yaml` manifest, a sample config stub, and two seed test files. It
compiles and `dart test` passes without manual edits.

Write your install logic declaratively in `install.yaml` (YAML-first, no Dart
required for common cases) OR imperatively in
`lib/src/commands/install_command.dart` using the `PluginInstaller` fluent
builder. The fluent builder chains pubspec mutations, file writes, code injections,
native-platform wiring, env-var declarations, interactive prompts, and shell hooks
in a single expression that commits atomically with conflict detection and an
install-record your `plugin:uninstall` command can reverse.

For the full schema, method catalog, testing patterns, conflict-handling rules,
and common recipes, see the
[Plugin Authoring Guide](doc/plugin_authoring_guide.md).

## Plugin Integration

Magic CLI exports its infrastructure for other plugins to build on — custom commands, stub loaders, file helpers, and console styling.

```yaml
# pubspec.yaml in your plugin
dependencies:
  magic_cli: ^0.0.1
```

### Creating Custom Commands

```dart
import 'package:magic_cli/magic_cli.dart';

class MakeJobCommand extends GeneratorCommand {
  @override
  String get name => 'make:job';

  @override
  String get description => 'Create a new job class';

  @override
  String getDefaultNamespace() => 'lib/app/jobs';

  @override
  String getStub() => 'job';

  @override
  Map<String, String> getReplacements(String name) {
    final parsed = StringHelper.parseName(name);
    return {
      '{{ snakeName }}': StringHelper.toSnakeCase(parsed.className),
    };
  }
}
```

### Available Helpers

<details>
<summary><strong>ConsoleStyle</strong> — ANSI-colored output, tables, formatted messages</summary>

```dart
// Output methods (available via Command base class)
success('Created successfully');   // ✓ green
error('File not found');           // ✗ red
info('Processing...');             // ℹ blue
warn('File already exists');       // ⚠ yellow

// Interactive prompts
final name = ask('Project name?', defaultValue: 'my_app');
final ok = confirm('Continue?', defaultValue: true);

// Tables
table(['Name', 'Status'], [
  ['User', 'Active'],
  ['Admin', 'Inactive'],
]);
```

</details>

<details>
<summary><strong>FileHelper</strong> — File I/O, YAML, project root detection</summary>

```dart
FileHelper.fileExists('pubspec.yaml');
FileHelper.readFile('lib/main.dart');
FileHelper.writeFile('lib/config/app.dart', content);
FileHelper.ensureDirectoryExists('lib/app/models');
FileHelper.findProjectRoot();

final yaml = FileHelper.readYamlFile('pubspec.yaml');
```

</details>

<details>
<summary><strong>StubLoader</strong> — Template loading and placeholder replacement</summary>

```dart
// Load and replace in one step
final content = await StubLoader.make('controller', {
  'className': 'UserController',
  'namespace': 'lib/app/controllers',
});

// Or separately
final stub = await StubLoader.load('model');
final result = StubLoader.replace(stub, {
  'className': 'Post',
  'tableName': 'posts',
});
```

</details>

<details>
<summary><strong>ConfigEditor</strong> — pubspec.yaml and Dart file editing</summary>

```dart
ConfigEditor.addDependencyToPubspec(
  pubspecPath: 'pubspec.yaml',
  name: 'my_package',
  version: '^1.0.0',
);

ConfigEditor.addImportToFile(
  filePath: 'lib/config/app.dart',
  importStatement: "import 'package:my_app/app/providers/custom_provider.dart';",
);
```

</details>

<details>
<summary><strong>StringHelper</strong> — Case conversion and name parsing</summary>

```dart
StringHelper.toPascalCase('user_profile');  // UserProfile
StringHelper.toSnakeCase('UserProfile');    // user_profile
StringHelper.toCamelCase('user_profile');   // userProfile
StringHelper.toPlural('post');              // posts

// Nested path parsing
final parsed = StringHelper.parseName('Admin/Dashboard');
// parsed.directory  → 'admin'
// parsed.className  → 'Dashboard'
// parsed.fileName   → 'dashboard'
```

</details>

## Architecture

Magic CLI uses a Kernel-based command registry — inspired by Laravel Artisan:

```
bin/magic.dart (entry point)
    ↓
Kernel.register(commands)
    ↓
Kernel.handle(args) → lookup by name → parse flags → command.handle()
    ↓
GeneratorCommand: load .stub → replace {{ placeholders }} → write file
```

**Command types:**
- **GeneratorCommand** — base for all `make:*` commands (stub loading + placeholder replacement)
- **Command** — base for utility commands (`install`, `key:generate`)

**Stub system:** `.stub` files in `assets/stubs/` with `{{ className }}`, `{{ namespace }}`, and custom placeholders. `StubLoader` resolves stubs via multi-strategy path resolution.

## Contributing

```bash
git clone https://github.com/fluttersdk/magic_cli.git
cd magic_cli && flutter pub get
flutter test && dart analyze
```

[Report a bug](https://github.com/fluttersdk/magic_cli/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/fluttersdk/magic_cli/issues/new?template=feature_request.yml)

## License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a></sub><br/>
  <sub>If Magic CLI saves you time, <a href="https://github.com/fluttersdk/magic_cli">give it a star</a> — it helps others discover it.</sub>
</p>
