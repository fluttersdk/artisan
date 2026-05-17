import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ListCommand', () {
    late ArtisanRegistry registry;

    setUp(() {
      registry = ArtisanRegistry();
    });

    test('boot=none, name=list', () {
      final command = ListCommand(registry);

      expect(command.name, 'list');
      expect(command.boot, CommandBoot.none);
    });

    test('handle returns 0 even for empty registry', () async {
      final command = ListCommand(registry);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 0);
      expect(output.content, contains('Available commands (0)'));
    });

    test('lists root commands by name', () async {
      registry.register(_FakeCommand('start', 'Start the app'));
      registry.register(_FakeCommand('stop', 'Stop the app'));
      final command = ListCommand(registry);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      expect(output.content, contains('start'));
      expect(output.content, contains('stop'));
    });

    test('groups colon-namespaced commands under a heading', () async {
      registry.register(_FakeCommand('dusk:snap', 'Snap'));
      registry.register(_FakeCommand('dusk:tap', 'Tap'));
      registry.register(_FakeCommand('start', 'Start'));
      final command = ListCommand(registry);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      expect(output.content, contains('dusk'));
      expect(output.content, contains('dusk:snap'));
      expect(output.content, contains('dusk:tap'));
    });

    test('configure is a no-op (no flags)', () {
      final command = ListCommand(registry);
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options, isEmpty);
    });
  });
}

class _FakeCommand extends ArtisanCommand {
  _FakeCommand(this._name, this._description);
  final String _name;
  final String _description;

  @override
  String get name => _name;

  @override
  String get description => _description;

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}
