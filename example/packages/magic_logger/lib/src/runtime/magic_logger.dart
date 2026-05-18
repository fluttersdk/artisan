import 'dart:convert';
import 'dart:io';

/// Tiny file-backed logger. Writes JSON-line records to [logFilePath]
/// (default `~/.magic_logger.log`). Consumers call the static API from
/// anywhere in their app; the `logger:tail` artisan command reads the
/// same file.
///
/// This is intentionally minimal, production loggers should use
/// `package:logging` or similar. The plugin's purpose is to demonstrate
/// the third-party artisan plugin pattern, not to be a real logger.
class MagicLogger {
  MagicLogger._();

  static String logFilePath =
      '${Platform.environment['HOME'] ?? '/tmp'}/.magic_logger.log';

  static LogLevel minLevel = LogLevel.info;

  static void debug(String message, {Map<String, dynamic>? context}) =>
      _write(LogLevel.debug, message, context);

  static void info(String message, {Map<String, dynamic>? context}) =>
      _write(LogLevel.info, message, context);

  static void warn(String message, {Map<String, dynamic>? context}) =>
      _write(LogLevel.warn, message, context);

  static void error(String message, {Map<String, dynamic>? context}) =>
      _write(LogLevel.error, message, context);

  static void _write(
    LogLevel level,
    String message,
    Map<String, dynamic>? context,
  ) {
    if (level.severity < minLevel.severity) return;
    final entry = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'message': message,
      if (context != null && context.isNotEmpty) 'context': context,
    };
    final file = File(logFilePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
  }
}

enum LogLevel {
  debug(severity: 10, name: 'debug'),
  info(severity: 20, name: 'info'),
  warn(severity: 30, name: 'warn'),
  error(severity: 40, name: 'error');

  const LogLevel({required this.severity, required this.name});

  final int severity;
  final String name;

  static LogLevel parse(String input) {
    return LogLevel.values.firstWhere(
      (l) => l.name == input.toLowerCase(),
      orElse: () => throw ArgumentError(
        'Unknown log level "$input" (allowed: debug|info|warn|error).',
      ),
    );
  }
}
