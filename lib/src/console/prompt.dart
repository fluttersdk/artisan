import 'dart:io';

/// Interactive stdin prompts for ArtisanCommands.
///
/// Mirrors Laravel's [InteractsWithIO] surface but stays POSIX-friendly:
/// reads from `stdin.readLineSync()` rather than a full readline library
/// (no extra deps, no platform-specific quirks).
///
/// Use these helpers inside [ArtisanCommand.handle] to gather missing
/// inputs from the user. Tests inject a [Prompt.testOverride] to bypass
/// the real stdin.
class Prompt {
  Prompt._();

  /// Test injection seam. When non-null, every Prompt method consumes
  /// the next answer from this queue instead of reading from stdin.
  /// Tests should reset this in setUp/tearDown.
  ///
  /// Example:
  /// ```dart
  /// Prompt.testOverride = ['yes', 'My Project'];
  /// expect(Prompt.confirm('proceed?'), isTrue);
  /// expect(Prompt.ask('name?'), 'My Project');
  /// Prompt.testOverride = null;
  /// ```
  static List<String>? testOverride;

  /// Ask a free-form question. Returns the user's answer trimmed.
  ///
  /// When the user just presses ENTER, [defaultValue] is returned. Null
  /// default means an empty answer returns the empty string (not null).
  ///
  /// [validator], when supplied, is called on the parsed answer; returning
  /// a non-null string re-asks the question with that message printed
  /// above the prompt.
  static String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) {
    while (true) {
      _writePrompt(question, defaultValue);
      final raw = _readLine();
      final answer = raw.isEmpty ? (defaultValue ?? '') : raw;
      if (validator != null) {
        final err = validator(answer);
        if (err != null) {
          stdout.writeln('  ✗ $err');
          continue;
        }
      }
      return answer;
    }
  }

  /// Ask a yes/no question. Accepts `y`/`yes`/`n`/`no` (case-insensitive)
  /// + Enter for the default.
  static bool confirm(String question, {bool defaultValue = false}) {
    while (true) {
      final hint = defaultValue ? '[Y/n]' : '[y/N]';
      stdout.write('$question $hint ');
      final raw = _readLine().toLowerCase();
      if (raw.isEmpty) return defaultValue;
      if (raw == 'y' || raw == 'yes') return true;
      if (raw == 'n' || raw == 'no') return false;
      stdout.writeln('  ✗ Please answer y or n.');
    }
  }

  /// Pick one option from a closed set. Accepts the index (1-based) OR
  /// the option string itself. Returns the chosen option.
  ///
  /// ```dart
  /// final env = Prompt.choice('Which env?',
  ///     options: ['local', 'staging', 'production'], defaultValue: 'local');
  /// ```
  static String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) {
    if (options.isEmpty) {
      throw ArgumentError('Prompt.choice: options must not be empty.');
    }
    while (true) {
      stdout.writeln(question);
      for (var i = 0; i < options.length; i++) {
        final marker = options[i] == defaultValue ? '*' : ' ';
        stdout.writeln('  $marker [${i + 1}] ${options[i]}');
      }
      stdout.write('Choice${defaultValue == null ? '' : ' [$defaultValue]'}: ');
      final raw = _readLine();
      if (raw.isEmpty && defaultValue != null) return defaultValue;
      final asInt = int.tryParse(raw);
      if (asInt != null && asInt >= 1 && asInt <= options.length) {
        return options[asInt - 1];
      }
      if (options.contains(raw)) return raw;
      stdout.writeln(
          '  ✗ Choose 1-${options.length} or one of: ${options.join(", ")}');
    }
  }

  /// Like [ask] but hides the typed characters (passwords, tokens).
  /// Falls back to plain [ask] when stdin is not a TTY.
  static String secret(String question) {
    if (!stdin.hasTerminal) return ask(question);
    final wasEchoOn = stdin.echoMode;
    stdout.write('$question: ');
    stdin.echoMode = false;
    try {
      final line = stdin.readLineSync() ?? '';
      stdout.writeln('');
      return line;
    } finally {
      stdin.echoMode = wasEchoOn;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static String _readLine() {
    final override = testOverride;
    if (override != null) {
      if (override.isEmpty) {
        throw StateError(
          'Prompt.testOverride consumed; supply more entries or null it out.',
        );
      }
      return override.removeAt(0).trim();
    }
    return (stdin.readLineSync() ?? '').trim();
  }

  static void _writePrompt(String question, String? defaultValue) {
    if (defaultValue != null && defaultValue.isNotEmpty) {
      stdout.write('$question [$defaultValue]: ');
    } else {
      stdout.write('$question: ');
    }
  }
}
