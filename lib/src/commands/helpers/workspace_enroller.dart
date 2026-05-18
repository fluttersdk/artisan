import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import '../../installer/virtual_fs.dart';

/// Detects a parent Flutter application in the directory hierarchy and
/// enrolls a plugin package into its Dart pub workspace.
///
/// Enrollment means two idempotent mutations:
/// - Parent `pubspec.yaml` gains a `workspace:` list entry for the plugin's
///   relative path.
/// - Plugin `pubspec.yaml` gains `resolution: workspace` at the top level.
///
/// Both mutations use [YamlEditor] for safe structural YAML editing — no raw
/// string concatenation.
///
/// ## Usage
///
/// ```dart
/// final enroller = WorkspaceEnroller(RealFs());
///
/// final parentPubspec = enroller.detectParentFlutterApp('/path/to/plugin');
/// if (parentPubspec != null) {
///   await enroller.enrollWorkspace(
///     parentPubspecPath: parentPubspec,
///     pluginRelativePath: 'plugins/my_plugin',
///     pluginPubspecPath: '/path/to/plugin/pubspec.yaml',
///   );
/// }
/// ```
class WorkspaceEnroller {
  /// Creates a [WorkspaceEnroller] backed by [fs].
  ///
  /// @param fs  File-system abstraction (production: [RealFs]; tests: [InMemoryFs]).
  WorkspaceEnroller(this._fs);

  final VirtualFs _fs;

  /// Walks up the directory tree from [targetDir] looking for the nearest
  /// ancestor `pubspec.yaml` that contains a top-level `flutter:` key.
  ///
  /// The search begins at the **parent** of [targetDir] (the plugin's own
  /// pubspec, if any, is deliberately skipped). It stops at the filesystem
  /// root. When multiple ancestors contain `pubspec.yaml`, only those with a
  /// `flutter:` key qualify — pure Dart packages and workspace roots are
  /// skipped.
  ///
  /// @param targetDir  Absolute path of the plugin (or any directory).
  /// @return Absolute path of the first matching `pubspec.yaml`, or `null`
  ///         when no Flutter app is found in the ancestor chain.
  String? detectParentFlutterApp(String targetDir) {
    var current = p.dirname(targetDir);

    while (true) {
      final candidate = p.join(current, 'pubspec.yaml');

      if (_fs.exists(candidate)) {
        final content = _fs.readAsString(candidate);
        // A top-level `flutter:` key starts at column 0 and is followed by a
        // colon (with optional space or newline). This regex avoids matching
        // nested `flutter:` entries that appear under `dependencies:` etc.
        if (RegExp(r'^flutter\s*:', multiLine: true).hasMatch(content)) {
          return candidate;
        }
      }

      final parent = p.dirname(current);

      // Stop when we have reached the filesystem root (dirname is idempotent).
      if (parent == current) return null;

      current = parent;
    }
  }

  /// Enrolls the plugin at [pluginRelativePath] into the Dart pub workspace
  /// declared in the parent `pubspec.yaml` at [parentPubspecPath].
  ///
  /// Both mutations are idempotent: calling this method multiple times with
  /// the same arguments produces the same file content as a single call.
  ///
  /// Steps:
  /// 1. Append [pluginRelativePath] to the `workspace:` list in the parent
  ///    pubspec, creating the list when absent.
  /// 2. Set `resolution: workspace` in the plugin pubspec when absent.
  ///
  /// @param parentPubspecPath   Absolute path to the parent app's pubspec.yaml.
  /// @param pluginRelativePath  Relative path from the parent app root to the
  ///                            plugin directory (e.g. `plugins/my_plugin`).
  /// @param pluginPubspecPath   Absolute path to the plugin's pubspec.yaml.
  Future<void> enrollWorkspace({
    required String parentPubspecPath,
    required String pluginRelativePath,
    required String pluginPubspecPath,
  }) async {
    // 1. Append the plugin path to the parent pubspec's workspace: list,
    //    creating the list when the key is absent. Skip when already present.
    _appendWorkspaceEntry(
      pubspecPath: parentPubspecPath,
      pluginRelativePath: pluginRelativePath,
    );

    // 2. Add resolution: workspace to the plugin pubspec when absent.
    _ensureResolutionWorkspace(pluginPubspecPath: pluginPubspecPath);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Appends [pluginRelativePath] to the `workspace:` list in the pubspec at
  /// [pubspecPath]. Creates the `workspace:` key with a single-item list when
  /// the key is absent. No-op when [pluginRelativePath] is already present.
  ///
  /// @param pubspecPath         Absolute path to the target pubspec.yaml.
  /// @param pluginRelativePath  Entry to append or verify.
  void _appendWorkspaceEntry({
    required String pubspecPath,
    required String pluginRelativePath,
  }) {
    final content = _fs.readAsString(pubspecPath);
    final editor = YamlEditor(content);

    // 1. Read the current workspace: value (null when key is absent).
    dynamic existing;
    try {
      existing = editor.parseAt(['workspace']).value;
    } catch (_) {
      existing = null;
    }

    if (existing == null) {
      // 2a. Key absent: create a fresh single-item list.
      editor.update(['workspace'], <String>[pluginRelativePath]);
    } else {
      if (existing is! List) {
        // workspace: exists but is not a list — refuse to clobber.
        throw StateError(
          'WorkspaceEnroller: workspace: key in $pubspecPath is not a list '
          '(found ${existing.runtimeType}); refusing to mutate.',
        );
      }

      // 2b. List present: dedup before appending.
      final alreadyPresent =
          existing.any((entry) => entry?.toString() == pluginRelativePath);
      if (alreadyPresent) return;

      final merged = <dynamic>[...existing, pluginRelativePath];
      editor.update(['workspace'], merged);
    }

    _fs.writeAsString(pubspecPath, editor.toString());
  }

  /// Sets `resolution: workspace` at the top level of the pubspec at
  /// [pluginPubspecPath]. No-op when the key already carries that value.
  ///
  /// @param pluginPubspecPath  Absolute path to the plugin's pubspec.yaml.
  void _ensureResolutionWorkspace({required String pluginPubspecPath}) {
    final content = _fs.readAsString(pluginPubspecPath);
    final editor = YamlEditor(content);

    // 1. Check existing value to stay idempotent.
    dynamic existing;
    try {
      existing = editor.parseAt(['resolution']).value;
    } catch (_) {
      existing = null;
    }

    if (existing?.toString() == 'workspace') return;

    // 2. Set resolution: workspace when absent or holding a different value.
    editor.update(['resolution'], 'workspace');

    _fs.writeAsString(pluginPubspecPath, editor.toString());
  }
}
