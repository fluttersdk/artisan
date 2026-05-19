import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../tinker/tinker.dart';
import '../tinker/tinker_formatter.dart';

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
  String get signature => 'tinker '
      '{--eval= : Evaluate a single Dart expression in the running app, '
      'print the formatted result on stdout, and exit. When set, REPL is '
      'skipped. Pipe-friendly: `dart run artisan tinker --eval "1+1"`.}';

  @override
  String get description =>
      'Connected REPL into the running Flutter app (Dart expression evaluation via VM Service).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. One-shot eval branch ; bypass REPL when --eval is supplied. Used by
    //    scripts and pipelines that want the evaluated value without the
    //    `>>>` prompt or "Tinker connected" / "Tinker session ended" chatter.
    final eval = (ctx.input.option('eval') ?? '').trim();
    if (eval.isNotEmpty) {
      try {
        final result = await ctx.evaluate(eval);
        ctx.output.writeln(formatTinkerResult(result, casters: Tinker.casters));
        return 0;
      } catch (e) {
        ctx.output.error('$e');
        return 1;
      }
    }

    // 2. REPL mode (default) ; read-eval-print loop until Ctrl+D / exit / quit.
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
        ctx.output.writeln(formatTinkerResult(result, casters: Tinker.casters));
      } catch (e) {
        ctx.output.error('$e');
      }
    }
    ctx.output.writeln('');
    ctx.output.info('Tinker session ended.');
    return 0;
  }
}
