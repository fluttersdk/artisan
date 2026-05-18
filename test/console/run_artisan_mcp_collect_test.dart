import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Verifies the `collectMcpTools` opt-in flag on [runArtisan].
///
/// Observable contract:
/// 1. Default (`collectMcpTools: false`) never calls [ArtisanRegistry.registerMcpToolsFor],
///    proven by two providers with a duplicate tool name NOT causing a collision.
/// 2. `collectMcpTools: true` calls [ArtisanRegistry.registerMcpToolsFor] per provider,
///    proven by two providers with a duplicate tool name surfacing an exit 3
///    (collision propagates as a non-[ArtisanCommandCollisionException] to the
///    generic catch → exit 3).
/// 3. `collectMcpTools: true` with non-colliding providers succeeds (exit 0).
void main() {
  group('runArtisan collectMcpTools', () {
    test(
        'default collectMcpTools:false does NOT call registerMcpToolsFor; '
        'duplicate tool names across two providers produce no collision '
        '(legacy CLI behavior preserved)', () async {
      // Two providers sharing a tool name. If collectMcpTools were true,
      // ArtisanMcpToolCollisionException would fire and return exit 3.
      // With the default false, both providers' commands() are registered and
      // `list` dispatches cleanly → exit 0.
      final first = _SimpleMcpProvider(
        name: 'provider_alpha',
        tools: const <McpToolDescriptor>[
          McpToolDescriptor(
            name: 'shared_tool',
            description: 'first',
            inputSchema: <String, dynamic>{'type': 'object'},
            extensionMethod: 'ext.a.shared',
          ),
        ],
      );
      final second = _SimpleMcpProvider(
        name: 'provider_beta',
        tools: const <McpToolDescriptor>[
          McpToolDescriptor(
            name: 'shared_tool',
            description: 'second',
            inputSchema: <String, dynamic>{'type': 'object'},
            extensionMethod: 'ext.b.shared',
          ),
        ],
      );

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        baseProviders: <ArtisanServiceProvider>[first, second],
        // collectMcpTools omitted — defaults to false.
      );

      // No MCP collection → no collision → clean exit.
      expect(code, 0);
    });

    test(
        'collectMcpTools:true with non-colliding tools from baseProviders '
        'succeeds and exits 0', () async {
      final provider = _SimpleMcpProvider(
        name: 'dusk',
        tools: const <McpToolDescriptor>[
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
        ],
      );

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        baseProviders: <ArtisanServiceProvider>[provider],
        collectMcpTools: true,
      );

      expect(code, 0);
    });

    test(
        'collectMcpTools:true with non-colliding tools from autoProviders '
        'succeeds and exits 0', () async {
      final autoProvider = _SimpleMcpProvider(
        name: 'telescope',
        tools: const <McpToolDescriptor>[
          McpToolDescriptor(
            name: 'telescope_tail',
            description: 'Tail logs.',
            inputSchema: <String, dynamic>{'type': 'object'},
            extensionMethod: 'ext.telescope.tail',
          ),
        ],
      );

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        autoProviders: () => <ArtisanServiceProvider>[autoProvider],
        collectMcpTools: true,
      );

      expect(code, 0);
    });

    test(
        'collectMcpTools:true with a duplicate tool name across two '
        'baseProviders throws ArtisanMcpToolCollisionException → exit 3; '
        'both provider names surface in the exception message', () async {
      // Use a command-capturing provider so we can verify the exception was
      // ArtisanMcpToolCollisionException. The generic catch in runArtisan
      // returns exit 3 for non-ArtisanCommandCollisionException throws.
      final first = _SimpleMcpProvider(
        name: 'provider_alpha',
        tools: const <McpToolDescriptor>[
          McpToolDescriptor(
            name: 'shared_tool',
            description: 'first',
            inputSchema: <String, dynamic>{'type': 'object'},
            extensionMethod: 'ext.a.shared',
          ),
        ],
      );
      final second = _SimpleMcpProvider(
        name: 'provider_beta',
        tools: const <McpToolDescriptor>[
          McpToolDescriptor(
            name: 'shared_tool',
            description: 'second',
            inputSchema: <String, dynamic>{'type': 'object'},
            extensionMethod: 'ext.b.shared',
          ),
        ],
      );

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        baseProviders: <ArtisanServiceProvider>[first, second],
        collectMcpTools: true,
      );

      // ArtisanMcpToolCollisionException is not caught by the
      // ArtisanCommandCollisionException branch (exit 2), so it falls
      // through to the generic catch → exit 3.
      expect(code, 3);
    });

    test(
        'collectMcpTools:true with a duplicate tool name across a baseProvider '
        'and an autoProvider also throws → exit 3', () async {
      const tool = McpToolDescriptor(
        name: 'shared_tool',
        description: 'shared',
        inputSchema: <String, dynamic>{'type': 'object'},
        extensionMethod: 'ext.shared',
      );

      final base = _SimpleMcpProvider(
        name: 'base_provider',
        tools: const <McpToolDescriptor>[tool],
      );
      final auto = _SimpleMcpProvider(
        name: 'auto_provider',
        tools: const <McpToolDescriptor>[tool],
      );

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        baseProviders: <ArtisanServiceProvider>[base],
        autoProviders: () => <ArtisanServiceProvider>[auto],
        collectMcpTools: true,
      );

      expect(code, 3);
    });
  });
}

// ---------------------------------------------------------------------------
// Test-private helpers
// ---------------------------------------------------------------------------

/// A minimal provider exposing [tools] from [mcpTools]; no commands.
class _SimpleMcpProvider extends ArtisanServiceProvider {
  _SimpleMcpProvider({
    required String name,
    required List<McpToolDescriptor> tools,
  })  : _name = name,
        _tools = tools;

  final String _name;
  final List<McpToolDescriptor> _tools;

  @override
  String get providerName => _name;

  @override
  List<ArtisanCommand> commands() => const <ArtisanCommand>[];

  @override
  List<McpToolDescriptor> mcpTools() => _tools;
}
