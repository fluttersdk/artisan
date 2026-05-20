import 'dart:io';

import 'package:path/path.dart' as p;

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../helpers/file_helper.dart';
import '../installer/plugins_registry_file.dart';
import '../installer/virtual_fs.dart';

/// Matches a valid Dart class identifier (PascalCase, ASCII alphanumeric +
/// underscore, no leading digit). Used to defend the code generator against
/// arbitrary strings landing in `.artisan/plugins.json` being interpolated
/// straight into the emitted Dart source.
final RegExp _identifierPattern = RegExp(r'^[A-Z][a-zA-Z0-9_]*$');

/// `artisan plugins:refresh`: regenerates `lib/app/_plugins.g.dart` from the
/// authoritative `.artisan/plugins.json` registry written by plugin install
/// commands.
///
/// The generated file is the consumer-side codegen barrel imported by the
/// project's `bin/dispatcher.dart` wrapper to wire every installed plugin's
/// [ArtisanServiceProvider] into the in-process command registry without
/// `dart:mirrors` (AOT-prohibited) or runtime file scanning.
///
/// Parallels [CommandsRefreshCommand]: both are deterministic codegen
/// primitives ("read source of truth → emit Dart"), both are idempotent
/// (consecutive runs produce byte-identical output), both write atomically
/// via `.tmp` + rename so an open editor never observes a partial file.
///
/// ## Failure modes
///
/// - `lib/app/` missing → [FormatException] pointing the operator at
///   `dart run magic:artisan install`.
/// - Two registry entries claiming the same `providerClass` → [FormatException]
///   naming both colliding plugin names (mirrors the fail-fast collision
///   semantics already enforced by [ArtisanRegistry]).
/// - A `providerClass` that is not a valid Dart identifier →
///   [FormatException] (defense against code injection via the registry).
///
/// ## Testing seams
///
/// The constructor accepts an optional [VirtualFs], an optional
/// `projectRoot` override, and an optional `directoryExists` predicate so the
/// command can be driven against an [InMemoryFs] without touching the host
/// filesystem. Production callers pass nothing and get [RealFs] +
/// [FileHelper.findProjectRoot] + `Directory.existsSync` by default.
class PluginsRefreshCommand extends ArtisanCommand {
  /// Creates a [PluginsRefreshCommand].
  ///
  /// @param fs               File-system abstraction (defaults to [RealFs]).
  /// @param projectRoot      Override for project root resolution; defaults to
  ///                         [FileHelper.findProjectRoot] which walks up from
  ///                         the current working directory looking for
  ///                         `pubspec.yaml`.
  /// @param directoryExists  Predicate used to verify `lib/app/` exists.
  ///                         Defaults to `Directory(absDir).existsSync()`.
  ///                         Tests inject an in-memory probe so unit tests
  ///                         never touch disk.
  PluginsRefreshCommand({
    VirtualFs? fs,
    String? projectRoot,
    bool Function(String absDir)? directoryExists,
  })  : _fs = fs ?? const RealFs(),
        _projectRootOverride = projectRoot,
        _directoryExists = directoryExists ?? _defaultDirectoryExists;

  final VirtualFs _fs;
  final String? _projectRootOverride;
  final bool Function(String absDir) _directoryExists;

  static bool _defaultDirectoryExists(String absDir) =>
      Directory(absDir).existsSync();

  @override
  String get signature => 'plugins:refresh';

  @override
  String get description =>
      'Regenerate lib/app/_plugins.g.dart from .artisan/plugins.json registry.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Resolve where in the host filesystem to operate.
    final root = _projectRootOverride ?? FileHelper.findProjectRoot();
    final libAppDir = p.join(root, 'lib', 'app');
    final outputPath = p.join(libAppDir, '_plugins.g.dart');

    // 2. Refuse to write into a non-magic-structured project so the operator
    //    gets a clear pointer to the bootstrap command rather than a mystery
    //    file appearing under lib/.
    if (!_directoryExists(libAppDir)) {
      throw FormatException(
        'lib/app/ directory not found at $libAppDir. '
        'Project does not look magic-structured. '
        'Run `dart run magic:artisan install` first to bootstrap.',
      );
    }

    // 3. Read the authoritative registry. Missing file is treated as empty.
    final registry = await PluginsRegistryFile(_fs, root).read();
    final entries = registry.plugins;

    // 4. Defend the generator against arbitrary identifiers from JSON:
    //    every providerClass must be a valid Dart class name BEFORE it lands
    //    in source code, and no two entries may claim the same class.
    _validateIdentifiers(entries);
    _validateNoCollisions(entries);

    // 5. Render + atomically swap the generated file.
    final source = _renderSource(_sortedForOutput(entries));
    _atomicWrite(outputPath, source);

    // 6. Summarise so the operator sees what landed.
    ctx.output.success(
      'Refreshed ${entries.length} plugin(s) → ${p.join('lib', 'app', '_plugins.g.dart')}',
    );
    return 0;
  }

  /// Throws [FormatException] when any [PluginEntry.providerClass] is not a
  /// valid Dart identifier.
  void _validateIdentifiers(List<PluginEntry> entries) {
    for (final entry in entries) {
      if (!_identifierPattern.hasMatch(entry.providerClass)) {
        throw FormatException(
          'Invalid providerClass "${entry.providerClass}" for plugin '
          '"${entry.name}" in .artisan/plugins.json. '
          'Expected a PascalCase Dart identifier matching '
          r'^[A-Z][a-zA-Z0-9_]*$.',
        );
      }
    }
  }

  /// Throws [FormatException] when two entries register the same
  /// `providerClass`. Names every colliding plugin so the operator can fix
  /// the registry without guessing which packages clashed.
  void _validateNoCollisions(List<PluginEntry> entries) {
    final byClass = <String, List<String>>{};
    for (final entry in entries) {
      byClass
          .putIfAbsent(entry.providerClass, () => <String>[])
          .add(entry.name);
    }
    for (final mapEntry in byClass.entries) {
      if (mapEntry.value.length > 1) {
        final names = (mapEntry.value.toList()..sort()).join(', ');
        throw FormatException(
          'Duplicate providerClass "${mapEntry.key}" claimed by plugins: '
          '$names. Each plugin must contribute a unique provider class.',
        );
      }
    }
  }

  /// Returns [entries] sorted alphabetically by `providerClass` so the
  /// generated file is byte-identical across consecutive runs regardless of
  /// the registry's insertion order.
  List<PluginEntry> _sortedForOutput(List<PluginEntry> entries) {
    final copy = entries.toList(growable: false);
    copy.sort((a, b) => a.providerClass.compareTo(b.providerClass));
    return copy;
  }

  /// Renders the Dart source file from a list of entries already sorted by
  /// [_sortedForOutput]. Pure function (no I/O, no clock reads) so the
  /// output is fully determined by the inputs (idempotence guarantee).
  String _renderSource(List<PluginEntry> entries) {
    final buf = StringBuffer()
      ..writeln('// GENERATED: do not edit by hand.')
      ..writeln('// Regenerate via: dart run magic:artisan plugins:refresh')
      ..writeln('//')
      ..writeln('// Source: .artisan/plugins.json')
      ..writeln()
      ..writeln("import 'package:fluttersdk_artisan/artisan.dart';");

    if (entries.isEmpty) {
      buf
        ..writeln()
        ..writeln('List<ArtisanServiceProvider> autoDiscoveredProviders() {')
        ..writeln('  return <ArtisanServiceProvider>[];')
        ..writeln('}')
        ..writeln();
      return buf.toString();
    }

    // Imports sorted by providerImport for deterministic ordering, then
    // deduplicated so a hypothetical future where two plugins share the same
    // import URI emits one import (still safe because providerClass is unique
    // per the collision guard above).
    final imports = <String, String>{}; // providerImport -> providerClass
    for (final e in entries) {
      imports[e.providerImport] = e.providerClass;
    }
    final sortedImports = imports.keys.toList()..sort();
    for (final importUri in sortedImports) {
      buf.writeln("import '$importUri' show ${imports[importUri]};");
    }

    buf
      ..writeln()
      ..writeln('List<ArtisanServiceProvider> autoDiscoveredProviders() {')
      ..writeln('  return <ArtisanServiceProvider>[');
    for (final entry in entries) {
      buf.writeln('    ${entry.providerClass}(),');
    }
    buf
      ..writeln('  ];')
      ..writeln('}')
      ..writeln();
    return buf.toString();
  }

  /// Writes [content] to [outputPath] using a `.tmp` + rename so concurrent
  /// readers (open editors, lint daemons) never observe a partial file.
  ///
  /// Mirrors the same pattern used by [PluginsRegistryFile.write] and
  /// [InstallTransaction.commit].
  void _atomicWrite(String outputPath, String content) {
    final tmpPath = '$outputPath.tmp';
    _fs.writeAsString(tmpPath, content);
    _fs.rename(tmpPath, outputPath);
  }
}
