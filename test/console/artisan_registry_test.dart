import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanRegistry', () {
    test('register adds a command lookup-able by name', () {
      final registry = ArtisanRegistry();
      final command = _FakeCommand('alpha');

      registry.register(command, providerName: 'test');

      expect(registry.find('alpha'), same(command));
    });

    test('find returns null when name unknown', () {
      final registry = ArtisanRegistry();
      expect(registry.find('does-not-exist'), isNull);
    });

    test('registerAll registers each command', () {
      final registry = ArtisanRegistry();
      final commands = <ArtisanCommand>[
        _FakeCommand('alpha'),
        _FakeCommand('beta'),
        _FakeCommand('gamma'),
      ];

      registry.registerAll(commands, providerName: 'test');

      expect(registry.all().length, 3);
      expect(registry.find('alpha'), isNotNull);
      expect(registry.find('beta'), isNotNull);
      expect(registry.find('gamma'), isNotNull);
    });

    test(
        'register throws ArtisanCommandCollisionException on duplicate name from different providers',
        () {
      final registry = ArtisanRegistry();
      registry.register(_FakeCommand('shared'), providerName: 'provider_a');

      expect(
        () => registry.register(_FakeCommand('shared'),
            providerName: 'provider_b'),
        throwsA(isA<ArtisanCommandCollisionException>()),
      );
    });

    test(
        'collision exception message names both the conflicting command and providers',
        () {
      final registry = ArtisanRegistry();
      registry.register(_FakeCommand('dusk:snap'), providerName: 'dusk');

      try {
        registry.register(_FakeCommand('dusk:snap'), providerName: 'telescope');
        fail('expected collision');
      } on ArtisanCommandCollisionException catch (e) {
        final msg = e.toString();
        expect(msg, contains('dusk:snap'));
        expect(msg, contains('dusk'));
        expect(msg, contains('telescope'));
      }
    });

    test('registerProvider expands provider.commands() into the registry', () {
      final registry = ArtisanRegistry();
      final provider = _FakeProvider('demo', [
        _FakeCommand('demo:a'),
        _FakeCommand('demo:b'),
      ]);

      registry.registerProvider(provider);

      expect(registry.find('demo:a'), isNotNull);
      expect(registry.find('demo:b'), isNotNull);
    });

    test('all() returns commands sorted alphabetically by name', () {
      final registry = ArtisanRegistry();
      registry.register(_FakeCommand('z'), providerName: 'p');
      registry.register(_FakeCommand('a'), providerName: 'p');
      registry.register(_FakeCommand('m'), providerName: 'p');

      expect(
        registry.all().map((c) => c.name).toList(),
        ['a', 'm', 'z'],
      );
    });

    test('groupedByNamespace splits on `:`, top-level under empty key', () {
      final registry = ArtisanRegistry();
      registry.register(_FakeCommand('start'), providerName: 'p');
      registry.register(_FakeCommand('dusk:snap'), providerName: 'p');
      registry.register(_FakeCommand('dusk:tap'), providerName: 'p');
      registry.register(_FakeCommand('telescope:tail'), providerName: 'p');

      final grouped = registry.groupedByNamespace();

      expect(grouped.keys, containsAll(<String>['dusk', 'telescope']));
      expect(grouped['dusk']!.length, 2);
      expect(grouped['telescope']!.length, 1);
    });

    test('override=true allows replacing an existing command', () {
      final registry = ArtisanRegistry();
      final first = _FakeCommand('shared');
      final second = _FakeCommand('shared');
      registry.register(first, providerName: 'a');

      registry.register(second, providerName: 'b', override: true);

      expect(registry.find('shared'), same(second));
    });
  });
}

class _FakeCommand extends ArtisanCommand {
  _FakeCommand(this._name);
  final String _name;

  @override
  String get name => _name;

  @override
  String get description => 'fake $_name';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _FakeProvider extends ArtisanServiceProvider {
  _FakeProvider(this._name, this._commands);
  final String _name;
  final List<ArtisanCommand> _commands;

  @override
  String get providerName => _name;

  @override
  List<ArtisanCommand> commands() => _commands;
}
