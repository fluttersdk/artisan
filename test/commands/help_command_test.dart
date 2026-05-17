import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('HelpCommand', () {
    late ArtisanRegistry registry;

    setUp(() {
      registry = ArtisanRegistry();
      registry.register(_FakeCommand('greet', 'Say hello'));
    });

    test('declared metadata is none-boot, name=help', () {
      final command = HelpCommand(registry);

      expect(command.name, 'help');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('returns 1 when no target name given', () async {
      final command = HelpCommand(registry);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content, contains('Usage:'));
    });

    test('returns 1 when target command not found', () async {
      final command = HelpCommand(registry);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const {}, positional: <String>['nope']),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content, contains('Unknown command: nope'));
    });

    test('prints description, usage, boot mode for a registered command',
        () async {
      final command = HelpCommand(registry);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const {}, positional: <String>['greet']),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0);
      expect(output.content, contains('Say hello'));
      expect(output.content, contains('artisan greet'));
      expect(output.content, contains('none'));
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
