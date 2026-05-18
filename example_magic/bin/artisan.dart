import 'dart:io';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic/cli.dart' show MagicArtisanProvider;
import '../lib/app/_plugins.g.dart' as plugins;

Future<void> main(List<String> args) async {
  exit(await runArtisan(args,
    baseProviders: [MagicArtisanProvider(), ...plugins.autoDiscoveredProviders()],
    delegateToConsumer: false,
  ));
}
