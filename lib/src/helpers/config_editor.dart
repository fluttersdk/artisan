import 'package:yaml_edit/yaml_edit.dart';
import 'file_helper.dart';

/// Configuration file editing utilities for CLI commands.
///
/// Provides safe YAML editing for pubspec.yaml, code injection into Dart files,
/// and config file creation.
///
/// ## Usage
///
/// ```dart
/// // Add dependency
/// ConfigEditor.addDependencyToPubspec(
///   pubspecPath: 'pubspec.yaml',
///   name: 'http',
///   version: '^1.0.0',
/// );
///
/// // Add import to Dart file
/// ConfigEditor.addImportToFile(
///   filePath: 'lib/main.dart',
///   importStatement: "import 'package:http/http.dart';",
/// );
/// ```
class ConfigEditor {
  /// Add or update a dependency in pubspec.yaml.
  ///
  /// If the dependency already exists, it will be updated to the new version.
  /// Creates the dependencies section if it doesn't exist.
  static void addDependencyToPubspec({
    required String pubspecPath,
    required String name,
    required String version,
  }) {
    final content = FileHelper.readFile(pubspecPath);
    final editor = YamlEditor(content);

    // Ensure dependencies section exists
    if (editor.parseAt(['dependencies']).value == null) {
      editor.update(['dependencies'], {});
    }

    // Add or update the dependency
    editor.update(['dependencies', name], version);

    // Write the updated content
    FileHelper.writeFile(pubspecPath, editor.toString());
  }

  /// Add or update a path-based dependency in pubspec.yaml.
  ///
  /// Use this for local plugin dependencies that reference a path rather than a version.
  /// Creates the dependencies section if it doesn't exist.
  ///
  /// Example:
  /// ```yaml
  /// dependencies:
  ///   my_plugin:
  ///     path: ./plugins/my_plugin
  /// ```
  static void addPathDependencyToPubspec({
    required String pubspecPath,
    required String name,
    required String path,
  }) {
    final content = FileHelper.readFile(pubspecPath);
    final editor = YamlEditor(content);

    // Ensure dependencies section exists
    try {
      if (editor.parseAt(['dependencies']).value == null) {
        editor.update(['dependencies'], {});
      }
    } catch (e) {
      editor.update(['dependencies'], {});
    }

    // Add or update the dependency with path
    editor.update(['dependencies', name], {'path': path});

    // Write the updated content
    FileHelper.writeFile(pubspecPath, editor.toString());
  }

  /// Remove a dependency from pubspec.yaml.
  ///
  /// Does nothing if the dependency doesn't exist.
  static void removeDependencyFromPubspec({
    required String pubspecPath,
    required String name,
  }) {
    final content = FileHelper.readFile(pubspecPath);
    final editor = YamlEditor(content);

    // Check if dependencies section exists first
    try {
      final deps = editor.parseAt(['dependencies']).value;
      if (deps != null && deps is Map && deps.containsKey(name)) {
        editor.remove(['dependencies', name]);
        FileHelper.writeFile(pubspecPath, editor.toString());
      }
    } catch (e) {
      // Dependencies section doesn't exist, nothing to remove
      return;
    }
  }

  /// Update a nested value in pubspec.yaml.
  ///
  /// The [keyPath] is a list of keys to traverse, e.g., ['environment', 'sdk'].
  /// Creates missing keys if needed.
  static void updatePubspecValue({
    required String pubspecPath,
    required List<String> keyPath,
    required dynamic value,
  }) {
    final content = FileHelper.readFile(pubspecPath);
    final editor = YamlEditor(content);

    // Build up the path, creating missing sections
    for (var i = 0; i < keyPath.length - 1; i++) {
      final currentPath = keyPath.sublist(0, i + 1);
      try {
        if (editor.parseAt(currentPath).value == null) {
          editor.update(currentPath, {});
        }
      } catch (e) {
        // Path doesn't exist, create it
        editor.update(currentPath, {});
      }
    }

    // Update the final value
    editor.update(keyPath, value);

    // Write the updated content
    FileHelper.writeFile(pubspecPath, editor.toString());
  }

  /// Add an import statement to a Dart file if not already present.
  ///
  /// The import is added at the top of the file, after any existing imports.
  /// Automatically handles adding semicolon if missing.
  static void addImportToFile({
    required String filePath,
    required String importStatement,
  }) {
    var content = FileHelper.readFile(filePath);

    // Ensure import has semicolon
    var statement = importStatement.trim();
    if (!statement.endsWith(';')) {
      statement += ';';
    }

    // Check if import already exists
    if (content.contains(statement)) {
      return; // Already present, nothing to do
    }

    // Find the position to insert (after last import or at start)
    final lines = content.split('\n');
    var insertIndex = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('import ')) {
        insertIndex = i + 1;
      } else if (line.isNotEmpty && !line.startsWith('//') && insertIndex > 0) {
        // Found first non-import, non-comment line after imports
        break;
      }
    }

    // Insert the import
    lines.insert(insertIndex, statement);
    FileHelper.writeFile(filePath, lines.join('\n'));
  }

  /// Insert code before the first occurrence of a pattern in a file.
  ///
  /// Does nothing if the pattern is not found.
  static void insertCodeBeforePattern({
    required String filePath,
    required Pattern pattern,
    required String code,
  }) {
    final content = FileHelper.readFile(filePath);
    final RegExp regex =
        pattern is RegExp ? pattern : RegExp(RegExp.escape(pattern.toString()));
    final match = regex.firstMatch(content);

    if (match != null) {
      final updatedContent = content.substring(0, match.start) +
          code +
          content.substring(match.start);
      FileHelper.writeFile(filePath, updatedContent);
    }
  }

  /// Insert code after the first occurrence of a pattern in a file.
  ///
  /// Does nothing if the pattern is not found.
  static void insertCodeAfterPattern({
    required String filePath,
    required Pattern pattern,
    required String code,
  }) {
    final content = FileHelper.readFile(filePath);
    final RegExp regex =
        pattern is RegExp ? pattern : RegExp(RegExp.escape(pattern.toString()));
    final match = regex.firstMatch(content);

    if (match != null) {
      final updatedContent =
          content.substring(0, match.end) + code + content.substring(match.end);
      FileHelper.writeFile(filePath, updatedContent);
    }
  }

  /// Create a config file with the given content.
  ///
  /// Creates parent directories if they don't exist.
  /// Overwrites the file if it already exists.
  static void createConfigFile({
    required String path,
    required String content,
  }) {
    FileHelper.writeFile(path, content);
  }
}
