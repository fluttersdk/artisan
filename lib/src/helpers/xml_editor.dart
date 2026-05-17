import 'dart:io';

/// XML and Plist file manipulation helper for CLI commands.
///
/// Provides pure string/regex-based utilities for reading and modifying
/// XML files (Android manifests, iOS plist files) without external parser
/// packages. All mutation methods are idempotent unless the task spec
/// states otherwise.
///
/// ## Usage
///
/// ```dart
/// // Read raw XML content
/// final content = XmlEditor.read('/path/to/AndroidManifest.xml');
///
/// // Add an Android permission (idempotent)
/// XmlEditor.addAndroidPermission(
///   '/path/to/AndroidManifest.xml',
///   'android.permission.POST_NOTIFICATIONS',
/// );
///
/// // Read Info.plist key-value pairs
/// final info = XmlEditor.readPlist('/path/to/Info.plist');
/// print(info['CFBundleName']); // MyApp
/// ```
class XmlEditor {
  XmlEditor._();

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Read the raw XML content from [path].
  ///
  /// @param path  Absolute or relative path to the XML file.
  /// @return The file content as a [String].
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('XML file not found', path);
    }
    return file.readAsStringSync();
  }

  // -------------------------------------------------------------------------
  // Inspection
  // -------------------------------------------------------------------------

  /// Check whether [pattern] is present anywhere inside the XML file.
  ///
  /// This is a simple [String.contains] search — not a structural query.
  ///
  /// @param path     Path to the XML file.
  /// @param pattern  Literal string to search for.
  /// @return `true` if the pattern was found, `false` otherwise.
  static bool hasElement(String path, String pattern) {
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    return file.readAsStringSync().contains(pattern);
  }

  // -------------------------------------------------------------------------
  // Generic insertion
  // -------------------------------------------------------------------------

  /// Insert [element] directly before [parentXpath] in the XML file.
  ///
  /// [parentXpath] is treated as a literal closing tag string, e.g.
  /// `</manifest>`. The method is idempotent: if [element] already appears
  /// in the file it will not be inserted again.
  ///
  /// @param path         Path to the XML file.
  /// @param parentXpath  Literal closing tag string used as the anchor.
  /// @param element      XML element string to insert.
  ///
  /// @throws [StateError] if [parentXpath] is not found in the file.
  static void addElement(
    String path,
    String parentXpath,
    String element,
  ) {
    var content = read(path);

    // 1. Idempotency check — skip when element is already present.
    if (content.contains(element)) {
      return;
    }

    // 2. Locate the anchor closing tag.
    if (!content.contains(parentXpath)) {
      throw StateError(
        'Cannot find anchor "$parentXpath" in XML file: $path',
      );
    }

    // 3. Insert element immediately before the anchor.
    content = content.replaceFirst(
      parentXpath,
      '$element\n$parentXpath',
    );

    File(path).writeAsStringSync(content);
  }

  // -------------------------------------------------------------------------
  // Android manifest helpers
  // -------------------------------------------------------------------------

  /// Add a `<uses-permission>` element to an Android manifest.
  ///
  /// The tag is inserted immediately before `</manifest>`. The operation is
  /// idempotent — if [permission] is already referenced anywhere in the file
  /// the method returns without making changes.
  ///
  /// @param manifestPath  Path to `AndroidManifest.xml`.
  /// @param permission    The full Android permission string, e.g.
  ///                      `android.permission.POST_NOTIFICATIONS`.
  ///
  /// @throws [FileSystemException] if the manifest file is not found.
  /// @throws [StateError]          if `</manifest>` is not present in the file.
  static void addAndroidPermission(
    String manifestPath,
    String permission,
  ) {
    var content = read(manifestPath);

    // 1. Idempotency — skip when the permission is already declared.
    if (content.contains(permission)) {
      return;
    }

    // 2. Validate the manifest structure before mutating.
    if (!content.contains('</manifest>')) {
      throw StateError(
        'Cannot find </manifest> closing tag in: $manifestPath',
      );
    }

    // 3. Build and insert the permission element.
    final tag = '  <uses-permission android:name="$permission"/>';
    content = content.replaceFirst(
      '</manifest>',
      '$tag\n</manifest>',
    );

    File(manifestPath).writeAsStringSync(content);
  }

  /// Add a `<meta-data>` element inside the `<application>` block of an
  /// Android manifest.
  ///
  /// The element is inserted at the start of the `<application>` content
  /// (right after the opening `<application...>` tag). The operation is
  /// idempotent — if [name] already appears in the file the method returns
  /// without making changes.
  ///
  /// @param manifestPath  Path to `AndroidManifest.xml`.
  /// @param name          Value for `android:name` attribute.
  /// @param value         Value for `android:value` attribute.
  ///
  /// @throws [FileSystemException] if the manifest file is not found.
  /// @throws [StateError]          if no `<application` opening tag is found.
  static void addAndroidMetaData(
    String manifestPath, {
    required String name,
    required String value,
  }) {
    var content = read(manifestPath);

    // 1. Idempotency — skip when meta-data with this name is already present.
    if (content.contains('android:name="$name"')) {
      return;
    }

    // 2. Find the <application ...> opening tag (may span multiple attributes).
    final appTagMatch =
        RegExp(r'<application[^>]*>', dotAll: true).firstMatch(content);
    if (appTagMatch == null) {
      throw StateError(
        'Cannot find <application> opening tag in: $manifestPath',
      );
    }

    // 3. Build the meta-data element and insert after the opening tag.
    final tag = '    <meta-data android:name="$name" android:value="$value"/>';
    final applicationTag = appTagMatch.group(0)!;
    content = content.replaceFirst(
      applicationTag,
      '$applicationTag\n$tag',
    );

    File(manifestPath).writeAsStringSync(content);
  }

  // -------------------------------------------------------------------------
  // Plist
  // -------------------------------------------------------------------------

  /// Parse basic string key-value pairs from an Apple Plist XML file.
  ///
  /// Only top-level `<key>` → `<string>` pairs inside the root `<dict>` are
  /// extracted. Nested structures, arrays, booleans, and integers are ignored.
  ///
  /// @param plistPath  Path to the `.plist` file.
  /// @return A [Map<String, dynamic>] of the extracted string values.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static Map<String, dynamic> readPlist(String plistPath) {
    final content = read(plistPath);
    final result = <String, dynamic>{};

    // Match consecutive <key>…</key> <string>…</string> pairs.
    final keyPattern = RegExp(
      r'<key>([^<]+)</key>\s*<string>([^<]*)</string>',
    );

    for (final match in keyPattern.allMatches(content)) {
      final key = match.group(1)!.trim();
      final val = match.group(2)!;
      result[key] = val;
    }

    return result;
  }
}
