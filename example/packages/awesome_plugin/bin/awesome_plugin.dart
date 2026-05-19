import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:awesome_plugin/cli.dart' show AwesomePluginArtisanProvider;

Future<void> main(List<String> args) async {
  exit(await runArtisan(
    args,
    baseProviders: [AwesomePluginArtisanProvider()],
    delegateToConsumer: false,
  ));
}
