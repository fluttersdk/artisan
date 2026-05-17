import 'file_helper.dart';
import 'config_editor.dart';

/// Route registration injection utilities for `RouteServiceProvider.boot()`.
///
/// Provides safe, idempotent mutations of the consumer's
/// `RouteServiceProvider` Dart source file: inserting or removing route
/// registration function calls inside the `boot()` body, and delegating
/// import injection to [ConfigEditor].
///
/// The implementation never evaluates Dart source as code. It operates
/// entirely on the raw string content using a brace-counting state machine to
/// locate the `boot()` body boundaries, then injects the call line at the
/// correct position.
///
/// ## Usage
///
/// ```dart
/// RouteRegistryEditor.addRouteRegistration(
///   'lib/app/providers/route_service_provider.dart',
///   'registerMyPluginRoutes',
/// );
///
/// RouteRegistryEditor.addRouteImport(
///   'lib/app/providers/route_service_provider.dart',
///   "import 'package:my_plugin/routes.dart';",
/// );
///
/// RouteRegistryEditor.removeRouteRegistration(
///   'lib/app/providers/route_service_provider.dart',
///   'registerMyPluginRoutes',
/// );
/// ```
class RouteRegistryEditor {
  RouteRegistryEditor._();

  /// Regex that matches the opening brace of `Future<void> boot() async {`.
  ///
  /// Allows arbitrary whitespace between tokens to tolerate hand-formatted
  /// provider files. The return type (`Future<void>` or `void`) is consumed
  /// as any non-whitespace token preceding `boot`, so both plain `void` and
  /// `Future<void>` signatures match correctly.
  static final RegExp _bootAnchor = RegExp(
    r'\S+\s+boot\s*\(\s*\)\s*async\s*\{',
    multiLine: true,
  );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Inserts a call to [registerFunctionName]`();` inside the `boot()` method
  /// of the `RouteServiceProvider` at [providerPath].
  ///
  /// Insertion strategy:
  /// - When `registerAppRoutes();` is present, the new call is placed on the
  ///   line immediately before it (preserving the convention that
  ///   `registerAppRoutes` is always the last call in `boot()`).
  /// - When `registerAppRoutes();` is absent, the new call is appended
  ///   immediately before the closing `}` of `boot()`.
  ///
  /// The operation is idempotent: if a call to [registerFunctionName]`();`
  /// already exists anywhere in the file, the method returns without
  /// modifying the file.
  ///
  /// @param providerPath Absolute or project-relative path to the Dart source
  ///   file containing `RouteServiceProvider`.
  /// @param registerFunctionName Name of the top-level function to call, e.g.
  ///   `'registerMyPluginRoutes'`.
  /// @throws StateError when `boot()` cannot be located in [providerPath].
  static void addRouteRegistration(
    String providerPath,
    String registerFunctionName,
  ) {
    final String content = FileHelper.readFile(providerPath);
    final String callLine = '    $registerFunctionName();';

    // 1. Idempotency guard: abort when the call is already present.
    if (content.contains('$registerFunctionName();')) {
      return;
    }

    // 2. Locate the opening brace of boot() to begin brace-counting.
    final Match? bootMatch = _bootAnchor.firstMatch(content);
    if (bootMatch == null) {
      throw StateError(
        'RouteRegistryEditor: could not locate boot() in $providerPath. '
        'Ensure the file contains a `Future<void> boot() async {` declaration.',
      );
    }

    // 3. Walk from the opening brace to find the matching closing brace using
    //    a brace depth counter. depth starts at 1 because the opening brace
    //    of boot() itself is already consumed.
    final int bodyStart = bootMatch.end;
    int depth = 1;
    int closingBraceIndex = -1;

    for (int i = bodyStart; i < content.length; i++) {
      final String ch = content[i];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          closingBraceIndex = i;
          break;
        }
      }
    }

    if (closingBraceIndex == -1) {
      throw StateError(
        'RouteRegistryEditor: unmatched opening brace for boot() in '
        '$providerPath. The file may have a syntax error.',
      );
    }

    // 4. The boot body is the substring from bodyStart to closingBraceIndex.
    final String bootBody = content.substring(bodyStart, closingBraceIndex);

    // 5. Determine insertion point and produce the updated content.
    final String updatedContent;

    const String appRoutesCall = 'registerAppRoutes();';
    if (bootBody.contains(appRoutesCall)) {
      // Insert immediately before the `registerAppRoutes();` line within body.
      final int bodyOffset = content.indexOf(appRoutesCall, bodyStart);
      final int lineStart = _lineStartOf(content, bodyOffset);

      updatedContent =
          '${content.substring(0, lineStart)}$callLine\n${content.substring(lineStart)}';
    } else {
      // No registerAppRoutes(): insert a new line before the closing brace.
      updatedContent =
          '${content.substring(0, closingBraceIndex)}$callLine\n  ${content.substring(closingBraceIndex)}';
    }

    FileHelper.writeFile(providerPath, updatedContent);
  }

  /// Removes the call line `[registerFunctionName]();` from the `boot()` body
  /// of the `RouteServiceProvider` at [providerPath].
  ///
  /// The operation is idempotent: if the call is not present the file is left
  /// unchanged.
  ///
  /// @param providerPath Absolute or project-relative path to the Dart source
  ///   file containing `RouteServiceProvider`.
  /// @param registerFunctionName Name of the top-level function whose call
  ///   line should be deleted.
  static void removeRouteRegistration(
    String providerPath,
    String registerFunctionName,
  ) {
    final String content = FileHelper.readFile(providerPath);
    final String callSuffix = '$registerFunctionName();';

    // Idempotency guard: nothing to do when the call is absent.
    if (!content.contains(callSuffix)) {
      return;
    }

    // Remove every line whose trimmed content equals the call expression.
    final List<String> lines = content.split('\n');
    final List<String> filtered =
        lines.where((String line) => line.trim() != callSuffix).toList();

    FileHelper.writeFile(providerPath, filtered.join('\n'));
  }

  /// Adds an import statement to [providerPath], delegating to
  /// [ConfigEditor.addImportToFile].
  ///
  /// Provided for chain-call symmetry with [addRouteRegistration]: a plugin
  /// installer can call both methods on the same [providerPath] in sequence
  /// without switching helpers.
  ///
  /// The operation is idempotent (handled by [ConfigEditor.addImportToFile]).
  ///
  /// @param providerPath Absolute or project-relative path to the Dart source
  ///   file that should receive the import.
  /// @param importStatement The full import statement string, e.g.
  ///   `"import 'package:my_plugin/routes.dart';"`.
  static void addRouteImport(
    String providerPath,
    String importStatement,
  ) {
    ConfigEditor.addImportToFile(
      filePath: providerPath,
      importStatement: importStatement,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Returns the index of the first character on the same line as [offset].
  ///
  /// Scans backwards from [offset] to find the preceding newline character,
  /// then returns the index after it (i.e. the start of the line).
  static int _lineStartOf(String content, int offset) {
    int i = offset - 1;
    while (i >= 0 && content[i] != '\n') {
      i--;
    }
    return i + 1;
  }
}
