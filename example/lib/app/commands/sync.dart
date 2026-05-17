import 'package:fluttersdk_artisan/artisan.dart';

/// Demo command showcasing the Laravel-style signature DSL: a required
/// positional argument, an optional with default, a boolean flag, and a
/// value-bearing option with default + help text.
class SyncCommand extends ArtisanCommand {
  @override
  String get signature =>
      'sync:monitors {team : Team slug to reconcile} '
      '{scope=all : Subset filter (all|active|paused)} '
      '{--force : Skip the confirmation prompt} '
      '{--limit=50 : Maximum monitors to push per batch}';

  @override
  String get description =>
      "Reconcile a team's monitors with the upstream API.";

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final team = ctx.input.argument('team');
    final scope = ctx.input.argument('scope');
    final force = ctx.input.option('force') as bool;
    final limit = int.parse(ctx.input.option('limit') as String);

    if (team == null || team.isEmpty) {
      ctx.output.error('Missing required argument: team');
      return 1;
    }

    ctx.output.info('Reconciling team=$team scope=$scope (limit=$limit)');
    if (force) {
      ctx.output.warning('--force given; skipping confirmation.');
    }
    ctx.output.success('Sync done.');
    return 0;
  }
}
