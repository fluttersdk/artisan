import '../console/artisan_generator_command.dart';

/// `artisan make:command MyCommand` — scaffolds a new ArtisanCommand subclass.
class MakeCommandCommand extends ArtisanGeneratorCommand {
  @override
  String get name => 'make:command';

  @override
  String get description =>
      'Scaffold a new ArtisanCommand subclass under lib/app/commands/.';

  @override
  String getStub() => 'artisan_command';

  @override
  String getDefaultNamespace() => 'lib/app/commands';
}
