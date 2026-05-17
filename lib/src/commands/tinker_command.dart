import 'dart:io';

import 'package:vm_service/vm_service.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../tinker/tinker.dart';

/// `artisan tinker` — connected REPL into the running Flutter app.
///
/// Reads input lines from stdin, evaluates each as a Dart expression in the
/// running app's root library via VM Service evaluate RPC, pretty-prints the
/// result via [Tinker.casters] chain (fallback: built-in InstanceRef unwrap).
///
/// V1: basic prompt + evaluate loop. cli_repl integration + IsolateReload
/// autocomplete cache + history persistence deferred V1.x.
class TinkerCommand extends ArtisanCommand {
  @override
  String get name => 'tinker';

  @override
  String get description =>
      'Connected REPL into the running Flutter app (Dart expression evaluation via VM Service).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info('Tinker connected. Type expressions; Ctrl+D to exit.');
    while (true) {
      stdout.write('>>> ');
      final line = stdin.readLineSync();
      if (line == null) break;
      final input = line.trim();
      if (input.isEmpty) continue;
      if (input == 'exit' || input == 'quit') break;
      try {
        final result = await ctx.evaluate(input);
        ctx.output.writeln(_formatResult(result));
      } catch (e) {
        ctx.output.error('$e');
      }
    }
    ctx.output.writeln('');
    ctx.output.info('Tinker session ended.');
    return 0;
  }

  String _formatResult(Object? value) {
    for (final caster in Tinker.casters) {
      final formatted = caster(value);
      if (formatted != null) return formatted;
    }
    return _defaultFormat(value);
  }

  /// Best-effort pretty-print for the raw VM Service evaluate result.
  /// Unwraps [InstanceRef] into the value the user typed at the prompt
  /// instead of dumping the raw VM internal shape.
  String _defaultFormat(Object? value) {
    if (value == null) return 'null';
    if (value is InstanceRef) {
      // Primitive scalars carry their printed form on `valueAsString`.
      if (value.valueAsString != null) {
        final printed = value.valueAsString!;
        return value.kind == 'String' ? '"$printed"' : printed;
      }
      // Non-primitive InstanceRefs: tagged type hint.
      final className = value.classRef?.name ?? 'Instance';
      return '<$className#${value.id ?? '?'}>';
    }
    if (value is ErrorRef) return 'Error: ${value.message ?? value.id}';
    return value.toString();
  }
}
