import 'dart:io';

import '../helpers/console_style.dart';

/// Abstract output layer for [ArtisanCommand] (Symfony Console parity).
///
/// Three concrete subclasses: [StdioOutput] (default), [BufferedOutput]
/// (testing), [NullOutput] (suppress all output).
abstract class ArtisanOutput {
  /// Verbosity threshold. Methods below honor this; if the level required
  /// exceeds [verbosity], the call is a no-op.
  int get verbosity;

  void writeln(String text, {int level = 1});
  void info(String text, {int level = 1});
  void success(String text, {int level = 1});
  void warning(String text, {int level = 1});
  void error(String text);
  void comment(String text, {int level = 2});
  void debug(String text) => comment('[debug] $text', level: 4);
}

/// Default output: stdout for normal/info/success/comment, stderr for error.
class StdioOutput implements ArtisanOutput {
  StdioOutput({this.verbosity = 1});

  @override
  final int verbosity;

  @override
  void writeln(String text, {int level = 1}) {
    if (verbosity >= level) stdout.writeln(text);
  }

  @override
  void info(String text, {int level = 1}) {
    if (verbosity >= level) stdout.writeln(ConsoleStyle.info(text));
  }

  @override
  void success(String text, {int level = 1}) {
    if (verbosity >= level) stdout.writeln(ConsoleStyle.success(text));
  }

  @override
  void warning(String text, {int level = 1}) {
    if (verbosity >= level) stdout.writeln(ConsoleStyle.warning(text));
  }

  @override
  void error(String text) => stderr.writeln(ConsoleStyle.error(text));

  @override
  void comment(String text, {int level = 2}) {
    if (verbosity >= level) stdout.writeln(ConsoleStyle.comment(text));
  }

  @override
  void debug(String text) => comment('[debug] $text', level: 4);
}

/// Test-friendly output that captures everything into an in-memory buffer.
class BufferedOutput implements ArtisanOutput {
  BufferedOutput({this.verbosity = 1});

  final StringBuffer _buffer = StringBuffer();

  @override
  final int verbosity;

  String get content => _buffer.toString();

  @override
  void writeln(String text, {int level = 1}) {
    if (verbosity >= level) _buffer.writeln(text);
  }

  @override
  void info(String text, {int level = 1}) => writeln(text, level: level);

  @override
  void success(String text, {int level = 1}) => writeln(text, level: level);

  @override
  void warning(String text, {int level = 1}) => writeln(text, level: level);

  @override
  void error(String text) => _buffer.writeln('[ERROR] $text');

  @override
  void comment(String text, {int level = 2}) => writeln(text, level: level);

  @override
  void debug(String text) => comment('[debug] $text', level: 4);
}

/// Discards every write. For tests that don't care about output.
class NullOutput implements ArtisanOutput {
  @override
  int get verbosity => 0;

  @override
  void writeln(String text, {int level = 1}) {}
  @override
  void info(String text, {int level = 1}) {}
  @override
  void success(String text, {int level = 1}) {}
  @override
  void warning(String text, {int level = 1}) {}
  @override
  void error(String text) {}
  @override
  void comment(String text, {int level = 2}) {}
  @override
  void debug(String text) {}
}
