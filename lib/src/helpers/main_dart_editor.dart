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

  /// Replace `runApp(<expr>)` with `runApp(<wrapperName>(<expr>))`.
  ///
  /// Idempotent: when `<wrapperName>(` already appears as the direct argument
  /// to `runApp`, the file is left unchanged.
  ///
  /// Throws [StateError] when no `runApp(` call can be found in the file.
  ///
  /// @param mainDartPath Absolute or relative path to `main.dart`.
  /// @param wrapperName  The widget constructor name to wrap around `runApp`'s
  ///                     argument (e.g. `'SentryWidget'`).
  static void wrapRunApp(String mainDartPath, String wrapperName) {
    // 1. Read content and locate the runApp( call.
    final content = FileHelper.readFile(mainDartPath);
    final runAppAnchor = RegExp(r'runApp\(', multiLine: true);
    final match = runAppAnchor.firstMatch(content);
    if (match == null) {
      throw StateError(
        'MainDartEditor.wrapRunApp: no "runApp(" found in $mainDartPath',
      );
    }

    // 2. Skip when already wrapped (idempotency).
    if (content.contains('runApp($wrapperName(')) {
      return;
    }

    // 3. Locate the matching `)` of runApp and reconstruct the call with the
    //    wrapper injected around the inner expression.
    final openParen = match.end - 1; // position of `(`
    final closeParen = _findMatchingParen(content, openParen);
    final innerExpr = content.substring(openParen + 1, closeParen);
    final updated =
        '${content.substring(0, openParen + 1)}$wrapperName($innerExpr)${content.substring(closeParen)}';
    FileHelper.writeFile(mainDartPath, updated);
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
}
