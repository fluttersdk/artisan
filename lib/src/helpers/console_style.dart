/// Console output styling utilities for Laravel Artisan-style CLI commands.
///
/// Provides ANSI color formatting, banners, progress indicators, and
/// structured output formatting (tables, key-value pairs).
///
/// ## Usage
///
/// ```dart
/// // Success message
/// print(ConsoleStyle.success('Migration completed'));
///
/// // Error message
/// print(ConsoleStyle.error('File not found'));
///
/// // Table output
/// print(ConsoleStyle.table(['Name', 'Status'], [
///   ['User', 'Active'],
///   ['Admin', 'Inactive'],
/// ]));
/// ```
class ConsoleStyle {
  // ANSI color codes
  static const String green = '\x1B[32m';
  static const String red = '\x1B[31m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String cyan = '\x1B[36m';
  static const String magenta = '\x1B[35m';
  static const String white = '\x1B[37m';
  static const String bold = '\x1B[1m';
  static const String dim = '\x1B[2m';
  static const String reset = '\x1B[0m';

  /// Write a success message with green checkmark.
  ///
  /// Example: `✓ Operation completed`
  static String success(String message) {
    return '$green✓$reset $message';
  }

  /// Write an error message with red X.
  ///
  /// Example: `✗ Operation failed`
  static String error(String message) {
    return '$red✗$reset $message';
  }

  /// Write an info message with blue info symbol.
  ///
  /// Example: `ℹ Information`
  static String info(String message) {
    return '$blue ℹ$reset $message';
  }

  /// Write a warning message with yellow warning symbol.
  ///
  /// Example: `⚠ Warning message`
  static String warning(String message) {
    return '$yellow⚠$reset $message';
  }

  /// Write a comment or debug message in dim text.
  ///
  /// Example: `Comment text` (dimmed)
  static String comment(String message) {
    return '$dim$message$reset';
  }

  /// Display a progress step counter.
  ///
  /// Example: `[3/5] Installing packages`
  static String step(int current, int total, String description) {
    return '$cyan[$current/$total]$reset $description';
  }

  /// Draw a horizontal line.
  ///
  /// Default char is '─', default length is 50.
  static String line({String char = '─', int length = 50}) {
    return char * length;
  }

  /// Return an empty line.
  static String newLine() {
    return '';
  }

  /// Format a section header with bold text.
  ///
  /// Example: `Configuration`
  static String header(String title) {
    return '$bold$cyan$title$reset';
  }

  /// Create a customizable package banner.
  ///
  /// Example:
  /// ```
  /// ╔═══════════════════════════╗
  /// ║  Magic CLI v1.0.0         ║
  /// ╚═══════════════════════════╝
  /// ```
  static String banner(String title, String version) {
    final text = '  $title v$version';
    final width = text.length + 4;
    final topLine = '╔${'═' * (width - 2)}╗';
    final bottomLine = '╚${'═' * (width - 2)}╝';
    final contentLine = '║$text${' ' * (width - text.length - 2)}║';

    return '$green$topLine\n$contentLine\n$bottomLine$reset';
  }

  /// Format data as a table with headers and rows.
  ///
  /// Example:
  /// ```
  /// Name       Status
  /// ─────────  ─────────
  /// User       Active
  /// Admin      Inactive
  /// ```
  static String table(List<String> headers, List<List<String>> rows) {
    if (headers.isEmpty) return '';

    // Calculate column widths
    final columnWidths = <int>[];
    for (var i = 0; i < headers.length; i++) {
      var maxWidth = headers[i].length;
      for (final row in rows) {
        if (i < row.length && row[i].length > maxWidth) {
          maxWidth = row[i].length;
        }
      }
      columnWidths.add(maxWidth);
    }

    final buffer = StringBuffer();

    // Headers
    for (var i = 0; i < headers.length; i++) {
      buffer.write('$bold${headers[i].padRight(columnWidths[i] + 2)}$reset');
    }
    buffer.writeln();

    // Separator
    for (var i = 0; i < headers.length; i++) {
      buffer.write('─' * (columnWidths[i] + 2));
    }
    buffer.writeln();

    // Rows
    for (final row in rows) {
      for (var i = 0; i < headers.length; i++) {
        final value = i < row.length ? row[i] : '';
        buffer.write(value.padRight(columnWidths[i] + 2));
      }
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }

  /// Format a key-value pair with alignment.
  ///
  /// Example: `Name:           John Doe`
  static String keyValue(String key, String value, {int keyWidth = 20}) {
    final paddedKey = '$cyan${key.padRight(keyWidth)}$reset';
    return '$paddedKey $value';
  }
}
