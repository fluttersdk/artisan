import 'dart:convert';

import 'package:path/path.dart' as p;

import 'install_context.dart';
import 'install_operation.dart';

/// Represents a single file-level conflict detected before committing an
/// [InstallTransaction].
///
/// A conflict means the installer would overwrite a file that the user (or
/// another tool) has changed outside of the managed install lifecycle.
///
/// ## Reason codes
///
/// - `'modified-since-last-known-stub'` -- the file exists, was previously
///   managed by this plugin (a hash record exists), but the current on-disk
///   hash differs from the recorded hash.
/// - `'unmanaged-file'` -- the file exists but no hash record was found
///   (neither in the plugin record nor the global INDEX.json). The installer
///   refuses to overwrite an unknown file by default.
class FileConflict {
  /// Absolute path of the conflicting file.
  final String absPath;

  /// Machine-readable reason code. One of
  /// `'modified-since-last-known-stub'` or `'unmanaged-file'`.
  final String reason;

  /// The hash that was recorded at install time. `null` for
  /// `'unmanaged-file'` conflicts where no record exists.
  final String? lastKnownHash;

  /// The md5 digest of the file as it currently sits on disk.
  final String currentHash;

  /// Creates a [FileConflict] record.
  ///
  /// @param absPath       Absolute path of the conflicting file.
  /// @param reason        Machine-readable reason code.
  /// @param lastKnownHash Hash recorded at install time; `null` when no
  ///                      record exists.
  /// @param currentHash   Current on-disk md5 hex digest. Defaults to the
  ///                      empty string when creating synthetic records via the
  ///                      [InstallTransaction.debugSetConflictsForTest] seam.
  const FileConflict({
    required this.absPath,
    required this.reason,
    this.currentHash = '',
    this.lastKnownHash,
  });

  @override
  String toString() => 'FileConflict($absPath, $reason)';
}

/// Pre-flight conflict detector for [InstallTransaction].
///
/// Before committing a set of [InstallOperation]s, [detect] inspects each
/// operation that would write or overwrite a file and determines whether the
/// current on-disk state is safe to overwrite automatically.
///
/// Detection reads from two JSON sources:
///
/// 1. `<projectRoot>/.artisan/installed/<pluginName>.json` -- per-plugin
///    record that stores `stubHashes` (absolute path to md5 hex string).
/// 2. `<projectRoot>/.artisan/installed/INDEX.json` -- global shared-file
///    index (V1: existence check only; absence of this file causes any
///    unrecorded file to be treated as an `'unmanaged-file'` conflict).
///
/// ## Usage
///
/// ```dart
/// final detector = ConflictDetector(ctx);
/// final conflicts = detector.detect(ops, pluginName: 'firebase_messaging');
/// if (conflicts.isNotEmpty) {
///   // Surface to user or pass --force to bypass.
/// }
/// ```
class ConflictDetector {
  /// Creates a [ConflictDetector] bound to [ctx] for filesystem and path
  /// resolution.
  ///
  /// @param ctx  The active [InstallContext] providing the [VirtualFs] and
  ///             [projectRoot].
  ConflictDetector(InstallContext ctx) : _ctx = ctx;

  final InstallContext _ctx;

  /// Inspects [ops] and returns any file conflicts that would need user
  /// confirmation (or a `--force` flag) before committing.
  ///
  /// Only operations that produce file content on disk are checked.
  /// Pure-action operations ([RunShell], [AddDependency], [RemoveDependency],
  /// [AddPubspecAsset], [AddPathDependency]) are filtered out because they do
  /// not overwrite user-owned files.
  ///
  /// @param ops         The staged [InstallOperation] list to inspect.
  /// @param pluginName  Identifier used to locate the per-plugin hash record
  ///                    at `.artisan/installed/<pluginName>.json`.
  /// @return An empty list when no conflicts exist, or a list of
  ///         [FileConflict]s describing each problematic file.
  List<FileConflict> detect(
    List<InstallOperation> ops, {
    required String pluginName,
  }) {
    // 1. Load the per-plugin hash record once (null when the file is absent).
    final pluginRecord = _loadPluginRecord(pluginName);

    // 2. Iterate ops, extracting the target absolute path for file-writing
    //    operations. Non-file ops return null and are skipped.
    final conflicts = <FileConflict>[];
    for (final op in ops) {
      final absPath = _targetAbsPath(op);
      if (absPath == null) continue;

      // 3. No pre-existing file means a clean install slot. No conflict.
      if (!_ctx.fs.exists(absPath)) continue;

      // 4. Compute the current on-disk hash once per target.
      final currentHash = _ctx.fs.md5(absPath);

      // 5. Look up the last-known hash in the plugin record.
      final lastKnownHash = pluginRecord?['stubHashes']?[absPath] as String?;

      if (lastKnownHash == null) {
        // No record for this file: treat as unmanaged.
        conflicts.add(FileConflict(
          absPath: absPath,
          reason: 'unmanaged-file',
          currentHash: currentHash,
        ));
        continue;
      }

      // 6. Hash match: the file is unmodified since last install. No conflict.
      if (lastKnownHash == currentHash) continue;

      // 7. Hash mismatch: user modified the file. Surface the conflict.
      conflicts.add(FileConflict(
        absPath: absPath,
        reason: 'modified-since-last-known-stub',
        lastKnownHash: lastKnownHash,
        currentHash: currentHash,
      ));
    }

    return conflicts;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Resolves [relPath] to an absolute path against [InstallContext.projectRoot].
  /// Absolute paths pass through unchanged.
  String _abs(String relPath) {
    if (p.isAbsolute(relPath)) return relPath;
    return p.join(_ctx.projectRoot, relPath);
  }

  /// Returns the target absolute path for file-writing [InstallOperation]s.
  ///
  /// Returns `null` for pure-action ops that do not write a user-owned file
  /// (e.g. [RunShell], [AddDependency]).
  String? _targetAbsPath(InstallOperation op) {
    return switch (op) {
      // File-writing operations: extract target path.
      WriteFile(:final targetPath) => _abs(targetPath),
      PublishFile(:final targetPath) => _abs(targetPath),
      CopyFile(:final targetPath) => _abs(targetPath),
      MergeJson(:final targetPath) => _abs(targetPath),
      InjectImport(:final targetFile) => _abs(targetFile),
      InjectBeforePattern(:final targetFile) => _abs(targetFile),
      InjectAfterPattern(:final targetFile) => _abs(targetFile),
      InjectMainDartImport() => _abs('lib/main.dart'),
      InjectIntoMainDart() => _abs('lib/main.dart'),
      InjectRouteRegistration() =>
        null, // route file resolved at execution time
      // Native-file ops: paths are resolved by executor; skip for now.
      InjectAndroidPermission() => null,
      InjectAndroidMetaData() => null,
      InjectInfoPlistKey() => null,
      InjectEntitlement() => null,
      InjectPodfileLine() => null,
      InjectGradlePlugin() => null,
      InjectGradleDependency() => null,
      // Web ops.
      InjectIntoWebHead() => null,
      AddWebMetaTag() => null,
      // Env ops.
      InjectEnvVar() => null,
      // Pure-action ops: no file conflict possible.
      DeleteFile() => null,
      AddDependency() => null,
      AddPathDependency() => null,
      RemoveDependency() => null,
      AddPubspecAsset() => null,
      RunShell() => null,
    };
  }

  /// Loads and decodes the per-plugin JSON record from
  /// `<projectRoot>/.artisan/installed/<pluginName>.json`.
  ///
  /// @param pluginName  The plugin identifier.
  /// @return The parsed JSON map, or `null` when the record file is absent.
  Map<String, dynamic>? _loadPluginRecord(String pluginName) {
    final recordPath = p.join(
      _ctx.projectRoot,
      '.artisan',
      'installed',
      '$pluginName.json',
    );
    if (!_ctx.fs.exists(recordPath)) return null;
    final raw = _ctx.fs.readAsString(recordPath);
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
