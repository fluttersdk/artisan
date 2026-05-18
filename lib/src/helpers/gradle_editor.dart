import 'dart:io';

/// Supported Gradle build script syntaxes.
enum _BuildGradleSyntax {
  /// Kotlin DSL, file extension `.kts`.
  kts,

  /// Groovy DSL, file extension `.gradle`.
  groovy,
}

/// Android `build.gradle` / `build.gradle.kts` file manipulation helper.
///
/// Provides pure string/regex-based utilities for inserting plugins,
/// dependencies, and SDK version pins into Android Gradle build scripts.
/// Both Kotlin DSL (`.kts`) and Groovy (`.gradle`) syntaxes are supported.
/// The correct syntax is auto-detected from the file extension.
///
/// All mutation methods are **idempotent**: calling them a second time with
/// the same arguments leaves the file unchanged.
///
/// ## Usage
///
/// ```dart
/// // Add a plugin (KTS)
/// GradleEditor.addPlugin(
///   'android/app/build.gradle.kts',
///   'com.google.gms.google-services',
///   version: '4.4.0',
/// );
///
/// // Add a dependency (Groovy)
/// GradleEditor.addDependency(
///   'android/app/build.gradle',
///   'implementation',
///   'com.google.firebase:firebase-analytics:21.5.0',
/// );
///
/// // Update the minimum SDK version
/// GradleEditor.setMinSdkVersion('android/app/build.gradle.kts', 24);
///
/// // Add a classpath to the root build script
/// GradleEditor.addClasspath(
///   'android/build.gradle.kts',
///   'com.google.gms:google-services:4.4.0',
/// );
/// ```
class GradleEditor {
  GradleEditor._();

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Insert a plugin declaration inside the `plugins { ... }` block.
  ///
  /// For Kotlin DSL the line takes the form:
  /// ```
  ///   id("<pluginId>") version "<version>"
  /// ```
  /// For Groovy the line takes the form:
  /// ```
  ///   id '<pluginId>' version '<version>'
  /// ```
  /// When [version] is omitted the `version "..."` clause is not appended.
  ///
  /// The operation is idempotent: if [pluginId] is already present anywhere
  /// in the file the method returns without making changes.
  ///
  /// @param gradlePath  Absolute or relative path to the build script.
  /// @param pluginId    The Gradle plugin ID, e.g. `com.google.gms.google-services`.
  /// @param version     Optional version string. Omit for plugins managed by
  ///                    a version catalog or the root `plugins {}` block.
  ///
  /// @throws [FileSystemException]  if the file does not exist.
  /// @throws [StateError]           if no `plugins {` block is found.
  static void addPlugin(
    String gradlePath,
    String pluginId, {
    String? version,
  }) {
    final syntax = _detectSyntax(gradlePath);
    final content = _read(gradlePath);

    // 1. Idempotency, bail when the plugin ID is already referenced.
    if (content.contains(pluginId)) {
      return;
    }

    // 2. Build the new plugin line for the detected syntax.
    final line = switch (syntax) {
      _BuildGradleSyntax.kts => version != null
          ? '    id("$pluginId") version "$version"'
          : '    id("$pluginId")',
      _BuildGradleSyntax.groovy => version != null
          ? "    id '$pluginId' version '$version'"
          : "    id '$pluginId'",
    };

    // 3. Insert the line inside the first plugins { ... } block.
    _insertIntoBlock(gradlePath, content, 'plugins', line);
  }

  /// Insert a dependency declaration inside the `dependencies { ... }` block.
  ///
  /// For Kotlin DSL the line takes the form:
  /// ```
  ///   <scope>("<notation>")
  /// ```
  /// For Groovy the line takes the form:
  /// ```
  ///   <scope> '<notation>'
  /// ```
  ///
  /// Supported scopes: `implementation`, `api`, `classpath`,
  /// `testImplementation`.
  ///
  /// The operation is idempotent: if [notation] is already present anywhere
  /// in the file the method returns without making changes.
  ///
  /// @param gradlePath  Absolute or relative path to the build script.
  /// @param scope       Dependency configuration name.
  /// @param notation    Maven coordinate, e.g. `androidx.core:core-ktx:1.10.0`.
  ///
  /// @throws [FileSystemException]  if the file does not exist.
  /// @throws [StateError]           if no `dependencies {` block is found.
  static void addDependency(
    String gradlePath,
    String scope,
    String notation,
  ) {
    final syntax = _detectSyntax(gradlePath);
    final content = _read(gradlePath);

    // 1. Idempotency, bail when the notation is already referenced.
    if (content.contains(notation)) {
      return;
    }

    // 2. Build the new dependency line for the detected syntax.
    final line = switch (syntax) {
      _BuildGradleSyntax.kts => '    $scope("$notation")',
      _BuildGradleSyntax.groovy => "    $scope '$notation'",
    };

    // 3. Insert the line inside the first dependencies { ... } block.
    _insertIntoBlock(gradlePath, content, 'dependencies', line);
  }

  /// Update (or insert) the minimum SDK version inside `defaultConfig { ... }`.
  ///
  /// For Kotlin DSL the directive is `minSdk = <version>`.
  /// For Groovy the directive is `minSdkVersion <version>`.
  ///
  /// When the directive already exists it is replaced in-place; otherwise it
  /// is inserted as the first line inside `defaultConfig { ... }`.
  ///
  /// @param appGradlePath  Path to the app-level build script.
  /// @param version        The minimum SDK integer, e.g. `24`.
  ///
  /// @throws [FileSystemException]  if the file does not exist.
  /// @throws [StateError]           if no `defaultConfig {` block is found.
  static void setMinSdkVersion(String appGradlePath, int version) {
    final syntax = _detectSyntax(appGradlePath);
    var content = _read(appGradlePath);

    // 1. Attempt in-place replacement of an existing directive.
    final replaced = switch (syntax) {
      _BuildGradleSyntax.kts => _replaceInLine(
          content,
          RegExp(r'(\s*)minSdk\s*=\s*\d+'),
          (indent) => '${indent}minSdk = $version',
        ),
      _BuildGradleSyntax.groovy => _replaceInLine(
          content,
          RegExp(r'(\s*)minSdkVersion\s+\d+'),
          (indent) => '${indent}minSdkVersion $version',
        ),
    };

    if (replaced != null) {
      File(appGradlePath).writeAsStringSync(replaced);
      return;
    }

    // 2. Directive absent, insert as first line in defaultConfig { ... }.
    final newLine = switch (syntax) {
      _BuildGradleSyntax.kts => '    minSdk = $version',
      _BuildGradleSyntax.groovy => '    minSdkVersion $version',
    };

    _insertIntoBlock(appGradlePath, content, 'defaultConfig', newLine);
  }

  /// Insert a `classpath` entry inside the `dependencies { ... }` block.
  ///
  /// This is a convenience wrapper around [addDependency] with scope
  /// `classpath`. Typically used in a root-level build script to add a
  /// build-tool classpath, e.g. the Google Services Gradle plugin.
  ///
  /// @param rootGradlePath  Path to the root-level build script.
  /// @param notation        Maven coordinate for the classpath artifact.
  ///
  /// @throws [FileSystemException]  if the file does not exist.
  /// @throws [StateError]           if no `dependencies {` block is found.
  static void addClasspath(String rootGradlePath, String notation) {
    addDependency(rootGradlePath, 'classpath', notation);
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Detect the build script syntax from the file extension.
  ///
  /// @param path  Path to the build script.
  /// @return [_BuildGradleSyntax.kts] for `.kts` files,
  ///         [_BuildGradleSyntax.groovy] for all other `.gradle` files.
  static _BuildGradleSyntax _detectSyntax(String path) {
    return path.endsWith('.kts')
        ? _BuildGradleSyntax.kts
        : _BuildGradleSyntax.groovy;
  }

  /// Read the build script at [path], throwing [FileSystemException] when
  /// the file does not exist.
  ///
  /// @param path  Absolute or relative path to the build script.
  /// @return The raw file content as a [String].
  static String _read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Gradle build file not found', path);
    }
    return file.readAsStringSync();
  }

  /// Insert [newLine] as the first entry inside the named [block] in
  /// [content], then write the result back to [path].
  ///
  /// The method locates the opening brace of the block using a simple regex
  /// (`<block>\s*\{`) and inserts [newLine] immediately after it.
  ///
  /// @param path     Destination file path.
  /// @param content  Current raw file content.
  /// @param block    Block keyword without braces, e.g. `plugins`.
  /// @param newLine  The fully indented line to insert.
  ///
  /// @throws [StateError]  if the block is not found in [content].
  static void _insertIntoBlock(
    String path,
    String content,
    String block,
    String newLine,
  ) {
    // Matches "plugins {" or "dependencies {" with optional spaces, possibly
    // preceded by other content on the same line (e.g. "buildscript {").
    final blockPattern = RegExp('$block\\s*\\{');
    final match = blockPattern.firstMatch(content);

    if (match == null) {
      throw StateError(
        'Cannot find "$block {" block in Gradle file: $path',
      );
    }

    // Insert newLine immediately after the opening brace.
    final insertAt = match.end;
    final updated =
        '${content.substring(0, insertAt)}\n$newLine${content.substring(insertAt)}';

    File(path).writeAsStringSync(updated);
  }

  /// Attempt to replace the first line matching [pattern] in [content].
  ///
  /// [builder] receives the leading whitespace captured by group 1 of [pattern]
  /// and returns the replacement line (including that whitespace).
  ///
  /// @param content  The source text to search.
  /// @param pattern  A [RegExp] whose group 1 captures the leading whitespace.
  /// @param builder  Function from captured indent to the replacement line.
  /// @return The updated content string, or `null` when [pattern] has no match.
  static String? _replaceInLine(
    String content,
    RegExp pattern,
    String Function(String indent) builder,
  ) {
    final match = pattern.firstMatch(content);
    if (match == null) return null;

    final indent = match.group(1) ?? '';
    return content.replaceFirst(match.group(0)!, builder(indent));
  }
}
