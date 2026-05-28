/// Bug 3 contract regression net: plugin wrappers MUST pass collectMcpTools: true when dispatching mcp:serve. This file locks the substrate's default-false semantics so wrapper bugs surface here instead of in the wild.
library;

import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('runArtisan collectMcpTools + mcp:serve registry wiring', () {
    // -------------------------------------------------------------------------
    // Contract A (positive): collectMcpTools: true surfaces plugin tools
    // -------------------------------------------------------------------------

    test(
        'collectMcpTools:true registers plugin tools so tools/list contains '
        'fake_tool_a, fake_tool_b alongside substrate artisan_* tools',
        () async {
      // 1. Build the registry replicating the runArtisan standalone path with
      //    collectMcpTools: true.
      final registry = ArtisanRegistry();
      registry.registerAll(
        _substrateCommands(),
        providerName: 'fluttersdk_artisan',
      );
      final provider = _FakeProvider();
      registry.registerProvider(provider);
      registry.registerMcpToolsFor(provider); // collectMcpTools: true path

      // 2. Spin up an in-memory MCP channel pair so the full protocol surface
      //    is exercised without spawning a real process.
      final harness = await _McpHarness.build(registry: registry);
      addTearDown(harness.dispose);

      // 3. tools/list must include both plugin tools.
      final result = await harness.connection.listTools();
      final names = result.tools.map((t) => t.name).toList();

      expect(names, contains('fake_tool_a'));
      expect(names, contains('fake_tool_b'));

      // 4. Substrate artisan_* tools must still be present (verifies the
      //    substrate commands registered under providerName 'fluttersdk_artisan'
      //    surface through the artisan_* synthesis path in McpServer).
      expect(names.any((n) => n.startsWith('artisan_')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Contract B (negative / trap): collectMcpTools: false omits plugin tools
    // -------------------------------------------------------------------------

    test(
        'collectMcpTools:false (default) does NOT register plugin tools; '
        'tools/list has zero fake_* entries but substrate artisan_* tools remain',
        () async {
      // 1. Build the registry replicating the runArtisan standalone path with
      //    collectMcpTools: false (default). registerMcpToolsFor is never called.
      final registry = ArtisanRegistry();
      registry.registerAll(
        _substrateCommands(),
        providerName: 'fluttersdk_artisan',
      );
      final provider = _FakeProvider();
      registry.registerProvider(provider);
      // collectMcpTools: false (default), intentionally omit registerMcpToolsFor.

      // 2. Spin up an in-memory MCP channel pair.
      final harness = await _McpHarness.build(registry: registry);
      addTearDown(harness.dispose);

      // 3. tools/list must NOT include any fake_* tool.
      final result = await harness.connection.listTools();
      final names = result.tools.map((t) => t.name).toList();

      expect(names.any((n) => n.startsWith('fake_')), isFalse);

      // 4. Substrate artisan_* tools must still be present even without
      //    plugin MCP registration.
      expect(names.any((n) => n.startsWith('artisan_')), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// In-memory MCP harness (mirrors mcp_server_test.dart _TestHarness shape)
// ---------------------------------------------------------------------------

/// Wires [McpServer] + a [dart_mcp] client around a paired in-memory channel
/// so tests exercise the full MCP protocol without spawning a process.
class _McpHarness {
  _McpHarness._({
    required this.server,
    required this.connection,
    required this.client,
  });

  final McpServer server;
  final ServerConnection connection;
  final MCPClient client;

  static Future<_McpHarness> build({
    required ArtisanRegistry registry,
  }) async {
    // 1. Paired channels: local side drives the server, foreign side drives
    //    the client.
    final controller = StreamChannelController<String>(sync: true);

    // 2. Server with a no-op state reader (no live Flutter app needed for
    //    tools/list assertions). The vmClientFactory is supplied but the stub
    //    state reader returns an empty map so McpServer never calls connect().
    final server = McpServer.test(
      channel: controller.local,
      registry: registry,
      filter: McpFilterConfig.empty(),
      vmClientFactory: (wsUri) => VmServiceClient(wsUri),
      stateReader: () async => const <String, dynamic>{},
    );

    // 3. Connect a real MCP client over the foreign channel end.
    final client = MCPClient(
      Implementation(name: 'regression_net_client', version: '1.0.0'),
    );
    final connection = client.connectServer(controller.foreign);
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: ClientCapabilities(),
        clientInfo: Implementation(
          name: 'regression_net_client',
          version: '1.0.0',
        ),
      ),
    );
    connection.notifyInitialized();

    // Yield so the initialized notification reaches the server before any
    // tools/list call.
    await Future<void>.delayed(Duration.zero);

    return _McpHarness._(
      server: server,
      connection: connection,
      client: client,
    );
  }

  Future<void> dispose() async {
    await connection.shutdown();
    await client.shutdown();
    await server.shutdown();
  }
}

// ---------------------------------------------------------------------------
// Minimal substrate command set used to seed the registry in both tests
// ---------------------------------------------------------------------------

/// Returns the minimum substrate commands needed to verify that artisan_*
/// tools surface via McpServer's synthesis path. Avoids spinning up the full
/// 22-command builtin list (which would pull in live-FS commands).
List<ArtisanCommand> _substrateCommands() => <ArtisanCommand>[
      _StubCommand('start', 'Boot flutter run -d <device> detached.'),
      _StubCommand('doctor', 'Run environment preflight checks.'),
    ];

/// Minimal no-op command that satisfies [ArtisanCommand] without live I/O.
class _StubCommand extends ArtisanCommand {
  _StubCommand(this._name, this._description);

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

// ---------------------------------------------------------------------------
// Test-private fake provider
// ---------------------------------------------------------------------------

/// Minimal [ArtisanServiceProvider] contributing two unique MCP tool
/// descriptors for the regression net assertions.
class _FakeProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'fake_package';

  @override
  List<ArtisanCommand> commands() => const <ArtisanCommand>[];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
        McpToolDescriptor(
          name: 'fake_tool_a',
          description: 'Fake tool A for contract regression net.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
          extensionMethod: 'ext.fake.a',
        ),
        McpToolDescriptor(
          name: 'fake_tool_b',
          description: 'Fake tool B for contract regression net.',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
          extensionMethod: 'ext.fake.b',
        ),
      ];
}
