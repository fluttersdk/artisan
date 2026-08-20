import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanCommand', () {
    test('exposes name, description, boot from a concrete subclass', () {
      final command = _NoOpCommand();

      expect(command.name, 'noop');
      expect(command.description, 'A no-op command for tests.');
      expect(command.boot, CommandBoot.none);
    });

    test('configure default is a no-op (parser remains empty)', () {
      final command = _NoOpCommand();
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options, isEmpty);
    });

    test('handle returns the value the subclass produces', () async {
      final command = _NoOpCommand();
      final ctx = ArtisanContext.bare(
        MapInput(const {}),
        BufferedOutput(),
      );

      final code = await command.handle(ctx);

      expect(code, 0);
    });

    test('subclass override of configure registers flags', () {
      final command = _ConfigCommand();
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options.containsKey('force'), isTrue);
    });

    test('a command with no name is refused with a kebab-case suggestion', () {
      // The message is the whole value of the check: an author who forgot
      // `name` gets the line to paste rather than a bare "override name".
      expect(
        () => _MakeFancyThingCommand().name,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('make-fancy-thing'),
          ),
        ),
      );
    });

    test('a single-word class name suggests it without separators', () {
      expect(
        () => _StatusCommand().name,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('status'),
          ),
        ),
      );
    });
  });
}

class _NoOpCommand extends ArtisanCommand {
  @override
  String get name => 'noop';

  @override
  String get description => 'A no-op command for tests.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _ConfigCommand extends ArtisanCommand {
  @override
  String get name => 'cfg';

  @override
  String get description => 'Configures a force flag.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    parser.addFlag('force', negatable: false);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

/// Two commands that declare no `name`, so both fall through to the
/// class-name derivation.
class _MakeFancyThingCommand extends ArtisanCommand {
  @override
  String get description => 'derives its name from the class';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _StatusCommand extends ArtisanCommand {
  @override
  String get description => 'derives its name from the class';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}
