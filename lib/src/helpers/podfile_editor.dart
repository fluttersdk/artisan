import 'dart:io';

/// iOS and macOS Podfile manipulation helper for CLI install commands.
///
/// Provides pure regex-based utilities for reading and modifying Ruby Podfiles
/// without requiring a Dart Ruby AST parser (none exists; regex is the industry
/// standard approach, following FlutterFire CLI's own Gradle-file strategy).
/// All mutation methods are idempotent unless the task spec states otherwise.
///
/// Supported DSL constructs:
/// - `platform :ios, '<version>'` and `platform :osx, '<version>'`
/// - `target '<name>' do ... end` blocks
/// - `post_install do |installer| ... end` blocks
///
/// ## Usage
///
/// ```dart
/// // Bump the minimum iOS deployment target.
/// PodfileEditor.setPlatformVersion(
///   'ios/Podfile',
///   'ios',
///   '13.0',
/// );
///
/// // Inject a build-settings hook into post_install.
/// PodfileEditor.addPostInstallHook(
///   'ios/Podfile',
///   "  installer.pods_project.targets.each { |t| ... }",
/// );
///
/// // Add a CocoaPod dependency to the Runner target.
/// PodfileEditor.addPodLine(
///   'ios/Podfile',
///   'Runner',
///   "pod 'Firebase/Core', '~> 10.0'",
/// );
///
/// // Check whether a pod is already declared.
/// final present = PodfileEditor.hasPod('ios/Podfile', 'Firebase/Core');
/// ```
class PodfileEditor {
  PodfileEditor._();

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Read [podfilePath] and return its contents.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static String _read(String podfilePath) {
    final file = File(podfilePath);
    if (!file.existsSync()) {
      throw FileSystemException('Podfile not found', podfilePath);
    }
    return file.readAsStringSync();
  }

  /// Overwrite [podfilePath] with [content].
  static void _write(String podfilePath, String content) {
    File(podfilePath).writeAsStringSync(content);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Update or insert the `platform :<token>, '<version>'` line in a Podfile.
  ///
  /// For iOS targets pass `platform = 'ios'`; for macOS pass `platform = 'macos'`
  /// (the method maps `'macos'` to the CocoaPods `:osx` token automatically).
  /// The operation is idempotent: calling it twice with the same version is a
  /// no-op.
  ///
  /// When no matching `platform :*` line exists the declaration is prepended to
  /// the file so it appears before the first `target` block, which matches the
  /// canonical Flutter Podfile layout.
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param platform     Either `'ios'` or `'macos'`.
  /// @param version      CocoaPods deployment target string, e.g. `'13.0'`.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [ArgumentError]       if [platform] is not `'ios'` or `'macos'`.
  static void setPlatformVersion(
    String podfilePath,
    String platform,
    String version,
  ) {
    // 1. Resolve the CocoaPods DSL token for the requested platform.
    final String token;
    if (platform == 'ios') {
      token = 'ios';
    } else if (platform == 'macos') {
      token = 'osx';
    } else {
      throw ArgumentError.value(
        platform,
        'platform',
        "Must be 'ios' or 'macos'.",
      );
    }

    var content = _read(podfilePath);

    // 2. Replace an existing `platform :<token>, '...'` line with the new one.
    final existingLine = RegExp("platform :$token, '[^']*'");
    if (existingLine.hasMatch(content)) {
      content = content.replaceFirst(
        existingLine,
        "platform :$token, '$version'",
      );
      _write(podfilePath, content);
      return;
    }

    // 3. No platform line found, prepend the declaration so it precedes all
    //    target blocks (canonical Flutter Podfile layout).
    _write(podfilePath, "platform :$token, '$version'\n\n$content");
  }

  /// Insert [hookContent] inside the `post_install do |installer| ... end`
  /// block of a Podfile.
  ///
  /// If the block does not exist it is created at the end of the file. The
  /// operation is idempotent: if [hookContent] is already present anywhere in
  /// the file it will not be inserted again.
  ///
  /// The [hookContent] string is inserted as-is immediately before the `end`
  /// that closes the post_install block. Callers are responsible for providing
  /// correct indentation (two-space indent is standard for iOS Podfiles).
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param hookContent  One or more Ruby statement lines to inject.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static void addPostInstallHook(String podfilePath, String hookContent) {
    var content = _read(podfilePath);

    // 1. Idempotency, skip when hookContent already appears in the file.
    if (content.contains(hookContent)) {
      return;
    }

    // 2. Locate the post_install block and inject before its closing `end`.
    //    The regex matches `post_install do |installer|` followed by any body
    //    and the trailing `end`, capturing everything so we can reconstruct.
    final blockPattern = RegExp(
      r'(post_install do \|installer\|)(.*?)(^end)',
      dotAll: true,
      multiLine: true,
    );

    final match = blockPattern.firstMatch(content);
    if (match != null) {
      // Insert the hook line before the closing `end`.
      final open = match.group(1)!;
      final body = match.group(2)!;
      final close = match.group(3)!;
      content = content.replaceFirst(
        match.group(0)!,
        '$open$body$hookContent\n$close',
      );
      _write(podfilePath, content);
      return;
    }

    // 3. No post_install block exists, append a new one at the end of file.
    final block = '\npost_install do |installer|\n$hookContent\nend\n';
    _write(podfilePath, '${content.trimRight()}\n$block');
  }

  /// Insert [podLine] inside the `target '<targetName>' do ... end` block.
  ///
  /// [podLine] should be a fully-formed CocoaPods pod declaration, e.g.
  /// `pod 'Firebase/Core', '~> 10.0'`. The operation is idempotent: if
  /// [podLine] already appears anywhere in the file it will not be inserted.
  ///
  /// The line is inserted immediately before the `end` that closes the target
  /// block and indented with two spaces, matching Flutter's generated Podfile
  /// style.
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param targetName   CocoaPods target name, typically `'Runner'`.
  /// @param podLine      Full `pod '...'` declaration line.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if no target block matching [targetName]
  ///                               is found in the file.
  static void addPodLine(
    String podfilePath,
    String targetName,
    String podLine,
  ) {
    var content = _read(podfilePath);

    // 1. Idempotency, skip when podLine already appears in the file.
    if (content.contains(podLine)) {
      return;
    }

    // 2. Locate the target block for [targetName].
    //    The regex matches `target '<name>' do` … closing `end` non-greedily.
    final blockPattern = RegExp(
      "(target '$targetName' do)(.*?)(^end)",
      dotAll: true,
      multiLine: true,
    );

    final match = blockPattern.firstMatch(content);
    if (match == null) {
      throw StateError(
        "Cannot find target '$targetName' block in Podfile: $podfilePath",
      );
    }

    // 3. Insert the pod line before the block's closing `end`.
    final open = match.group(1)!;
    final body = match.group(2)!;
    final close = match.group(3)!;
    content = content.replaceFirst(
      match.group(0)!,
      '$open$body  $podLine\n$close',
    );

    _write(podfilePath, content);
  }

  /// Return `true` if `pod '<podName>'` is declared anywhere in the Podfile.
  ///
  /// This is a simple substring search, not a structural query. It matches
  /// any line that contains `pod '<podName>'`, regardless of indentation,
  /// version constraint, or surrounding whitespace.
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param podName      The CocoaPods pod name to search for, e.g.
  ///                     `'Firebase/Core'`.
  /// @return `true` if found, `false` otherwise (including when the file
  ///         does not exist).
  static bool hasPod(String podfilePath, String podName) {
    final file = File(podfilePath);
    if (!file.existsSync()) {
      return false;
    }
    return file.readAsStringSync().contains("pod '$podName'");
  }
}
