import 'package:fluttersdk_artisan/artisan.dart';

import '../app/commands/clean_cache.dart';

/// Consumer-side artisan provider list. The wrapper at `bin/artisan.dart`
/// expands this list into the registry alongside the 9 builtin commands
/// from fluttersdk_artisan.
///
/// Pure-Dart only — no Flutter imports. The wrapper runs under `dart run`,
/// which cannot load `dart:ui`.
final List<ArtisanServiceProvider Function()> artisanProviders = [
  ExampleArtisanProvider.new,
];

/// In-app provider that owns every command defined under `lib/app/commands/`.
/// For larger projects split into multiple providers per domain.
class ExampleArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'example';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[CleanCacheCommand()];
}
