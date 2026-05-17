import 'package:fluttersdk_artisan/artisan.dart';

/// Single optional positional argument + boolean flag.
/// `artisan db:seed` → seeds every table.
/// `artisan db:seed users --fresh` → wipes then seeds the `users` table.
class DbSeedCommand extends ArtisanCommand {
  @override
  String get signature =>
      'db:seed {table? : Table to seed (omit for all tables)} '
      '{--fresh : Truncate the table(s) before seeding}';

  @override
  String get description => 'Seed the database with factory data.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final table = ctx.input.argument('table');
    final fresh = ctx.input.option('fresh') as bool;

    if (fresh) ctx.output.warning('--fresh given; truncating before seed.');
    ctx.output.info(
      table == null
          ? 'Seeding every registered table.'
          : 'Seeding table=$table.',
    );
    ctx.output.success('Seed done.');
    return 0;
  }
}
