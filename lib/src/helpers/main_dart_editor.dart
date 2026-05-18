import 'config_editor.dart';
import 'file_helper.dart';

/// Targeted mutations for a Flutter application's `lib/main.dart` file.
///
/// All methods are idempotent: calling them a second time with the same
/// arguments leaves the file unchanged. Every method that searches for a
/// `Magic.init(...)` call throws [StateError] when the anchor is not present,
/// so callers receive an actionable error rather than silent no-ops.
///
/// ## Usage
///
/// ```dart
/// // Add an import at the top of main.dart.
/// MainDartEditor.addImport(
///   'lib/main.dart',
///   "import 'package:sentry_flutter/sentry_flutter.dart'",
/// );
///
/// // Inject plugin-install code before Magic.init().
/// MainDartEditor.injectBeforeMagicInit(
///   'lib/main.dart',
///   '  DuskPlugin.install();\n',
/// );
///
/// // Inject post-init adapters after Magic.init().
/// MainDartEditor.injectAfterMagicInit(
///   'lib/main.dart',
///   '  MagicDuskIntegration.install();\n',
/// );
///
/// // Wrap the runApp() call with a higher-order widget.
/// MainDartEditor.wrapRunApp('lib/main.dart', 'SentryWidget');
///
/// // Wrap a custom entry point (e.g. runWidget) instead of runApp.
/// MainDartEditor.wrapRunApp('lib/main.dart', 'SentryWidget', appCall: 'runWidget');
/// ```
class MainDartEditor {
  MainDartEditor._();

  /// Regex that matches the opening of a `Magic.init(` call.
  ///
  /// Handles optional whitespace between `Magic`, `.`, `init`, and `(`.
  static final RegExp _initAnchor = RegExp(
    r'await\s+Magic\.init\s*\(',
    multiLine: true,
  );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Add [importStatement] to [mainDartPath] if not already present.
  ///
  /// Delegates to [ConfigEditor.addImportToFile] for consistent placement
  /// (after the last existing import line). Idempotent.
  ///
  /// @param mainDartPath Absolute or relative path to `main.dart`.
  /// @param importStatement The import string, with or without a trailing `;`.
  static void addImport(String mainDartPath, String importStatement) {
    ConfigEditor.addImportToFile(
      filePath: mainDartPath,
      importStatement: importStatement,
    );
  }

  /// Insert [code] on the line immediately before `await Magic.init(...)`.
  ///
  /// The insertion is skipped when [code] (trimmed) is already present
  /// anywhere in the file, making the call idempotent.
  ///
  /// Throws [StateError] when no `Magic.init` call can be found in the file.
  ///
  /// @param mainDartPath Absolute or relative path to `main.dart`.
  /// @param code         The source block to insert, including trailing newline.
  static void injectBeforeMagicInit(String mainDartPath, String code) {
    // 1. Read current content and locate the Magic.init anchor.
    final content = FileHelper.readFile(mainDartPath);
    final match = _initAnchor.firstMatch(content);
    if (match == null) {
      throw StateError(
        'MainDartEditor.injectBeforeMagicInit: no "await Magic.init(" found '
        'in $mainDartPath',
      );
    }

    // 2. Skip insertion when the block is already present (idempotency).
    if (content.contains(code.trim())) {
      return;
    }

    // 3. Insert code at the start of the line that contains the init call.
    final lineStart = _lineStartBefore(content, match.start);
    final updated =
        content.substring(0, lineStart) + code + content.substring(lineStart);
    FileHelper.writeFile(mainDartPath, updated);
  }

  /// Insert [code] on the line immediately after the closing `);` of
  /// `await Magic.init(...)`.
  ///
  /// Uses a brace-counting state machine starting from the opening `(` of
  /// `Magic.init` so that multi-line calls (with nested `configFactories`
  /// lists) are handled correctly.
  ///
  /// The insertion is skipped when [code] (trimmed) is already present
  /// anywhere in the file, making the call idempotent.
  ///
  /// Throws [StateError] when no `Magic.init` call can be found in the file.
  ///
  /// @param mainDartPath Absolute or relative path to `main.dart`.
  /// @param code         The source block to insert, including trailing newline.
  static void injectAfterMagicInit(String mainDartPath, String code) {
    // 1. Read current content and locate the Magic.init anchor.
    final content = FileHelper.readFile(mainDartPath);
    final match = _initAnchor.firstMatch(content);
    if (match == null) {
      throw StateError(
        'MainDartEditor.injectAfterMagicInit: no "await Magic.init(" found '
        'in $mainDartPath',
      );
    }

    // 2. Skip insertion when the block is already present (idempotency).
    if (content.contains(code.trim())) {
      return;
    }

    // 3. Walk from the opening `(` using a paren-depth counter to find the
    //    matching closing `)`. The `(` is the last character of the match.
    final closingParenIndex = _findMatchingParen(content, match.end - 1);

    // 4. Advance past the `)` and any trailing `;` on the same line, then
    //    find the end of that line so we insert after it.
    final insertAt = _lineEndAfter(content, closingParenIndex);
    final updated =
        content.substring(0, insertAt) + code + content.substring(insertAt);
    FileHelper.writeFile(mainDartPath, updated);
  }

  /// Insert [snippet] immediately before the line containing [anchor] in [source].
  ///
  /// This is a pure functional transform: the modified source string is returned
  /// and no file I/O is performed.
  ///
  /// Idempotent: when [snippet] (trimmed) already appears anywhere in [source],
  /// the source is returned unchanged.
  ///
  /// Anchor not found: when no line in [source] contains [anchor] as a substring,
  /// the source is returned unchanged (no exception is thrown).
  ///
  /// When [indent] is supplied, it is prepended to every line of [snippet] before
  /// insertion. Lines that are already empty (or whitespace-only) are not indented
  /// so that blank separator lines stay clean.
  ///
  /// @param source  The full source text to transform.
  /// @param anchor  Substring that identifies the insertion anchor line.
  /// @param snippet The text block to insert, including trailing newline(s).
  /// @param indent  Optional leading whitespace to prepend to each snippet line.
  /// @return        The transformed source, or [source] unchanged when the anchor
  ///                is absent or the snippet is already present.
  static String injectBeforeAnchor({
    required String source,
    required String anchor,
    required String snippet,
    String? indent,
  }) {
    // 1. Apply optional indentation to produce the final block to insert.
    final block = indent == null ? snippet : _indentBlock(snippet, indent);

    // 2. Skip insertion when the snippet body is already present (idempotency).
    //    Compare against trimmed snippet so trailing-newline differences are
    //    ignored on subsequent calls.
    if (source.contains(snippet.trim())) {
      return source;
    }

    // 3. Locate the first line that contains the anchor substring.
    final lines = source.split('\n');
    final anchorLineIndex = lines.indexWhere((line) => line.contains(anchor));
    if (anchorLineIndex == -1) {
      return source;
    }

    // 4. Rebuild: everything before the anchor line + block + anchor line onward.
    //    split('\n') loses the newlines, so we rejoin with '\n' at the end.
    //    The block is expected to carry its own trailing newline(s).
    final before = lines.sublist(0, anchorLineIndex).join('\n');
    final from = lines.sublist(anchorLineIndex).join('\n');

    // Preserve the original leading newline separator when the before-section
    // is non-empty (i.e. the anchor was not the very first line).
    if (before.isEmpty) {
      return block + from;
    }
    return '$before\n$block$from';
  }

  /// Insert [snippet] immediately AFTER the closing `)` of the call expression
  /// `anchor(...)` in [source]. The anchor matches the first occurrence of
  /// `<anchor>(` (e.g. `'Magic.init'` matches `await Magic.init(`); the
  /// matching closing paren is found via a depth counter so multi-line calls
  /// with nested arguments are handled correctly.
  ///
  /// Pure functional transform: no file I/O. Returns the modified source.
  ///
  /// Idempotent: when [snippet] (trimmed) already appears anywhere in [source],
  /// the source is returned unchanged.
  ///
  /// Anchor not found: when `<anchor>(` cannot be located, the source is
  /// returned unchanged (no exception is thrown), matching the
  /// fail-soft contract of [injectBeforeAnchor].
  ///
  /// @param source  The full source text to transform.
  /// @param anchor  The call name to match (without the `(`). Regex-escaped
  ///                internally so `'Magic.init'` is matched literally.
  /// @param snippet The text block to insert after the closing `)`, including
  ///                trailing newline(s).
  /// @return        The transformed source, or [source] unchanged.
  static String injectAfterAnchor({
    required String source,
    required String anchor,
    required String snippet,
  }) {
    // 1. Skip insertion when the snippet body is already present (idempotency).
    if (source.contains(snippet.trim())) {
      return source;
    }

    // 2. Locate the opening `(` of the anchored call; bail when absent.
    final callPattern =
        RegExp('${RegExp.escape(anchor)}\\s*\\(', multiLine: true);
    final match = callPattern.firstMatch(source);
    if (match == null) {
      return source;
    }

    // 3. Walk from the opening `(` using a paren-depth counter to find the
    //    matching closing `)`. _findMatchingParen throws on unmatched parens
    //    (malformed source), preserving the fail-loud contract from wrapRunApp.
    final openParen = match.end - 1;
    final closeParen = _findMatchingParen(source, openParen);

    // 4. Advance past `)` and any trailing `;` on the same line, then insert
    //    on the next line so the snippet sits in its own statement block.
    final insertAt = _lineEndAfter(source, closeParen);
    return source.substring(0, insertAt) + snippet + source.substring(insertAt);
  }

  /// Replace `<appCall>(<expr>)` with `<appCall>(<wrapperName>(<expr>))`.
  ///
  /// Idempotent: when `<wrapperName>(` already appears as the direct argument
  /// to `<appCall>`, the file is left unchanged.
  ///
  /// Throws [StateError] when no `<appCall>(` call can be found in the file.
  ///
  /// @param mainDartPath Absolute or relative path to `main.dart`.
  /// @param wrapperName  The widget constructor name to wrap around the entry
  ///                     point's argument (e.g. `'SentryWidget'`).
  /// @param appCall      The Flutter entry-point function name to match
  ///                     (defaults to `'runApp'`, the Flutter standard).
  ///                     Pass a custom value (e.g. `'runWidget'`) for
  ///                     non-standard entry points.
  static void wrapRunApp(
    String mainDartPath,
    String wrapperName, {
    String appCall = 'runApp',
  }) {
    // 1. Read content and locate the named entry-point call.
    final content = FileHelper.readFile(mainDartPath);

    // 2. Delegate pure transform to wrapRunAppInSource, then persist.
    final updated = wrapRunAppInSource(
      content,
      wrapperName,
      appCall: appCall,
      sourceName: mainDartPath,
    );
    if (updated == content) return; // already wrapped — nothing to write.
    FileHelper.writeFile(mainDartPath, updated);
  }

  /// Pure-functional sibling of [wrapRunApp].
  ///
  /// Replace `<appCall>(<expr>)` with `<appCall>(<wrapperName>(<expr>))` in
  /// [source] and return the modified string. No file I/O is performed.
  ///
  /// Idempotent: when `<wrapperName>(` already appears as the direct argument
  /// to `<appCall>`, [source] is returned unchanged.
  ///
  /// Throws [StateError] when no `<appCall>(` call can be found in [source].
  ///
  /// @param source      The full source text to transform.
  /// @param wrapperName The widget constructor name to wrap around the inner
  ///                    expression (e.g. `'MagicApplication'`).
  /// @param appCall     The Flutter entry-point function name to match
  ///                    (defaults to `'runApp'`). Pass a custom value (e.g.
  ///                    `'runWidget'`) for non-standard entry points.
  /// @param sourceName  Optional label used in [StateError] messages to help
  ///                    the caller identify which source triggered the error.
  /// @return            The transformed source, or [source] unchanged when the
  ///                    wrapper is already present.
  static String wrapRunAppInSource(
    String source,
    String wrapperName, {
    String appCall = 'runApp',
    String sourceName = '<source>',
  }) {
    // 1. Locate the named entry-point call; throw when absent.
    final entryAnchor = RegExp('${RegExp.escape(appCall)}\\(', multiLine: true);
    final match = entryAnchor.firstMatch(source);
    if (match == null) {
      throw StateError(
        'MainDartEditor.wrapRunAppInSource: no "$appCall(" found in $sourceName',
      );
    }

    // 2. Skip when already wrapped (idempotency).
    if (source.contains('$appCall($wrapperName(')) {
      return source;
    }

    // 3. Locate the matching `)` of the entry-point call and reconstruct it
    //    with the wrapper injected around the inner expression.
    final openParen = match.end - 1; // position of `(`
    final closeParen = _findMatchingParen(source, openParen);
    final innerExpr = source.substring(openParen + 1, closeParen);
    return '${source.substring(0, openParen + 1)}$wrapperName($innerExpr)${source.substring(closeParen)}';
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Return the index of the start of the line that contains [offset].
  static int _lineStartBefore(String content, int offset) {
    var i = offset - 1;
    while (i >= 0 && content[i] != '\n') {
      i--;
    }
    return i + 1;
  }

  /// Return the index just after the newline that terminates the line
  /// containing [offset]. If the line runs to end-of-file, returns
  /// `content.length`.
  static int _lineEndAfter(String content, int offset) {
    var i = offset;
    while (i < content.length && content[i] != '\n') {
      i++;
    }
    // i now points at the `\n` (or past EOF). Move past the newline.
    if (i < content.length) {
      i++;
    }
    return i;
  }

  /// Walk [content] from [openParenIndex] (which must be `(`) and return the
  /// index of the matching `)`, using a depth counter.
  ///
  /// Throws [StateError] when the file ends before the paren is closed.
  static int _findMatchingParen(String content, int openParenIndex) {
    var depth = 0;
    for (var i = openParenIndex; i < content.length; i++) {
      final ch = content[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    throw StateError(
      'MainDartEditor: unmatched "(" at offset $openParenIndex, '
      'the file may be malformed.',
    );
  }

  /// Prepend [indent] to every non-blank line in [block].
  ///
  /// Blank or whitespace-only lines are left as-is so that blank separator
  /// lines inside multi-line snippets remain clean.
  ///
  /// @param block  The text block, possibly containing newlines.
  /// @param indent The whitespace prefix to add to each non-blank line.
  /// @return       The indented block, preserving the original trailing newline.
  static String _indentBlock(String block, String indent) {
    return block
        .split('\n')
        .map((line) => line.trim().isEmpty ? line : '$indent$line')
        .join('\n');
  }
}
