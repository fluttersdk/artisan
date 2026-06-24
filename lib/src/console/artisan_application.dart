import 'dart:io';

import 'package:args/args.dart';

import '../helpers/console_style.dart';
import '../state/state_file.dart';
import '../vm/vm_service_client.dart';
import 'artisan_command.dart';
import 'artisan_context.dart';
import 'artisan_input.dart';
import 'artisan_output.dart';
import 'artisan_registry.dart';
import 'command_boot.dart';

/// Core console application + dispatcher.
///
/// Boot lifecycle per [CommandBoot]:
/// - [CommandBoot.none]: `ArtisanContext.bare(input, output)`, no Magic, no VM.
/// - [CommandBoot.connected]: read `~/.artisan/state.json`, dial VM Service
///   WebSocket, `ArtisanContext.connected(input, output, vmClient)`. Fails fast
///   when no state.json (`Run artisan start first.`).
///
/// V1 has 2 boot modes; headless is deferred to V1.x (would force a Flutter
/// dep into pure-Dart artisan + circular dep with magic).
class ArtisanApplication {
  ArtisanApplication({required this.registry, this.version = '1.0.0-alpha.1'});

  static const String defaultVersion = '1.0.0-alpha.1';

  final ArtisanRegistry registry;
  final String version;

  /// Dispatch a raw argv list. Returns the process exit code (0 = success).
  Future<int> dispatch(List<String> args) async {
    if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
      _printRootHelp();
      return 0;
    }
    if (args[0] == '--version' || args[0] == '-V') {
      stdout.writeln('artisan $version');
      return 0;
    }

    final commandName = args[0];
    final command = registry.find(commandName);
    if (command == null) {
      stderr.writeln(
        ConsoleStyle.error(
          'Unknown command: "$commandName". Try `artisan list`.',
        ),
      );
      return 1;
    }

    final parser = ArgParser();
    parser.addFlag(
      'help',
      abbr: 'h',
      help: 'Show command help',
      negatable: false,
    );
    command.configure(parser);

    final commandArgs = args.sublist(1);
    final ArgResults parsed;
    try {
      parsed = parser.parse(commandArgs);
    } on ArgParserException catch (e) {
      // An unknown flag must fail loudly rather than silently printing help as
      // if it were requested: name the offending option, then show the help so
      // the caller can find the correct flag. Other parse failures (missing
      // value, bad value, mandatory option) keep their original message.
      if (_isUnknownOption(e)) {
        stderr.writeln(
          ConsoleStyle.error('Unknown option: ${e.argumentName ?? e.message}'),
        );
      } else {
        stderr.writeln(ConsoleStyle.error(e.message));
      }
      _printCommandHelp(command, parser);
      return 1;
    } on FormatException catch (e) {
      stderr.writeln(ConsoleStyle.error(e.message));
      _printCommandHelp(command, parser);
      return 1;
    }

    if (parsed.wasParsed('help')) {
      _printCommandHelp(command, parser);
      return 0;
    }

    final input = ArgvInput(parsed, signature: command.parsedSignature);
    final output = StdioOutput(verbosity: input.verbosity);

    switch (command.boot) {
      case CommandBoot.none:
        return await _runWithBare(command, input, output);
      case CommandBoot.connected:
        return await _runWithConnected(command, input, output);
    }
  }

  Future<int> _runWithBare(
    ArtisanCommand command,
    ArtisanInput input,
    ArtisanOutput output,
  ) async {
    try {
      return await command.handle(
        ArtisanContext.bare(input, output, registry: registry),
      );
    } catch (e, s) {
      output.error('Unexpected error in ${command.name}: $e');
      stderr.writeln(s);
      return 3;
    }
  }

  Future<int> _runWithConnected(
    ArtisanCommand command,
    ArtisanInput input,
    ArtisanOutput output,
  ) async {
    final state = await StateFile.read();
    if (state == null) {
      output.error(
        'No running Flutter app detected (state file: ${StateFile.path}).\n'
        'Run `artisan start --device=<chrome|macos|linux|windows|UDID>` first.',
      );
      return 1;
    }
    final wsUri = state['vmServiceUri'] as String?;
    if (wsUri == null) {
      output.error('state.json missing vmServiceUri; re-run `artisan start`.');
      return 1;
    }
    final vmClient = VmServiceClient(wsUri);
    try {
      await vmClient.connect();
      return await command.handle(
        ArtisanContext.connected(input, output, vmClient, registry: registry),
      );
    } catch (e, s) {
      output.error('Connected command ${command.name} failed: $e');
      stderr.writeln(s);
      return 3;
    } finally {
      await vmClient.disconnect();
    }
  }

  /// Whether [e] reports an unknown option / flag rather than a missing value,
  /// a disallowed value, or a mandatory-option violation.
  ///
  /// Dart's `args` has no dedicated unknown-flag error type, so the signal is
  /// the message prefix the parser emits for every "Could not find an option"
  /// path (`--long` and `-short` both share it). Matching the prefix keeps the
  /// other [ArgParserException] causes on their original, helpful messages.
  bool _isUnknownOption(ArgParserException e) {
    return e.message.startsWith('Could not find an option');
  }

  void _printRootHelp() {
    stdout.writeln(ConsoleStyle.header('artisan $version'));
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Usage:'));
    stdout.writeln('  artisan <command> [arguments]');
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Global options:'));
    stdout.writeln(
      '  -h, --help     Show this help, or `artisan help <command>` for command help.',
    );
    stdout.writeln('  -V, --version  Show artisan version.');
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Hint:'));
    stdout.writeln(
      '  Run `artisan list` to see every registered command (grouped by `:` namespace).',
    );
  }

  void _printCommandHelp(ArtisanCommand command, ArgParser parser) {
    final signature = command.parsedSignature;
    final argsHint = signature == null
        ? '[arguments]'
        : signature.arguments.map((a) {
            final base = a.isOptional ? '[${a.name}]' : '<${a.name}>';
            return a.isVariadic ? '$base...' : base;
          }).join(' ');

    stdout.writeln(ConsoleStyle.info('Description:'));
    stdout.writeln('  ${command.description}');
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Usage:'));
    stdout.writeln('  artisan ${command.name} [options] $argsHint');
    stdout.writeln('');
    stdout.writeln(ConsoleStyle.info('Boot mode:'));
    stdout.writeln('  ${command.boot.name}');
    stdout.writeln('');
    if (signature != null && signature.arguments.isNotEmpty) {
      stdout.writeln(ConsoleStyle.info('Arguments:'));
      for (final a in signature.arguments) {
        final attrs = <String>[
          if (a.isOptional) 'optional',
          if (a.isVariadic) 'variadic',
          if (a.defaultValue != null) 'default=${a.defaultValue}',
        ];
        final attrsTail = attrs.isEmpty ? '' : '   [${attrs.join(', ')}]';
        final desc =
            a.description == null ? '' : '\n             ${a.description}';
        stdout.writeln('  ${a.name.padRight(10)} $attrsTail$desc');
      }
      stdout.writeln('');
    }
    if (parser.options.isNotEmpty) {
      stdout.writeln(ConsoleStyle.info('Options:'));
      stdout.writeln(
        parser.usage.replaceAll(RegExp(r'^', multiLine: true), '  '),
      );
    }
  }
}
