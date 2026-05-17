import 'dart:convert';
import 'dart:io';

/// JSON file manipulation helper for CLI commands.
///
/// Provides utilities for reading, writing, and merging JSON files using only
/// Dart's built-in `dart:convert` library — no external packages required.
///
/// ## Usage
///
/// ```dart
/// // Read a JSON file
/// final data = JsonEditor.readJson('/path/to/manifest.json');
///
/// // Merge a single key (idempotent overwrite)
/// JsonEditor.mergeKey('/path/to/manifest.json', 'gcm_sender_id', '482941778795');
///
/// // Deep-merge two maps (nested translation files, configs, etc.)
/// final merged = JsonEditor.deepMerge(existing, incoming);
///
/// // Merge an incoming JSON file into an existing one (idempotent)
/// JsonEditor.mergeJsonFile('/app/assets/lang/en.json', '/stubs/en.json');
///
/// // Write a full map
/// JsonEditor.writeJson('/path/to/output.json', {'key': 'value'});
///
/// // Check if a key exists
/// if (!JsonEditor.hasKey('/path/to/manifest.json', 'gcm_sender_id')) {
///   JsonEditor.mergeKey(...);
/// }
/// ```
class JsonEditor {
  JsonEditor._();

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Read and parse a JSON file from [path].
  ///
  /// @param path  Absolute or relative path to the `.json` file.
  /// @return A [Map<String, dynamic>] of the decoded JSON object.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [FormatException]     if the file contains invalid JSON.
  static Map<String, dynamic> readJson(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('JSON file not found', path);
    }

    final content = file.readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Write
  // -------------------------------------------------------------------------

  /// Serialise [data] and write it to [path] as pretty-printed JSON.
  ///
  /// Creates parent directories and the file if they do not exist.
  /// Overwrites any existing content.
  ///
  /// @param path    Destination file path.
  /// @param data    The object to serialise (typically `Map<String, dynamic>`).
  /// @param indent  Number of spaces for indentation (default: `2`).
  static void writeJson(
    String path,
    dynamic data, {
    int indent = 2,
  }) {
    final file = File(path);

    // 1. Ensure parent directory exists.
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    // 2. Encode and write with the requested indentation.
    final encoder = JsonEncoder.withIndent(' ' * indent);
    file.writeAsStringSync(encoder.convert(data));
  }

  // -------------------------------------------------------------------------
  // Merge
  // -------------------------------------------------------------------------

  /// Read the JSON file at [path], set [key] to [value], and write it back.
  ///
  /// All existing keys are preserved. If [key] already exists its value is
  /// overwritten.
  ///
  /// @param path   Path to the `.json` file.
  /// @param key    Top-level key to insert or update.
  /// @param value  The new value for [key].
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [FormatException]     if the file contains invalid JSON.
  static void mergeKey(String path, String key, dynamic value) {
    // 1. Load current state.
    final data = readJson(path);

    // 2. Apply the change.
    data[key] = value;

    // 3. Persist.
    writeJson(path, data);
  }

  /// Deep-merge [source] into [target], returning a new map.
  ///
  /// When both [target] and [source] contain the same key and both values
  /// are `Map<String, dynamic>`, the merge recurses into that key.
  ///
  /// Merge strategy is controlled by [additive]:
  ///
  /// - `false` (default) — **source wins**: when a leaf key exists in both
  ///   maps, the [source] value overwrites the [target] value.
  /// - `true` — **target wins**: existing leaf values are preserved; only
  ///   keys missing from [target] are added from [source]. Use this mode
  ///   when merging plugin defaults into user-customised files (e.g.
  ///   translation stubs into host app translations).
  ///
  /// Neither [target] nor [source] are mutated — a fresh map is returned.
  ///
  /// ### Example
  ///
  /// ```dart
  /// final target = {'auth': {'login': 'Login', 'logout': 'Logout'}};
  /// final source = {'auth': {'login': 'Sign In', 'register': 'Sign Up'}};
  ///
  /// // Default (source wins):
  /// final result = JsonEditor.deepMerge(target, source);
  /// // {'auth': {'login': 'Sign In', 'logout': 'Logout', 'register': 'Sign Up'}}
  ///
  /// // Additive (target wins):
  /// final additive = JsonEditor.deepMerge(target, source, additive: true);
  /// // {'auth': {'login': 'Login', 'logout': 'Logout', 'register': 'Sign Up'}}
  /// ```
  ///
  /// @param target    The base map (existing data).
  /// @param source    The incoming map.
  /// @param additive  When `true`, existing leaf values in [target] are
  ///                  preserved and only missing keys are added.
  /// @return A new [Map<String, dynamic>] containing the merged result.
  static Map<String, dynamic> deepMerge(
    Map<String, dynamic> target,
    Map<String, dynamic> source, {
    bool additive = false,
  }) {
    final Map<String, dynamic> result = Map<String, dynamic>.from(target);

    for (final entry in source.entries) {
      final existing = result[entry.key];

      // Both sides are maps → recurse.
      if (existing is Map<String, dynamic> &&
          entry.value is Map<String, dynamic>) {
        result[entry.key] = deepMerge(
          existing,
          entry.value as Map<String, dynamic>,
          additive: additive,
        );
      } else if (additive && result.containsKey(entry.key)) {
        // Additive mode — preserve existing leaf value, skip overwrite.
        continue;
      } else {
        // Source wins — overwrite or add.
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  /// Merge an incoming JSON file into an existing target JSON file.
  ///
  /// If the [targetPath] file does not exist, the [sourcePath] content is
  /// written as-is. If the target already exists, a recursive deep-merge
  /// is performed.
  ///
  /// When [additive] is `true` (the default), existing leaf values in the
  /// target are preserved — only missing keys are added from the source.
  /// This is the safe default for merging plugin stubs into user-customised
  /// files (e.g. translation files).
  ///
  /// When [additive] is `false`, the source value wins on leaf conflicts
  /// (overwrite semantics).
  ///
  /// When [force] is `true`, the [sourcePath] content overwrites [targetPath]
  /// entirely — no merge is performed.
  ///
  /// ### Example
  ///
  /// ```dart
  /// // Merge plugin translations into host app (additive — preserves user values)
  /// JsonEditor.mergeJsonFile(
  ///   '/app/assets/lang/en.json',
  ///   '/stubs/en.json',
  /// );
  ///
  /// // Force-overwrite with stub content
  /// JsonEditor.mergeJsonFile(
  ///   '/app/assets/lang/en.json',
  ///   '/stubs/en.json',
  ///   force: true,
  /// );
  /// ```
  ///
  /// @param targetPath  The destination JSON file (host app's file).
  /// @param sourcePath  The incoming JSON file (stub / plugin file).
  /// @param additive    When `true` (default), existing values are preserved.
  /// @param force       When `true`, skip merge and overwrite entirely.
  ///
  /// @throws [FileSystemException] if [sourcePath] does not exist.
  /// @throws [FormatException]     if either file contains invalid JSON.
  static void mergeJsonFile(
    String targetPath,
    String sourcePath, {
    bool additive = true,
    bool force = false,
  }) {
    final sourceData = readJson(sourcePath);
    final targetFile = File(targetPath);

    // 1. Force mode or target missing → write source as-is.
    if (force || !targetFile.existsSync()) {
      writeJson(targetPath, sourceData);
      return;
    }

    // 2. Deep-merge source into existing target.
    final targetData = readJson(targetPath);
    final merged = deepMerge(targetData, sourceData, additive: additive);

    writeJson(targetPath, merged);
  }

  /// Merge an in-memory [sourceData] map into an existing JSON file.
  ///
  /// Convenience variant of [mergeJsonFile] when the source content is
  /// already loaded (e.g. from a stub string rather than a file on disk).
  ///
  /// @param targetPath  The destination JSON file.
  /// @param sourceData  The incoming map to merge.
  /// @param additive    When `true` (default), existing values are preserved.
  /// @param force       When `true`, skip merge and overwrite entirely.
  static void mergeJsonData(
    String targetPath,
    Map<String, dynamic> sourceData, {
    bool additive = true,
    bool force = false,
  }) {
    final targetFile = File(targetPath);

    // 1. Force mode or target missing → write source as-is.
    if (force || !targetFile.existsSync()) {
      writeJson(targetPath, sourceData);
      return;
    }

    // 2. Deep-merge source into existing target.
    final targetData = readJson(targetPath);
    final merged = deepMerge(targetData, sourceData, additive: additive);

    writeJson(targetPath, merged);
  }

  // -------------------------------------------------------------------------
  // Inspection
  // -------------------------------------------------------------------------

  /// Check whether [key] exists as a top-level key in the JSON file.
  ///
  /// Returns `false` (instead of throwing) when the file does not exist or
  /// cannot be parsed — making this safe to use as a precondition guard.
  ///
  /// @param path  Path to the `.json` file.
  /// @param key   Top-level key to look for.
  /// @return `true` if the key is present, `false` in all other cases.
  static bool hasKey(String path, String key) {
    try {
      final data = readJson(path);
      return data.containsKey(key);
    } catch (_) {
      return false;
    }
  }
}
