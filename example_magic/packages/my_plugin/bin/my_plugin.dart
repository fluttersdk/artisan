import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:my_plugin/cli.dart' show MyPluginArtisanProvider;

Future<void> main(List<String> args) async {
  exit(await runArtisan(
    args,
    baseProviders: [MyPluginArtisanProvider()],
    delegateToConsumer: false,
  ));
}
