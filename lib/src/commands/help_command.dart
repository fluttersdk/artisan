import 'package:args/args.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/artisan_registry.dart';
import '../console/command_boot.dart';

/// `artisan help <command>` — prints full signature for a single command.
class HelpCommand extends ArtisanCommand {
  HelpCommand(this._registry);

  final ArtisanRegistry _registry;

  @override
  String get name => 'help';

  @override
  String get description => 'Show detailed help for a single command.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final target = ctx.input.argument(0);
    if (target == null || target.isEmpty) {
      ctx.output.error('Usage: artisan help <command-name>');
      return 1;
    }
    final command = _registry.find(target);
    if (command == null) {
      ctx.output.error('Unknown command: $target. Try `artisan list`.');
      return 1;
    }
    final parser = ArgParser();
    command.configure(parser);
    final signature = command.parsedSignature;

    final argsHint = signature == null
        ? '[arguments]'
        : signature.arguments.map((a) {
            final base = a.isOptional ? '[${a.name}]' : '<${a.name}>';
            return a.isVariadic ? '$base...' : base;
          }).join(' ');

    ctx.output.info('Description:');
    ctx.output.writeln('  ${command.description}');
    ctx.output.writeln('');
    ctx.output.info('Usage:');
    ctx.output.writeln('  artisan ${command.name} [options] $argsHint');
    ctx.output.writeln('');
    ctx.output.info('Boot mode:');
    ctx.output.writeln('  ${command.boot.name}');
    if (signature != null && signature.arguments.isNotEmpty) {
      ctx.output.writeln('');
      ctx.output.info('Arguments:');
      for (final a in signature.arguments) {
        final attrs = <String>[
          if (a.isOptional) 'optional',
          if (a.isVariadic) 'variadic',
          if (a.defaultValue != null) 'default=${a.defaultValue}',
        ];
        final attrsTail = attrs.isEmpty ? '' : '  [${attrs.join(', ')}]';
        ctx.output.writeln('  ${a.name.padRight(12)}$attrsTail');
        if (a.description != null) {
          ctx.output.writeln('              ${a.description}');
        }
      }
    }
    if (parser.options.isNotEmpty) {
      ctx.output.writeln('');
      ctx.output.info('Options:');
      ctx.output.writeln(
        parser.usage.replaceAll(RegExp(r'^', multiLine: true), '  '),
      );
    }
    return 0;
  }
}
