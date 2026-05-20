import 'dart:io';

import 'package:path/path.dart' as p;

import '../console/artisan_context.dart';
import '../console/artisan_generator_command.dart';
import '../console/string_helper.dart';
import '../helpers/config_editor.dart';
import '../helpers/file_helper.dart';
import 'commands_index_writer.dart';

/// `artisan make:command MyCommand` — scaffolds a new ArtisanCommand subclass.
///
/// Output location is context-aware:
/// - **Consumer app** (lib/app/ + a consumer wrapper such as
///   `bin/dispatcher.dart` present): writes to `lib/app/commands/` and
///   refreshes the auto-discovery index so the command shows up on the next
///   `artisan list`.
/// - **Plugin context** (`lib/src/[name]_artisan_provider.dart` present at
///   project root): writes to `lib/src/commands/` (alongside the plugin's
///   install/uninstall commands) and injects an import + registration line
///   into the nearest `*_artisan_provider.dart` so the command shows up
///   inside the plugin's own command surface.
///
/// Name normalization (idempotent): input `Hello` becomes `HelloCommand`;
/// input `HelloCommand` stays `HelloCommand`. The class always ends with
/// `Command`; the signature (kebab) strips the trailing `-command` so the
/// user-facing command name is `hello`, not `hello-command`.
///
/// Default command name derivation (Laravel convention):
///   - `SyncMonitors` → `sync-monitors`
///   - `Admin/UserSync` → `admin:user-sync`
class MakeCommandCommand extends ArtisanGeneratorCommand {
  @override
  String get name => 'make:command';

  @override
  String get description =>
      'Scaffold a new ArtisanCommand subclass under lib/app/commands/ '
      '(or lib/src/commands/ when run inside a plugin).';

  @override
  String getStub() => 'artisan_command';

  /// Returns `lib/src/commands` when invoked inside a plugin (detected via
  /// presence of `lib/src/<name>_artisan_provider.dart`), `lib/app/commands`
  /// otherwise (consumer app convention).
  @override
  String getDefaultNamespace() {
    return _isPluginContext() ? 'lib/src/commands' : 'lib/app/commands';
  }

  @override
  Map<String, String> getReplacements(String name) {
    final normalized = _normalizeName(name);
    final parsed = StringHelper.parseName(normalized);
    final kebab = _toCommandKebab(parsed.className);
    // Two namespace sources compose into the final command signature:
    // - Directory prefix from nested input (`Admin/SyncCommand` →
    //   `admin:sync`).
    // - Plugin prefix from cwd context (inside a plugin, prepend
    //   `<plugin_name>:` so the command lands in the plugin's namespace
    //   in `artisan list` and matches the convention every other plugin
    //   command follows).
    final directoryPrefix = parsed.directory.isEmpty
        ? ''
        : '${parsed.directory.replaceAll('/', ':')}:';
    final pluginPrefix = _isPluginContext() ? '${_pluginName()}:' : '';
    return <String, String>{
      '{{ commandName }}': '$pluginPrefix$directoryPrefix$kebab',
    };
  }

  /// Reads `name:` from the project root's `pubspec.yaml`. Used to derive the
  /// command namespace prefix in plugin context. Falls back to an empty
  /// string when pubspec is missing or malformed (defensive — the caller
  /// guards via `_isPluginContext()` first).
  static String _pluginName() {
    final pubspecPath = p.join(FileHelper.findProjectRoot(), 'pubspec.yaml');
    final file = File(pubspecPath);
    if (!file.existsSync()) return '';
    final match = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(
      file.readAsStringSync(),
    );
    return match?.group(1) ?? '';
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final raw = ctx.input.argument(0);
    if (raw == null || raw.isEmpty) {
      ctx.output.error('Not enough arguments (missing: "name").');
      return 1;
    }
    // Normalize input so the suffix is idempotent across all downstream
    // derivations (file name, class name, signature kebab).
    final normalized = _normalizeName(raw);

    final filePath = getPath(normalized);
    if (FileHelper.fileExists(filePath) && !ctx.input.hasOption('force')) {
      ctx.output.error('File already exists at $filePath');
      return 1;
    }
    final content = buildClass(normalized);
    FileHelper.writeFile(filePath, content);
    ctx.output.success('Created: $filePath');

    final root = FileHelper.findProjectRoot();
    if (_isPluginContext()) {
      // Plugin context: inject import + registration into the plugin's
      // ArtisanServiceProvider so the command appears in the plugin's surface
      // without a manual edit.
      _registerInPluginProvider(ctx, root: root, name: normalized);
    } else {
      // Consumer-app context: refresh the auto-discovery index so the
      // consumer's bin/dispatcher.dart wrapper picks the new command up
      // without an extra `commands:refresh` invocation.
      final commandsDir = Directory(p.join(root, 'lib', 'app', 'commands'));
      writeCommandsIndex(commandsDir);
    }
    return 0;
  }

  /// `Hello` → `HelloCommand`, `HelloCommand` → `HelloCommand` (idempotent).
  /// Operates on the LAST path segment only so `Admin/Sync` becomes
  /// `Admin/SyncCommand`, not `AdminCommand/SyncCommand`.
  static String _normalizeName(String input) {
    final parts = input.split('/');
    final last = parts.last;
    parts[parts.length - 1] =
        last.endsWith('Command') ? last : '${last}Command';
    return parts.join('/');
  }

  /// `HelloCommand` → `hello` (strips the `-command` suffix the kebab
  /// transform would otherwise emit). `SyncMonitorsCommand` → `sync-monitors`.
  /// Acronyms come out noisy (`HTTPCommand` → `h-t-t-p`); users edit the
  /// signature string to taste.
  static String _toCommandKebab(String pascal) {
    final kebab = _toKebabCase(pascal);
    const suffix = '-command';
    if (kebab.endsWith(suffix)) {
      return kebab.substring(0, kebab.length - suffix.length);
    }
    return kebab;
  }

  /// `SyncMonitors` → `sync-monitors` (simple lower-then-upper boundary).
  static String _toKebabCase(String pascal) {
    if (pascal.isEmpty) return pascal;
    return pascal
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}-${m[2]}',
        )
        .toLowerCase();
  }

  /// Plugin context = `lib/src/*_artisan_provider.dart` exists at project
  /// root. The provider file name follows the `<package>_artisan_provider.dart`
  /// convention from the `make:plugin` scaffold.
  static bool _isPluginContext() {
    final root = FileHelper.findProjectRoot();
    final libSrc = Directory(p.join(root, 'lib', 'src'));
    if (!libSrc.existsSync()) return false;
    return libSrc
        .listSync()
        .whereType<File>()
        .any((f) => f.path.endsWith('_artisan_provider.dart'));
  }

  /// Locates the nearest `lib/src/*_artisan_provider.dart` and injects an
  /// import + a `<Class>(),` entry into its `commands()` list. Idempotent
  /// via ConfigEditor's `content.contains(code.trim())` short-circuit.
  static void _registerInPluginProvider(
    ArtisanContext ctx, {
    required String root,
    required String name,
  }) {
    final libSrc = Directory(p.join(root, 'lib', 'src'));
    final providerFile = libSrc.listSync().whereType<File>().firstWhere(
          (f) => f.path.endsWith('_artisan_provider.dart'),
          orElse: () => File(''),
        );
    if (providerFile.path.isEmpty) {
      ctx.output.warning(
        'No <name>_artisan_provider.dart found in lib/src/. '
        'Add the command manually to your ArtisanServiceProvider.commands() list.',
      );
      return;
    }
    final parsed = StringHelper.parseName(name);
    final importStatement = "import 'commands/${parsed.fileName}.dart';";
    final registrationLine = '        ${parsed.className}(),';
    // Idempotent: skip if already registered.
    final before = File(providerFile.path).readAsStringSync();
    if (before.contains(registrationLine.trim())) {
      ctx.output.info(
        '${parsed.className} already registered in '
        '${p.basename(providerFile.path)} (no-op).',
      );
      return;
    }
    // Import at the top (idempotent via addImportToFile).
    ConfigEditor.addImportToFile(
      filePath: providerFile.path,
      importStatement: importStatement,
    );
    // Try to inject at the END of an existing commands list (lookahead
    // anchor on the last entry's trailing comma). When the list is empty
    // the regex has nothing to match, so we fall back to inserting
    // immediately after the opening `<ArtisanCommand>[` of the commands()
    // method. Both branches produce identical final shape for the first
    // and subsequent entries.
    final endOfListMatched = RegExp(r'\w+\(\),(?=\s*\n\s*\])').hasMatch(before);
    if (endOfListMatched) {
      ConfigEditor.insertCodeAfterPattern(
        filePath: providerFile.path,
        pattern: RegExp(r'\w+\(\),(?=\s*\n\s*\])'),
        code: '\n$registrationLine',
      );
    } else {
      ConfigEditor.insertCodeAfterPattern(
        filePath: providerFile.path,
        pattern: RegExp(r'<ArtisanCommand>\['),
        code: '\n$registrationLine',
      );
    }
    ctx.output.info(
      'Registered ${parsed.className} in ${p.basename(providerFile.path)}.',
    );
  }
}
