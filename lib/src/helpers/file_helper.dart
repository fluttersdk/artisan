import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// File system operation helpers for CLI commands.
///
/// Provides utilities for file/directory operations, YAML reading/writing,
/// and project root detection.
///
/// ## Usage
///
/// ```dart
/// // Check if file exists
/// if (FileHelper.fileExists('/path/to/file.txt')) {
///   final content = FileHelper.readFile('/path/to/file.txt');
/// }
///
/// // Find project root
/// final projectRoot = FileHelper.findProjectRoot();
///
/// // Read YAML file
/// final config = FileHelper.readYamlFile('config.yaml');
/// ```
class FileHelper {
  /// Check if a file exists at the given path.
  static bool fileExists(String filePath) {
    return File(filePath).existsSync();
  }

  /// Check if a directory exists at the given path.
  static bool directoryExists(String dirPath) {
    return Directory(dirPath).existsSync();
  }

  /// Read the contents of a file as a string.
  ///
  /// Throws [FileSystemException] if the file does not exist.
  static String readFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    return file.readAsStringSync();
  }

  /// Write content to a file.
  ///
  /// Creates the file if it does not exist, overwrites if it does.
  /// Creates parent directories if they do not exist.
  static void writeFile(String filePath, String content) {
    final file = File(filePath);
    // Ensure parent directory exists
    if (file.parent.existsSync() == false) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync(content);
  }

  /// Copy a file from source to destination.
  ///
  /// Throws [FileSystemException] if source does not exist.
  static void copyFile(String source, String destination) {
    final sourceFile = File(source);
    if (!sourceFile.existsSync()) {
      throw FileSystemException('Source file not found', source);
    }
    sourceFile.copySync(destination);
  }

  /// Delete a file at the given path.
  ///
  /// Does nothing if the file does not exist (safe delete).
  static void deleteFile(String filePath) {
    final file = File(filePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  /// Ensure a directory exists at the given path.
  ///
  /// Creates the directory (and any parent directories) if it does not exist.
  /// Does nothing if the directory already exists.
  static void ensureDirectoryExists(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// Read a YAML file and parse it to a Map.
  ///
  /// Throws [FileSystemException] if file not found.
  /// Throws [Exception] if YAML is invalid.
  static Map<String, dynamic> readYamlFile(String filePath) {
    final content = readFile(filePath);
    try {
      final yaml = loadYaml(content);
      if (yaml is Map) {
        return Map<String, dynamic>.from(yaml);
      }
      throw Exception('YAML root must be a Map');
    } catch (e) {
      throw Exception('Failed to parse YAML file $filePath: $e');
    }
  }

  /// Write a Map to a YAML file.
  ///
  /// Converts the Map to YAML format and writes to file.
  /// Creates parent directories if needed.
  static void writeYamlFile(String filePath, Map<String, dynamic> data) {
    final buffer = StringBuffer();
    _writeYamlMap(buffer, data, 0);
    writeFile(filePath, buffer.toString());
  }

  /// Helper to recursively write YAML map with proper indentation.
  static void _writeYamlMap(StringBuffer buffer, dynamic value, int indent) {
    if (value is Map) {
      value.forEach((key, val) {
        buffer.write('  ' * indent);
        buffer.write('$key:');
        if (val is Map || val is List) {
          buffer.writeln();
          _writeYamlMap(buffer, val, indent + 1);
        } else {
          buffer.write(' ');
          _writeYamlValue(buffer, val);
          buffer.writeln();
        }
      });
    } else if (value is List) {
      for (final item in value) {
        buffer.write('  ' * indent);
        buffer.write('- ');
        if (item is Map || item is List) {
          buffer.writeln();
          _writeYamlMap(buffer, item, indent + 1);
        } else {
          _writeYamlValue(buffer, item);
          buffer.writeln();
        }
      }
    }
  }

  /// Helper to write YAML scalar values with proper escaping.
  static void _writeYamlValue(StringBuffer buffer, dynamic value) {
    if (value == null) {
      buffer.write('null');
    } else if (value is String) {
      // Quote strings that contain special characters
      if (value.contains(':') ||
          value.contains('#') ||
          value.contains('[') ||
          value.contains(']') ||
          value.contains('{') ||
          value.contains('}') ||
          value.contains('\n')) {
        buffer.write("'${value.replaceAll("'", "''")}'");
      } else {
        buffer.write(value);
      }
    } else {
      buffer.write(value.toString());
    }
  }

  /// Find the project root directory by traversing up to find pubspec.yaml.
  ///
  /// Starts from [startFrom] (defaults to current directory) and traverses
  /// up the directory tree until it finds a directory containing pubspec.yaml.
  ///
  /// Throws [Exception] if no pubspec.yaml is found.
  static String findProjectRoot({String? startFrom}) {
    var current = Directory(startFrom ?? Directory.current.path);

    // Traverse up the directory tree
    while (true) {
      final pubspecPath = path.join(current.path, 'pubspec.yaml');
      if (File(pubspecPath).existsSync()) {
        return current.path;
      }

      // Check if we've reached the root
      final parent = current.parent;
      if (parent.path == current.path) {
        throw Exception(
          'Could not find pubspec.yaml. Not in a Flutter/Dart project?',
        );
      }

      current = parent;
    }
  }

  /// Compute the relative path from [from] to [to].
  ///
  /// Both paths can be absolute or relative.
  static String getRelativePath(String from, String to) {
    return path.relative(to, from: from);
  }
}
