import 'package:fluttersdk_artisan/artisan.dart';

/// Third-party command providers registered alongside the auto-discovered
/// commands from `lib/app/commands/`.
///
/// You do NOT need to list app-level commands here — drop a `.dart` file
/// under `lib/app/commands/` (or run `artisan make:command Foo`) and they
/// auto-register via `lib/app/commands/_index.g.dart`.
///
/// Use this list for ServiceProvider-shipped commands from external pub
/// packages (`fluttersdk_dusk`, `fluttersdk_telescope`, `magic`, ...).
/// Each provider contributes a namespaced command set to the unified
/// `artisan` binary.
///
/// Pure-Dart only — no Flutter imports. The wrapper runs under `dart run`,
/// which cannot load `dart:ui`.
final List<ArtisanServiceProvider Function()>
artisanProviders = <ArtisanServiceProvider Function()>[
  // Example: DuskArtisanProvider.new (from package:fluttersdk_dusk/cli.dart)
];
