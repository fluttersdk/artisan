import 'package:fluttersdk_artisan/artisan.dart';

/// Variadic positional + option-with-default. Showcases the `*` modifier.
/// `artisan mail:digest alice@x.com bob@x.com` → sends to two users.
/// `artisan mail:digest alice@x.com --queue=high` → routes via the
/// `high` queue.
///
/// NOTE: variadic args land in `ArgResults.rest` as separate entries;
/// `ctx.input.argument('users')` returns the FIRST one for the named
/// position. Use `ctx.input.argument(0)`, `ctx.input.argument(1)`, etc.
/// to iterate the full rest.
class MailDigestCommand extends ArtisanCommand {
  @override
  String get signature =>
      'mail:digest {users* : One or more recipient email addresses} '
      '{--queue=default : Queue to dispatch on}';

  @override
  String get description =>
      'Send the daily digest email to one or more recipients.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final recipients = <String>[];
    for (var i = 0; ; i++) {
      final v = ctx.input.argument(i);
      if (v == null) break;
      recipients.add(v);
    }
    if (recipients.isEmpty) {
      ctx.output.error('At least one recipient is required.');
      return 1;
    }
    final queue = ctx.input.option('queue') as String;
    ctx.output.info(
      'Dispatching digest to ${recipients.length} recipient(s) on queue "$queue":',
    );
    for (final r in recipients) {
      ctx.output.writeln('  -> $r');
    }
    ctx.output.success('Queued.');
    return 0;
  }
}
