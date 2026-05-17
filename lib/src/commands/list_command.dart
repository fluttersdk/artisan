import 'package:args/args.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/artisan_registry.dart';
import '../console/command_boot.dart';
import '../helpers/console_style.dart';

/// `artisan list` — prints every registered command grouped by `:` namespace.
class ListCommand extends ArtisanCommand {
  ListCommand(this._registry);

  final ArtisanRegistry _registry;

  @override
  String get name => 'list';

  @override
  String get description =>
      'List every registered command grouped by namespace.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {}

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final grouped = _registry.groupedByNamespace();
    ctx.output.writeln('');
    ctx.output.info('Available commands (${_registry.length}):');
    for (final entry in grouped.entries) {
      if (entry.key.isEmpty) {
        // Root commands first.
        for (final cmd in entry.value) {
          ctx.output.writeln('  ${cmd.name.padRight(28)} ${cmd.description}');
        }
      } else {
        ctx.output.writeln('');
        ctx.output.writeln(
          ' ${ConsoleStyle.yellow}${entry.key}${ConsoleStyle.reset}',
        );
        for (final cmd in entry.value) {
          ctx.output.writeln('  ${cmd.name.padRight(28)} ${cmd.description}');
        }
      }
    }
    return 0;
  }
}
