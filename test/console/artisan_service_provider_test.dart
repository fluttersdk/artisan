import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanServiceProvider', () {
    test('default providerName equals the runtime class name', () {
      final provider = _UnnamedProvider();

      expect(provider.providerName, '_UnnamedProvider');
    });

    test('commands() returns the supplied list', () {
      final provider = _NamedProvider('demo', <ArtisanCommand>[
        _StubCommand('one'),
        _StubCommand('two'),
      ]);

      expect(provider.commands(), hasLength(2));
      expect(provider.providerName, 'demo');
    });

    test('plays nicely with ArtisanRegistry.registerProvider', () {
      final registry = ArtisanRegistry();
      final provider = _NamedProvider('p', <ArtisanCommand>[
        _StubCommand('one'),
      ]);

      registry.registerProvider(provider);

      expect(registry.find('one'), isNotNull);
    });

    test('returning [] is valid', () {
      final provider = _NamedProvider('empty', const <ArtisanCommand>[]);

      expect(provider.commands(), isEmpty);
    });

    test('mcpTools() defaults to an empty list', () {
      expect(_AnonymousProvider().mcpTools(), isEmpty);
    });
  });
}

/// Minimal provider with no overrides; exercises the default implementations.
class _AnonymousProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() => const <ArtisanCommand>[];
}

class _UnnamedProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() => const <ArtisanCommand>[];
}

class _NamedProvider extends ArtisanServiceProvider {
  _NamedProvider(this._name, this._commands);
  final String _name;
  final List<ArtisanCommand> _commands;

  @override
  String get providerName => _name;

  @override
  List<ArtisanCommand> commands() => _commands;
}

class _StubCommand extends ArtisanCommand {
  _StubCommand(this._name);
  final String _name;

  @override
  String get name => _name;

  @override
  String get description => 'stub $_name';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}
