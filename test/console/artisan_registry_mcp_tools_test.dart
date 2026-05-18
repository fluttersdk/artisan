import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanRegistry MCP tool collection', () {
    test(
        'registerMcpToolsFor with a single provider exposing two unique tools '
        'registers both into mcpTools', () {
      final registry = ArtisanRegistry();
      final provider = _FakeMcpProvider('dusk', const <McpToolDescriptor>[
        McpToolDescriptor(
          name: 'dusk_snap',
          description: 'Capture a semantics snapshot.',
          inputSchema: <String, dynamic>{'type': 'object'},
          extensionMethod: 'ext.dusk.snap',
        ),
        McpToolDescriptor(
          name: 'dusk_tap',
          description: 'Tap a widget by ref.',
          inputSchema: <String, dynamic>{'type': 'object'},
          extensionMethod: 'ext.dusk.tap',
        ),
      ]);

      registry.registerMcpToolsFor(provider);

      expect(registry.mcpTools, hasLength(2));
      expect(
        registry.mcpTools.map((t) => t.name).toList(),
        containsAll(<String>['dusk_snap', 'dusk_tap']),
      );
    });

    test(
        'registerMcpToolsFor throws ArtisanMcpToolCollisionException when two '
        'providers register the same tool name; toString names both providers',
        () {
      final registry = ArtisanRegistry();
      final first = _FakeMcpProvider('dusk', const <McpToolDescriptor>[
        McpToolDescriptor(
          name: 'shared_tool',
          description: 'first',
          inputSchema: <String, dynamic>{'type': 'object'},
          extensionMethod: 'ext.dusk.shared',
        ),
      ]);
      final second = _FakeMcpProvider('telescope', const <McpToolDescriptor>[
        McpToolDescriptor(
          name: 'shared_tool',
          description: 'second',
          inputSchema: <String, dynamic>{'type': 'object'},
          extensionMethod: 'ext.telescope.shared',
        ),
      ]);

      registry.registerMcpToolsFor(first);

      try {
        registry.registerMcpToolsFor(second);
        fail('expected ArtisanMcpToolCollisionException');
      } on ArtisanMcpToolCollisionException catch (e) {
        final msg = e.toString();
        expect(msg, contains('shared_tool'));
        expect(msg, contains('dusk'));
        expect(msg, contains('telescope'));
      }
    });

    test(
        'registerMcpToolsFor is a clean no-op when the provider returns an '
        'empty mcpTools() list (default-empty providers stay safe)', () {
      final registry = ArtisanRegistry();
      final provider = _FakeMcpProvider('silent', const <McpToolDescriptor>[]);

      registry.registerMcpToolsFor(provider);

      expect(registry.mcpTools, isEmpty);
    });
  });
}

class _FakeMcpProvider extends ArtisanServiceProvider {
  _FakeMcpProvider(this._name, this._tools);
  final String _name;
  final List<McpToolDescriptor> _tools;

  @override
  String get providerName => _name;

  @override
  List<ArtisanCommand> commands() => const <ArtisanCommand>[];

  @override
  List<McpToolDescriptor> mcpTools() => _tools;
}
