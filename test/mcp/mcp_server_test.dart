import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// In-memory stub of [VmServiceClient] that records calls and replays canned
/// responses keyed by extension method name.
///
/// Production code never touches a real isolate during tests; we substitute
/// the whole VM Service surface via constructor injection so the McpServer
/// flow can be exercised end-to-end without spawning Flutter.
class _StubVmServiceClient extends VmServiceClient {
  _StubVmServiceClient({
    Map<String, Object?>? responses,
    this.failOnConnect = false,
  })  : responses = responses ?? <String, Object?>{},
        super('ws://stub-only/');

  static const _stubIsolateId = 'isolate-stub';

  final Map<String, Object?> responses;
  final bool failOnConnect;

  /// Every `callServiceExtension` invocation captured in arrival order.
  final List<({String method, String isolateId, Map<String, dynamic>? params})>
      calls = [];

  /// Set to true after [connect] is called at least once.
  bool didConnect = false;

  @override
  Future<void> connect() async {
    if (failOnConnect) {
      throw StateError('stub connect failure');
    }
    didConnect = true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<String> getMainIsolateId() async => _stubIsolateId;

  @override
  Future<T> callServiceExtension<T>(
    String method, {
    required String isolateId,
    Map<String, dynamic>? params,
  }) async {
    calls.add((method: method, isolateId: isolateId, params: params));
    if (!responses.containsKey(method)) {
      throw StateError('stub has no canned response for $method');
    }
    return responses[method] as T;
  }
}

/// Provider double that returns a fixed list of MCP tool descriptors.
class _FakeMcpProvider extends ArtisanServiceProvider {
  _FakeMcpProvider({required this.providerName, required this.tools});

  @override
  final String providerName;
  final List<McpToolDescriptor> tools;

  @override
  List<ArtisanCommand> commands() => const [];

  @override
  List<McpToolDescriptor> mcpTools() => tools;
}

/// Builds the descriptor + provider pair without repeating the boilerplate
/// per test.
McpToolDescriptor _tool(
  String name, {
  String? extensionMethod,
  Map<String, dynamic>? inputSchema,
}) =>
    McpToolDescriptor(
      name: name,
      description: 'Test tool $name.',
      inputSchema: inputSchema ?? const {'type': 'object', 'properties': {}},
      extensionMethod: extensionMethod ?? 'ext.test.$name',
    );

/// Wires the server + a real dart_mcp client around an in-memory channel pair
/// so tests drive the server through its true public protocol surface.
///
/// Returns the live [ServerConnection]; teardown is the test's responsibility
/// (the harness shuts both ends down via [_TestHarness.dispose]).
class _TestHarness {
  _TestHarness._({
    required this.server,
    required this.connection,
    required this.client,
    required this.stub,
  });

  final McpServer server;
  final ServerConnection connection;
  final MCPClient client;
  final _StubVmServiceClient stub;

  static Future<_TestHarness> build({
    required ArtisanRegistry registry,
    required McpFilterConfig filter,
    Map<String, Object?>? stubResponses,
    bool stubFailOnConnect = false,
    Map<String, dynamic>? stateOverride,
  }) async {
    // 1. Two paired channels: one for the server (super.fromStreamChannel),
    //    one for the client (connectServer).
    final controller = StreamChannelController<String>(sync: true);

    // 2. Stub the VM Service + state reader so initialize is hermetic.
    final stub = _StubVmServiceClient(
      responses: stubResponses,
      failOnConnect: stubFailOnConnect,
    );
    final defaultState = <String, dynamic>{
      'vmServiceUri': 'ws://stub-only/',
      'pid': 12345,
    };

    final server = McpServer.test(
      channel: controller.local,
      registry: registry,
      filter: filter,
      vmClientFactory: (_) => stub,
      stateReader: () async => stateOverride ?? defaultState,
    );

    // 3. Drive the server with a real client over the foreign side.
    final client = MCPClient(
      Implementation(name: 'mcp_server_test', version: '1.0.0'),
    );
    final connection = client.connectServer(controller.foreign);
    final init = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: ClientCapabilities(),
        clientInfo: Implementation(
          name: 'mcp_server_test_client',
          version: '1.0.0',
        ),
      ),
    );
    expect(init.protocolVersion, ProtocolVersion.latestSupported);
    connection.notifyInitialized();
    // Yield so notifications/initialized reaches the server before tests
    // start asserting `tools/list`.
    await Future<void>.delayed(Duration.zero);

    return _TestHarness._(
      server: server,
      connection: connection,
      client: client,
      stub: stub,
    );
  }

  Future<void> dispose() async {
    await connection.shutdown();
    await client.shutdown();
    await server.shutdown();
  }
}

void main() {
  group('McpServer.initialize', () {
    test('empty registry produces a tools/list of zero tools', () async {
      final registry = ArtisanRegistry();
      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);

      final result = await harness.connection.listTools();

      expect(result.tools, isEmpty);
    });

    test('registers every surviving tool from the registry', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [
              _tool('dusk_snap', extensionMethod: 'ext.dusk.snap'),
              _tool('dusk_tap', extensionMethod: 'ext.dusk.tap'),
            ],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);

      final result = await harness.connection.listTools();

      expect(result.tools.map((t) => t.name), ['dusk_snap', 'dusk_tap']);
    });

    test('keeps capabilities.tools.listChanged at the library default true',
        () async {
      final registry = ArtisanRegistry();
      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);

      // ToolsSupport.initialize sets listChanged = true unconditionally; our
      // override must not flip it back to false (Oracle C1 revise: honest
      // capability advertisement).
      expect(harness.connection.serverCapabilities.tools?.listChanged, isTrue);
    });

    test('connects the VM Service client during initialize', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [_tool('dusk_snap')],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);

      expect(harness.stub.didConnect, isTrue);
    });

    test('initialize fails when state.json has no vmServiceUri', () async {
      // VM Service URI unknown -> we cannot dispatch tool calls. Surface a
      // clear error during initialize rather than registering tools that
      // would later fail with "stub connect failure".
      //
      // Across the JSON-RPC boundary the `StateError` arrives at the client
      // as an `RpcException` whose message embeds the original `toString()`,
      // so we assert on the message text (the contract guarantee) rather
      // than the exception type (which dart_mcp owns).
      final registry = ArtisanRegistry();

      await expectLater(
        _TestHarness.build(
          registry: registry,
          filter: McpFilterConfig.empty(),
          stateOverride: const <String, dynamic>{},
        ),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains('vmServiceUri'),
            'error message mentions vmServiceUri',
          ),
        ),
      );
    });
  });

  group('McpServer filter application', () {
    test('package deny removes every tool from that provider', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [_tool('dusk_snap'), _tool('dusk_tap')],
          ),
        )
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_telescope',
            tools: [_tool('telescope_tail'), _tool('telescope_http')],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: const McpFilterConfig(
          packagesAllow: null,
          packagesDeny: {'fluttersdk_telescope'},
          toolsAllow: null,
          toolsDeny: {},
        ),
      );
      addTearDown(harness.dispose);

      final result = await harness.connection.listTools();

      expect(
        result.tools.map((t) => t.name),
        ['dusk_snap', 'dusk_tap'],
      );
    });

    test('tool deny removes the matching tool BEFORE registerTool', () async {
      // Behaviour proof: a denied tool returns a "no tool registered" error
      // from dart_mcp's CallTool dispatcher, not our dispatch try/catch.
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [_tool('dusk_snap'), _tool('dusk_tap')],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: const McpFilterConfig(
          packagesAllow: null,
          packagesDeny: {},
          toolsAllow: null,
          toolsDeny: {'dusk_snap'},
        ),
      );
      addTearDown(harness.dispose);

      final result = await harness.connection.listTools();
      expect(result.tools.map((t) => t.name), ['dusk_tap']);

      final callResult =
          await harness.connection.callTool(CallToolRequest(name: 'dusk_snap'));
      expect(callResult.isError, isTrue);
      expect(
        (callResult.content.single as TextContent).text,
        contains('No tool registered'),
      );
      // The stub was never asked to dispatch the denied tool.
      expect(harness.stub.calls.where((c) => c.method == 'ext.dusk.snap'),
          isEmpty);
    });
  });

  group('McpServer tools/call dispatch', () {
    test('forwards to the correct extensionMethod with the request arguments',
        () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [_tool('dusk_snap', extensionMethod: 'ext.dusk.snap')],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
        stubResponses: const {
          'ext.dusk.snap': {'yaml': '- node'},
        },
      );
      addTearDown(harness.dispose);

      final callResult = await harness.connection.callTool(
        CallToolRequest(name: 'dusk_snap', arguments: const {}),
      );

      expect(harness.stub.calls.single.method, 'ext.dusk.snap');
      expect(harness.stub.calls.single.isolateId, 'isolate-stub');
      expect(callResult.isError, anyOf(isNull, isFalse));
      final text = (callResult.content.single as TextContent).text;
      expect(jsonDecode(text), {'yaml': '- node'});
    });

    test('wraps dispatch exceptions in CallToolResult.isError=true', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [_tool('dusk_snap', extensionMethod: 'ext.dusk.snap')],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
        // No canned response -> stub throws StateError on dispatch.
      );
      addTearDown(harness.dispose);

      final callResult =
          await harness.connection.callTool(CallToolRequest(name: 'dusk_snap'));

      expect(callResult.isError, isTrue);
      expect(
        (callResult.content.single as TextContent).text,
        contains('### Error'),
      );
    });

    test('inputSchema validation rejects calls missing a required arg',
        () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'magic_tinker',
            tools: [
              _tool(
                'tinker_eval',
                extensionMethod: 'ext.tinker.evaluate',
                inputSchema: const {
                  'type': 'object',
                  'properties': {
                    'ref': {'type': 'string'},
                  },
                  'required': ['ref'],
                },
              ),
            ],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);

      final callResult = await harness.connection
          .callTool(CallToolRequest(name: 'tinker_eval', arguments: const {}));

      expect(callResult.isError, isTrue);
      // Stub was never reached because dart_mcp short-circuited on the
      // missing required arg.
      expect(harness.stub.calls, isEmpty);
    });
  });
}
