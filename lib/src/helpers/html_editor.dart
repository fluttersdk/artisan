import 'dart:io';

/// HTML file injection helper for CLI commands.
///
/// Provides pure string-based utilities for reading and modifying HTML files
/// (e.g. `web/index.html`) without external parser packages.
///
/// ## Usage
///
/// ```dart
/// // Read raw HTML
/// final html = HtmlEditor.read('/path/to/index.html');
///
/// // Inject a script tag before </head> (guard with hasContent first)
/// if (!HtmlEditor.hasContent('/path/to/index.html', 'OneSignalSDK')) {
///   HtmlEditor.injectBeforeClose(
///     '/path/to/index.html',
///     '</head>',
///     '  <script src="sdk.js" defer></script>',
///   );
/// }
///
/// // Add a <meta> tag (idempotent)
/// HtmlEditor.addMetaTag('/path/to/index.html', {
///   'name': 'description',
///   'content': 'My Flutter App',
/// });
/// ```
class HtmlEditor {
  HtmlEditor._();

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Read the raw HTML content from [path].
  ///
  /// @param path  Absolute or relative path to the HTML file.
  /// @return The file content as a [String].
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('HTML file not found', path);
    }
    return file.readAsStringSync();
  }

  // -------------------------------------------------------------------------
  // Inspection
  // -------------------------------------------------------------------------

  /// Check whether [pattern] appears in the HTML file (case-insensitive).
  ///
  /// @param path     Path to the HTML file.
  /// @param pattern  The string to look for.
  /// @return `true` if a case-insensitive match is found, `false` otherwise.
  static bool hasContent(String path, String pattern) {
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    final content = file.readAsStringSync();
    return content.toLowerCase().contains(pattern.toLowerCase());
  }

  // -------------------------------------------------------------------------
  // Injection
  // -------------------------------------------------------------------------

  /// Inject [content] immediately before [closingTag] in the HTML file.
  ///
  /// This method does **not** guard against duplicates — callers should call
  /// [hasContent] first if idempotency is required.
  ///
  /// @param path        Path to the HTML file.
  /// @param closingTag  Literal closing tag string used as the anchor, e.g.
  ///                    `'</head>'` or `'</body>'`.
  /// @param content     The HTML string to inject.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if [closingTag] is not found in the file.
  static void injectBeforeClose(
    String path,
    String closingTag,
    String content,
  ) {
    var html = read(path);

    if (!html.contains(closingTag)) {
      throw StateError(
        'Cannot find closing tag "$closingTag" in HTML file: $path',
      );
    }

    html = html.replaceFirst(closingTag, '$content\n$closingTag');
    File(path).writeAsStringSync(html);
  }

  /// Add a `<meta>` tag before `</head>`, building it from [attributes].
  ///
  /// The operation is idempotent: if all [attributes] values already appear
  /// together in the file the tag will not be inserted again.
  ///
  /// @param path        Path to the HTML file.
  /// @param attributes  Map of attribute name → value pairs for the meta tag,
  ///                    e.g. `{'name': 'description', 'content': 'My App'}`.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if `</head>` is not found in the file.
  static void addMetaTag(String path, Map<String, String> attributes) {
    // 1. Build the <meta> element string.
    final attribString =
        attributes.entries.map((e) => '${e.key}="${e.value}"').join(' ');
    final metaTag = '<meta $attribString>';

    final html = read(path);

    // 2. Idempotency: if every attribute value is already in the file, skip.
    final allPresent = attributes.entries.every(
      (e) => html.contains('${e.key}="${e.value}"'),
    );
    if (allPresent) {
      return;
    }

    // 3. Validate structure.
    if (!html.contains('</head>')) {
      throw StateError(
        'Cannot find </head> closing tag in HTML file: $path',
      );
    }

    // 4. Inject.
    injectBeforeClose(path, '</head>', '  $metaTag');
  }
}
