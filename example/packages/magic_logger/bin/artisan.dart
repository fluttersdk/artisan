import 'dart:io';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_logger/cli.dart' show MagicLoggerArtisanProvider;

Future<void> main(List<String> args) async {
  exit(await runArtisan(
    args,
    baseProviders: [MagicLoggerArtisanProvider()],
    delegateToConsumer: false,
  ));
}
