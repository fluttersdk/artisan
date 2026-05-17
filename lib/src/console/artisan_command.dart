import 'dart:io';

import 'package:args/args.dart';
import '../helpers/console_style.dart';

/// Base class for all Magic CLI commands.
abstract class Command {
  /// Command name, e.g. 'make:controller'
  String get name;

  /// Short description shown in help
  String get description;

  /// The parsed arguments
  late ArgResults arguments;

  /// Define arguments and options via [parser]
  void configure(ArgParser parser) {}

  /// Execute the command — implement in subclasses
  Future<void> handle();

  /// Execute this command programmatically with the given [args].
  /// Useful for calling commands from other commands.
  Future<void> runWith(List<String> args) async {
    final parser = ArgParser();
    configure(parser);
    arguments = parser.parse(args);
    await handle();
  }

  // IO helpers (delegate to ConsoleStyle):
  void info(String message) => stdout.writeln(ConsoleStyle.info(message));

  void success(String message) => stdout.writeln(ConsoleStyle.success(message));

  void warn(String message) => stdout.writeln(ConsoleStyle.warning(message));

  void error(String message) => stderr.writeln(ConsoleStyle.error(message));

  void line({String char = '-', int length = 60}) =>
      stdout.writeln(ConsoleStyle.line(char: char, length: length));

  void newLine() => stdout.writeln(ConsoleStyle.newLine());

  void comment(String message) => stdout.writeln(ConsoleStyle.comment(message));

  void table(List<String> headers, List<List<String>> rows) =>
      stdout.writeln(ConsoleStyle.table(headers, rows));

  void keyValue(String key, String value, {int keyWidth = 20}) =>
      stdout.writeln(ConsoleStyle.keyValue(key, value, keyWidth: keyWidth));

  // Arg helpers (populated after parse):

  /// Get option value
  dynamic option(String name) {
    if (!arguments.options.contains(name)) {
      return null;
    }
    return arguments[name];
  }

  /// Get positional arg by name
  String? argument(int index) {
    if (index >= arguments.rest.length) {
      return null;
    }
    return arguments.rest[index];
  }

  /// Check if option was provided
  bool hasOption(String name) {
    return arguments.wasParsed(name);
  }

  // Input helpers (for interactive prompts):

  String? ask(String question, {String? defaultValue}) {
    if (defaultValue != null) {
      stdout.write('$question [$defaultValue]: ');
    } else {
      stdout.write('$question: ');
    }

    final input = stdin.readLineSync();
    if (input == null || input.trim().isEmpty) {
      return defaultValue ?? '';
    }
    return input.trim();
  }

  bool confirm(String question, {bool? defaultValue}) {
    final defaultText = defaultValue == null
        ? 'y/n'
        : defaultValue
            ? 'Y/n'
            : 'y/N';
    stdout.write('$question [$defaultText]: ');

    final input = stdin.readLineSync()?.trim().toLowerCase();
    if (input == null || input.isEmpty) {
      return defaultValue ?? false;
    }

    return input == 'y' || input == 'yes';
  }

  String choice(String question, List<String> options, {int? defaultIndex}) {
    stdout.writeln(question);
    for (var i = 0; i < options.length; i++) {
      final marker = defaultIndex == i ? '>' : ' ';
      stdout.writeln(' $marker [$i] ${options[i]}');
    }

    if (defaultIndex != null) {
      stdout.write('Select [$defaultIndex]: ');
    } else {
      stdout.write('Select: ');
    }

    final input = stdin.readLineSync()?.trim();
    if (input == null || input.isEmpty) {
      if (defaultIndex != null &&
          defaultIndex >= 0 &&
          defaultIndex < options.length) {
        return options[defaultIndex];
      }
      return options[0];
    }

    final index = int.tryParse(input);
    if (index != null && index >= 0 && index < options.length) {
      return options[index];
    }

    // Invalid input, return default or first option
    if (defaultIndex != null &&
        defaultIndex >= 0 &&
        defaultIndex < options.length) {
      return options[defaultIndex];
    }
    return options[0];
  }
}
