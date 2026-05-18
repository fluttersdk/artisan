import 'dart:convert';

import 'package:path/path.dart' as p;

import 'virtual_fs.dart';

/// Immutable value object representing a single registered plugin entry inside
/// `.artisan/plugins.json`.
///
/// All fields are required. The [registeredAt] field carries an ISO-8601
/// UTC timestamp string rather than a [DateTime] so callers control formatting
/// and the JSON representation stays human-readable without a custom encoder.
final class PluginEntry {
  /// Short, unique plugin identifier (e.g. `firebase_messaging`).
  final String name;

  /// Dart import URI for the provider class (e.g.
  /// `package:magic_firebase/src/firebase_service_provider.dart`).
  final String providerImport;

  /// Unqualified class name of the provider (e.g. `FirebaseServiceProvider`).
  final String providerClass;

  /// ISO-8601 UTC timestamp recording when this entry was created or last
  /// replaced (e.g. `2026-05-18T10:00:00.000Z`).
  final String registeredAt;

  /// Creates a [PluginEntry].
  ///
  /// @param name           Unique plugin name.
  /// @param providerImport Dart import URI for the provider class.
  /// @param providerClass  Unqualified provider class name.
  /// @param registeredAt   ISO-8601 UTC registration timestamp.
  const PluginEntry({
    required this.name,
    required this.providerImport,
    required this.providerClass,
    required this.registeredAt,
  });

  /// Deserialises a [PluginEntry] from a JSON object map.
  ///
  /// @param json  Raw JSON map as decoded by `dart:convert`.
  /// @return A populated [PluginEntry].
  factory PluginEntry.fromJson(Map<String, dynamic> json) {
    return PluginEntry(
      name: json['name'] as String,
      providerImport: json['providerImport'] as String,
      providerClass: json['providerClass'] as String,
      registeredAt: json['registeredAt'] as String,
    );
  }

  /// Serialises this entry to a JSON-compatible map.
  ///
  /// @return A [Map] suitable for `jsonEncode`.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'providerImport': providerImport,
      'providerClass': providerClass,
      'registeredAt': registeredAt,
    };
  }
}

/// Immutable value object representing the full contents of
/// `.artisan/plugins.json`.
///
/// [version] is the schema version (currently `1`). Future schema changes
/// increment this; [PluginsRegistryFile.read] rejects any version above `1`
/// with a [FormatException] so old tooling fails loudly rather than silently
/// misinterpreting a newer format.
final class PluginsRegistry {
  /// Schema version. Must be `1` for this release of the tooling.
  final int version;

  /// Ordered list of registered plugin entries.
  final List<PluginEntry> plugins;

  /// Creates a [PluginsRegistry].
  ///
  /// @param version  Schema version (default `1`).
  /// @param plugins  List of [PluginEntry] items (default empty).
  const PluginsRegistry({
    this.version = 1,
    this.plugins = const <PluginEntry>[],
  });

  /// Returns an empty registry at schema version 1.
  ///
  /// @return A [PluginsRegistry] with no plugins.
  factory PluginsRegistry.empty() {
    return const PluginsRegistry(
      version: 1,
      plugins: <PluginEntry>[],
    );
  }

  /// Deserialises a [PluginsRegistry] from a JSON object map.
  ///
  /// @param json  Raw JSON map as decoded by `dart:convert`.
  /// @return A populated [PluginsRegistry].
  factory PluginsRegistry.fromJson(Map<String, dynamic> json) {
    final rawPlugins = (json['plugins'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(PluginEntry.fromJson)
        .toList(growable: false);

    return PluginsRegistry(
      version: json['version'] as int? ?? 1,
      plugins: rawPlugins,
    );
  }

  /// Serialises this registry to a JSON-compatible map.
  ///
  /// @return A [Map] suitable for `jsonEncode`.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'plugins': plugins.map((e) => e.toJson()).toList(growable: false),
    };
  }
}

/// Reads and writes the `.artisan/plugins.json` registry file through a
/// [VirtualFs] abstraction so the class is fully testable without touching
/// the host filesystem.
///
/// Schema: `{"version": 1, "plugins": [...]}`
///
/// ## Atomic write
///
/// [write] follows the same `.tmp` + rename pattern used by
/// [InstallTransaction]: content is written to
/// `<projectRoot>/.artisan/plugins.json.tmp` first and then renamed over the
/// target. On POSIX systems this rename is atomic, so readers never observe a
/// partial write.
///
/// ## Idempotent mutations
///
/// [addPlugin] replaces any existing entry with the same [PluginEntry.name]
/// instead of appending a duplicate. [removePlugin] is a no-op when the name
/// is absent.
///
/// ## Version guard
///
/// [read] throws [FormatException] when the stored version field exceeds `1`
/// so old tooling fails loudly rather than silently misinterpreting a newer
/// schema.
///
/// ## Usage
///
/// ```dart
/// final rf = PluginsRegistryFile(RealFs(), projectRoot);
/// await rf.addPlugin(PluginEntry(
///   name: 'firebase_messaging',
///   providerImport: 'package:magic_firebase/src/provider.dart',
///   providerClass: 'FirebaseProvider',
///   registeredAt: DateTime.now().toUtc().toIso8601String(),
/// ));
/// ```
class PluginsRegistryFile {
  /// Creates a [PluginsRegistryFile] bound to the given [VirtualFs] and
  /// [projectRoot].
  ///
  /// @param _fs           File-system abstraction (production: [RealFs];
  ///                      tests: [InMemoryFs]).
  /// @param _projectRoot  Absolute path to the Flutter project root. The
  ///                      registry lives at
  ///                      `<_projectRoot>/.artisan/plugins.json`.
  PluginsRegistryFile(this._fs, this._projectRoot);

  final VirtualFs _fs;
  final String _projectRoot;

  /// Absolute path of the registry file.
  String get _registryPath => p.join(_projectRoot, '.artisan', 'plugins.json');

  /// Absolute path of the temporary write target used during atomic writes.
  String get _tmpPath => '$_registryPath.tmp';

  /// Reads the registry from disk.
  ///
  /// Returns [PluginsRegistry.empty] when the file does not exist or is empty.
  ///
  /// @return The current [PluginsRegistry].
  /// @throws FormatException  When the stored `version` field exceeds `1`.
  Future<PluginsRegistry> read() async {
    // 1. Missing file is treated as an empty registry on first use.
    if (!_fs.exists(_registryPath)) {
      return PluginsRegistry.empty();
    }

    // 2. Empty file content (e.g. truncated write) is also treated as empty.
    final raw = _fs.readAsString(_registryPath).trim();
    if (raw.isEmpty) {
      return PluginsRegistry.empty();
    }

    // 3. Parse and validate the schema version before returning.
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final version = json['version'] as int? ?? 1;
    if (version > 1) {
      throw FormatException(
        'plugins.json schema version $version is not supported by this '
        'version of fluttersdk_artisan (max supported: 1). '
        'Upgrade the artisan tooling to read this registry.',
      );
    }

    return PluginsRegistry.fromJson(json);
  }

  /// Atomically writes [registry] to disk using a `.tmp` + rename strategy.
  ///
  /// @param registry  The [PluginsRegistry] to persist.
  Future<void> write(PluginsRegistry registry) async {
    const encoder = JsonEncoder.withIndent('  ');
    final content = encoder.convert(registry.toJson());

    // 1. Write to the temporary file first so no partial state is visible at
    //    the target path during the write.
    _fs.writeAsString(_tmpPath, content);

    // 2. Atomically rename the temporary file over the target (POSIX rename(2)).
    _fs.rename(_tmpPath, _registryPath);
  }

  /// Adds [entry] to the registry.
  ///
  /// When an entry with the same [PluginEntry.name] already exists it is
  /// replaced in-place so callers remain idempotent.
  ///
  /// @param entry  The [PluginEntry] to add or replace.
  Future<void> addPlugin(PluginEntry entry) async {
    final current = await read();

    // 1. Build the updated list, replacing any existing entry with the same
    //    name so addPlugin remains idempotent.
    final updated = [
      for (final existing in current.plugins)
        if (existing.name != entry.name) existing,
      entry,
    ];

    await write(PluginsRegistry(version: current.version, plugins: updated));
  }

  /// Removes the plugin identified by [name] from the registry.
  ///
  /// This is a no-op when no entry with that name exists, making it safe to
  /// call from uninstall commands without a prior existence check.
  ///
  /// @param name  The plugin name to remove.
  Future<void> removePlugin(String name) async {
    final current = await read();

    final updated = [
      for (final entry in current.plugins)
        if (entry.name != name) entry,
    ];

    await write(PluginsRegistry(version: current.version, plugins: updated));
  }
}
