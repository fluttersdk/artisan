import 'dart:io';

import 'package:args/args.dart';
import '../helpers/console_style.dart';
import 'command.dart';

/// The core console application runner.
class Kernel {
  static const String version = '1.0.0';

  final Map<String, Command> _commands = {};

  /// Register a single command.
  void register(Command command) {
    _commands[command.name] = command;
  }

  /// Register multiple commands at once.
  void registerMany(List<Command> commands) {
    for (final cmd in commands) {
      register(cmd);
    }
  }

  /// Process raw arguments and dispatch to appropriate command.
  Future<void> handle(List<String> args) async {
    if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
      _printHelp();
      return;
    }

    if (args.contains('--version') || args.contains('-V')) {
      stdout.writeln('Magic Framework $version');
      return;
    }

    final commandName = args[0];
    final command = _commands[commandName];

    if (command == null) {
      stderr.writeln(
          ConsoleStyle.error('Command "$commandName" is not defined.'));
      _printHelp();
      exitCode = 1;
      return;
    }

    final parser = ArgParser();
    parser.addFlag('help',
        abbr: 'h',
        help: 'Display help for the given command',
        negatable: false);

    // Let command configure its options
    command.configure(parser);

    // Skip the command name
    final commandArgs = args.sublist(1);

    try {
      final results = parser.parse(commandArgs);

      if (results.wasParsed('help')) {
        _printCommandHelp(command, parser);
        return;
      }

      command.arguments = results;
      await command.handle();
    } on FormatException catch (e) {
      stderr.writeln(ConsoleStyle.error(e.message));
      _printCommandHelp(command, parser);
      exitCode = 1;
    } catch (e) {
      stderr.writeln(
          ConsoleStyle.error('An error occurred while executing the command:'));
      stderr.writeln(e);
      exitCode = 1;
    }
  }

  void _printCommandHelp(Command command, ArgParser parser) {
    stdout.writeln(ConsoleStyle.info('Description:'));
    stdout.writeln('  ${command.description}');
    stdout.writeln('');

    stdout.writeln(ConsoleStyle.info('Usage:'));
    stdout.writeln('  magic ${command.name} [options] [arguments]');
    stdout.writeln('');

    if (parser.options.isNotEmpty) {
      stdout.writeln(ConsoleStyle.info('Options:'));
      stdout.writeln(
          parser.usage.replaceAll(RegExp(r'^', multiLine: true), '  '));
    }
  }

  void _printHelp() {
    stdout.writeln(ConsoleStyle.header('Magic Framework $version'));
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Usage:'));
    stdout.writeln('  magic <command> [arguments]');
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Options:'));
    stdout.writeln('  -h, --help      Display help for the given command');
    stdout.writeln('  -V, --version   Display this application version');
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Available commands:'));

    // Group commands by namespace (e.g., 'make', 'db')
    final namespaces = <String, List<Command>>{};
    final rootCommands = <Command>[];

    for (final cmd in _commands.values) {
      final parts = cmd.name.split(':');
      if (parts.length > 1) {
        final ns = parts[0];
        namespaces.putIfAbsent(ns, () => []).add(cmd);
      } else {
        rootCommands.add(cmd);
      }
    }

    // Print root commands first
    rootCommands.sort((a, b) => a.name.compareTo(b.name));
    for (final cmd in rootCommands) {
      _printCommandRow(cmd.name, cmd.description);
    }

    // Print namespaced commands grouped
    final sortedNamespaces = namespaces.keys.toList()..sort();

    for (final ns in sortedNamespaces) {
      stdout.writeln(' ${ConsoleStyle.yellow}$ns${ConsoleStyle.reset}');

      final nsCommands = namespaces[ns]!
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final cmd in nsCommands) {
        _printCommandRow(cmd.name, cmd.description);
      }
    }
  }

  void _printCommandRow(String name, String description) {
    final paddedName = name.padRight(20);
    stdout.writeln(
        '  ${ConsoleStyle.green}$paddedName${ConsoleStyle.reset} $description');
  }
}
