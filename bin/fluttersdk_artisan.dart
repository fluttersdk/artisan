import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// `dart run fluttersdk_artisan <cmd>` — universal entrypoint.
///
/// Thin wrapper around [runArtisan]. The helper owns auto-delegation,
/// builtin registration, base-provider wiring, auto-discovered provider
/// wiring, and the exit-code contract; see its docs for the full
/// behavior. This binary registers no extra providers — it is the
/// pure-substrate path that ships with `fluttersdk_artisan` itself.
Future<void> main(List<String> args) async {
  exit(await runArtisan(args));
}
