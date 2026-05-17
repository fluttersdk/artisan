import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../helpers/file_helper.dart';

/// File-system abstraction consumed by every operation inside the
/// `installer/` subtree.
///
/// Two concrete implementations ship in V1: [RealFs] backed by `dart:io` and
/// [InMemoryFs] backed by a [Map]. Both honour the same eight-method
/// contract so [InstallTransaction] can swap them out in tests without code
/// changes.
///
/// All paths are absolute. Implementations make no attempt to resolve
/// relatives. Use the synchronous Dart File API (matches existing helpers);
/// async variants are explicitly out of scope for V1.
///
/// ## Usage
///
/// ```dart
/// const fs = RealFs();
/// fs.writeAsString('/tmp/hello.txt', 'world');
/// final hash = fs.md5('/tmp/hello.txt');
/// ```
abstract class VirtualFs {
  /// Returns `true` when a file (not directory) exists at [absPath].
  ///
  /// @param absPath  Absolute path to test.
  /// @return `true` if the file exists, `false` otherwise.
  bool exists(String absPath);

  /// Reads the file at [absPath] and returns its UTF-8 string content.
  ///
  /// @param absPath  Absolute path of the file to read.
  /// @return The file contents decoded as UTF-8.
  /// @throws FileSystemException When the file does not exist.
  String readAsString(String absPath);

  /// Writes [content] to [absPath] (UTF-8). Auto-creates any missing parent
  /// directories. Overwrites the file when it already exists.
  ///
  /// @param absPath  Absolute target path.
  /// @param content  UTF-8 string content to write.
  void writeAsString(String absPath, String content);

  /// Deletes the file at [absPath]. Silent no-op when the file is missing
  /// (idempotent, mirrors `rm -f` semantics).
  ///
  /// @param absPath  Absolute path to delete.
  void delete(String absPath);

  /// Copies [fromAbs] to [toAbs]. Auto-creates any missing parent
  /// directories at the destination. Overwrites [toAbs] if present.
  ///
  /// @param fromAbs  Absolute source path. Must exist.
  /// @param toAbs    Absolute destination path.
  /// @throws FileSystemException When [fromAbs] is missing.
  void copy(String fromAbs, String toAbs);

  /// Atomic POSIX-style rename of [fromAbs] to [toAbs]. Overwrites [toAbs]
  /// when present (matches `rename(2)` semantics used by
  /// [InstallTransaction.commit]'s `.tmp` swap).
  ///
  /// @param fromAbs  Absolute source path. Must exist.
  /// @param toAbs    Absolute destination path.
  /// @throws FileSystemException When [fromAbs] is missing.
  void rename(String fromAbs, String toAbs);

  /// Returns the immediate filenames inside [absDir]. Non-recursive.
  /// Subdirectory names and nested files are excluded.
  ///
  /// @param absDir  Absolute directory path.
  /// @return Unordered list of filenames (no path component).
  List<String> listSync(String absDir);

  /// Returns the lowercase hex md5 digest of the file content at [absPath].
  /// Computed on demand each call (no caching) so the result reflects the
  /// current on-disk bytes.
  ///
  /// @param absPath  Absolute path of the file to hash.
  /// @return 32-character lowercase hex digest.
  /// @throws FileSystemException When the file does not exist.
  String md5(String absPath);
}

/// Production [VirtualFs] backed by `dart:io`. Every method delegates to the
/// existing [FileHelper] utilities so the installer reuses the same atomic
/// write + parent-directory semantics applied throughout the framework.
///
/// ## Usage
///
/// ```dart
/// const fs = RealFs();
/// fs.writeAsString('/Users/anilcan/Code/app/lib/config/x.dart', '...');
/// ```
class RealFs implements VirtualFs {
  /// Creates a stateless [RealFs]. The class holds no instance fields so the
  /// constructor is `const` and consumers can share a single literal.
  const RealFs();

  @override
  bool exists(String absPath) => FileHelper.fileExists(absPath);

  @override
  String readAsString(String absPath) => FileHelper.readFile(absPath);

  @override
  void writeAsString(String absPath, String content) {
    FileHelper.writeFile(absPath, content);
  }

  @override
  void delete(String absPath) {
    FileHelper.deleteFile(absPath);
  }

  @override
  void copy(String fromAbs, String toAbs) {
    // 1. Reject early when the source is missing so the error is identical to
    //    InMemoryFs's `! ` failure mode and matches the documented contract.
    if (!File(fromAbs).existsSync()) {
      throw FileSystemException('Source file not found', fromAbs);
    }
    // 2. Ensure the destination's parent exists; dart:io's File.copySync
    //    refuses to create missing directories.
    FileHelper.ensureDirectoryExists(File(toAbs).parent.path);
    FileHelper.copyFile(fromAbs, toAbs);
  }

  @override
  void rename(String fromAbs, String toAbs) {
    final source = File(fromAbs);
    if (!source.existsSync()) {
      throw FileSystemException('Source file not found', fromAbs);
    }
    source.renameSync(toAbs);
  }

  @override
  List<String> listSync(String absDir) {
    final dir = Directory(absDir);
    if (!dir.existsSync()) return const <String>[];
    return dir
        .listSync(followLinks: false)
        .whereType<File>()
        .map((entity) => p.basename(entity.path))
        .toList(growable: false);
  }

  @override
  String md5(String absPath) {
    final content = FileHelper.readFile(absPath);
    return crypto.md5.convert(utf8.encode(content)).toString();
  }
}

/// In-memory [VirtualFs] backed by a [Map] (`absPath -> UTF-8 content`).
///
/// Used exclusively in tests via [InstallContext.test] so commands can be
/// driven through their full lifecycle without touching the host filesystem.
/// State persists across calls within a single instance and is fully isolated
/// between instances (no shared static map).
///
/// ## Usage
///
/// ```dart
/// final fs = InMemoryFs();
/// fs.writeAsString('/virtual/pubspec.yaml', 'name: app\n');
/// expect(fs.readAsString('/virtual/pubspec.yaml'), contains('name'));
/// ```
class InMemoryFs implements VirtualFs {
  /// Creates an empty in-memory file store.
  InMemoryFs();

  final Map<String, String> _files = <String, String>{};

  /// Read-only view of the underlying storage map. Exposed for tests that
  /// need to assert on raw state without going through the [VirtualFs]
  /// surface.
  Map<String, String> get snapshot => Map.unmodifiable(_files);

  @override
  bool exists(String absPath) => _files.containsKey(absPath);

  @override
  String readAsString(String absPath) {
    final content = _files[absPath];
    if (content == null) {
      throw FileSystemException('File not found', absPath);
    }
    return content;
  }

  @override
  void writeAsString(String absPath, String content) {
    _files[absPath] = content;
  }

  @override
  void delete(String absPath) {
    _files.remove(absPath);
  }

  @override
  void copy(String fromAbs, String toAbs) {
    final content = _files[fromAbs];
    if (content == null) {
      throw FileSystemException('Source file not found', fromAbs);
    }
    _files[toAbs] = content;
  }

  @override
  void rename(String fromAbs, String toAbs) {
    final content = _files.remove(fromAbs);
    if (content == null) {
      throw FileSystemException('Source file not found', fromAbs);
    }
    _files[toAbs] = content;
  }

  @override
  List<String> listSync(String absDir) {
    // Normalise the directory to end with `/` so the prefix check excludes
    // sibling paths that merely start with the directory name.
    final prefix = absDir.endsWith('/') ? absDir : '$absDir/';
    final results = <String>[];
    for (final key in _files.keys) {
      if (!key.startsWith(prefix)) continue;
      final remainder = key.substring(prefix.length);
      // Non-recursive: skip any entry that lives in a subdirectory.
      if (remainder.contains('/')) continue;
      results.add(remainder);
    }
    return results;
  }

  @override
  String md5(String absPath) {
    final content = _files[absPath];
    if (content == null) {
      throw FileSystemException('File not found', absPath);
    }
    return crypto.md5.convert(utf8.encode(content)).toString();
  }
}
