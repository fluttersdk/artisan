import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart'
    show ErrorRef, InstanceRef, RPCError, Response, SentinelException;

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

  /// Connection-attempt count. The lazy-reconnect race guard test asserts
  /// this stays at 1 even under N concurrent dispatches starting from a
  /// null `_vmClient`.
  int connectCount = 0;

  @override
  Future<void> connect() async {
    connectCount++;
    if (failOnConnect) {
      throw StateError('stub connect failure');
    }
    // Yield once so concurrent waiters get a chance to interleave; without
    // this the test cannot exercise the race window.
    await Future<void>.delayed(Duration.zero);
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

  /// Every `evaluate` invocation captured in arrival order. The Step 4 RED
  /// tests assert on this tuple to confirm the new `dusk_evaluate` dispatch
  /// path routes the request's `expression` argument through to
  /// `VmServiceClient.evaluate` with the resolved isolate id.
  final List<({String isolateId, String expression})> evaluateCalls = [];

  /// Per-test script that produces the canned [Response] for the next
  /// [evaluate] call. Tests assign this to control the branch under test
  /// (InstanceRef success, ErrorRef value, SentinelException throw, or
  /// RPCError(113) throw). Default: a no-op `InstanceRef` that triggers the
  /// unconfigured-script failure mode.
  Response Function(String isolateId, String expression)? _evaluateScript;

  @override
  Future<Response> evaluate(String isolateId, String expression) async {
    evaluateCalls.add((isolateId: isolateId, expression: expression));
    final script = _evaluateScript;
    if (script == null) {
      throw StateError('stub has no _evaluateScript configured');
    }
    return script(isolateId, expression);
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
    Future<Map<String, dynamic>?> Function()? stateReader,
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
      stateReader: stateReader ?? () async => stateOverride ?? defaultState,
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

    test(
        'lazy-reconnect serializes via memoized future under concurrent dispatch',
        () async {
      // Race scenario: init runs with state.json absent (_vmClient stays
      // null + server stays online). state.json appears (user runs
      // `artisan start`). Two MCP tool calls arrive concurrently. Both see
      // _vmClient == null and trigger the lazy-reconnect branch in _dispatch.
      // The race guard MUST ensure the VmServiceClient factory runs exactly
      // once across the two concurrent dispatches (no leak).
      var stateRevealed = false;
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
        stubResponses: <String, Object?>{
          'ext.dusk.snap': <String, dynamic>{'ok': true},
        },
        stateReader: () async {
          // Return absent state during initialize; valid state on every
          // subsequent call (which is the lazy-reconnect path).
          if (!stateRevealed) {
            stateRevealed = true;
            return null;
          }
          return <String, dynamic>{
            'vmServiceUri': 'ws://stub-only/',
            'pid': 12345,
          };
        },
      );
      addTearDown(harness.dispose);

      // Sanity: initialize ran without connecting (state was absent).
      expect(harness.stub.connectCount, 0);

      // Fire two concurrent tool calls; both should hit the lazy-reconnect
      // branch with a null _vmClient.
      final results = await Future.wait([
        harness.connection.callTool(
          CallToolRequest(name: 'dusk_snap', arguments: const {}),
        ),
        harness.connection.callTool(
          CallToolRequest(name: 'dusk_snap', arguments: const {}),
        ),
      ]);

      // Both calls succeeded.
      expect(results.every((r) => r.isError != true), isTrue);
      // The race guard ran the factory exactly once even though both
      // dispatches needed the connection.
      expect(harness.stub.connectCount, 1);
      // Both dispatches reached the stub extension call.
      expect(harness.stub.calls, hasLength(2));
    });

    test('substrate commands surface as artisan_* MCP tools', () async {
      // The 9 allowlisted substrate commands MUST appear as MCP tools even
      // when no plugin providers are registered. This is the bootstrap path:
      // an MCP client (Claude Code) can call artisan_start BEFORE any
      // Flutter app is running.
      final registry = ArtisanRegistry();
      registry.registerAll(
        <ArtisanCommand>[
          _FakeSubstrateCommand(
              'start', 'Boot flutter run -d <device> detached.'),
          _FakeSubstrateCommand('doctor', 'Run environment preflight checks.'),
        ],
        providerName: 'fluttersdk_artisan',
      );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);

      final tools = await harness.connection.listTools();
      final names = tools.tools.map((t) => t.name).toList();
      expect(names, contains('artisan_start'));
      expect(names, contains('artisan_doctor'));
    });

    test('artisan_* tool dispatch runs command in-process + returns output',
        () async {
      final registry = ArtisanRegistry();
      registry.registerAll(
        <ArtisanCommand>[
          _FakeSubstrateCommand(
            'status',
            'Print JSON status.',
            onHandle: (ctx) async {
              ctx.output.info('{"running":false}');
              return 0;
            },
          ),
        ],
        providerName: 'fluttersdk_artisan',
      );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);

      final result = await harness.connection.callTool(
        CallToolRequest(name: 'artisan_status', arguments: const {}),
      );
      expect(result.isError, isFalse);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('# `artisan status` exit 0'));
      expect(text, contains('{"running":false}'));
    });

    test('initialize stays online when state.json has no vmServiceUri',
        () async {
      // V1 soft-fail policy: the MCP server stays connected even when no
      // Flutter app is running. Individual tool calls return an actionable
      // error at dispatch time so MCP clients (Claude Code, Cursor) can
      // survive the natural dev cycle of starting/stopping the app without
      // having to reconnect the server every time.
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
        stateOverride: const <String, dynamic>{},
      );
      addTearDown(harness.dispose);

      // Server initialized cleanly; tools registered.
      expect(harness.stub.didConnect, isFalse);
      final tools = await harness.connection.listTools();
      expect(tools.tools.map((t) => t.name), contains('dusk_snap'));

      // Tool call surfaces the actionable error at dispatch time.
      final result = await harness.connection.callTool(
        CallToolRequest(name: 'dusk_snap', arguments: const {}),
      );
      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('artisan start'));
      expect(text, contains('No Flutter app detected'));
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

    test(
        'dusk_evaluate routes through vm.evaluate and returns the '
        'InstanceRef value as JSON', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [
              _tool('dusk_evaluate', extensionMethod: 'ext.dusk.evaluate'),
            ],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);
      harness.stub._evaluateScript = (_, __) => InstanceRef(
            kind: 'Int',
            valueAsString: '3',
            id: 'objects/int-3',
          );

      final callResult = await harness.connection.callTool(
        CallToolRequest(
          name: 'dusk_evaluate',
          arguments: const {'expression': '1 + 2'},
        ),
      );

      expect(harness.stub.evaluateCalls.single,
          (isolateId: 'isolate-stub', expression: '1 + 2'));
      expect(callResult.isError, anyOf(isNull, isFalse));
      final text = (callResult.content.single as TextContent).text;
      expect(jsonDecode(text), {'expression': '1 + 2', 'result': '3'});
    });

    test(
        'dusk_evaluate surfaces ErrorRef result as isError with a '
        'Runtime exception message', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [
              _tool('dusk_evaluate', extensionMethod: 'ext.dusk.evaluate'),
            ],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);
      harness.stub._evaluateScript = (_, __) => ErrorRef(
            kind: 'UnhandledException',
            message: 'NoSuchMethodError: foo',
            id: 'objects/error-1',
          );

      final callResult = await harness.connection.callTool(
        CallToolRequest(
          name: 'dusk_evaluate',
          arguments: const {'expression': '1 + 2'},
        ),
      );

      expect(harness.stub.evaluateCalls.single,
          (isolateId: 'isolate-stub', expression: '1 + 2'));
      expect(callResult.isError, isTrue);
      final text = (callResult.content.single as TextContent).text;
      expect(text, contains('### Error'));
      expect(text, contains('Runtime exception'));
      expect(text, contains('NoSuchMethodError: foo'));
    });

    test(
        'dusk_evaluate maps SentinelException to isError with an '
        'Isolate sentinel hint', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [
              _tool('dusk_evaluate', extensionMethod: 'ext.dusk.evaluate'),
            ],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);
      harness.stub._evaluateScript = (_, __) => throw SentinelException.parse(
            'evaluate',
            <String, dynamic>{'kind': 'Collected', 'type': '@Sentinel'},
          );

      final callResult = await harness.connection.callTool(
        CallToolRequest(
          name: 'dusk_evaluate',
          arguments: const {'expression': '1 + 2'},
        ),
      );

      expect(harness.stub.evaluateCalls.single,
          (isolateId: 'isolate-stub', expression: '1 + 2'));
      expect(callResult.isError, isTrue);
      final text = (callResult.content.single as TextContent).text;
      expect(text, contains('### Error'));
      expect(text, contains('Isolate sentinel'));
      // Actionable hint pointing the user at the recovery command. The exact
      // wording locks in Step 7; assert only on the stable substring.
      expect(text, contains('artisan'));
    });

    test(
        'dusk_evaluate translates RPCError code 113 into a compile-error '
        'message', () async {
      final registry = ArtisanRegistry()
        ..registerMcpToolsFor(
          _FakeMcpProvider(
            providerName: 'fluttersdk_dusk',
            tools: [
              _tool('dusk_evaluate', extensionMethod: 'ext.dusk.evaluate'),
            ],
          ),
        );

      final harness = await _TestHarness.build(
        registry: registry,
        filter: McpFilterConfig.empty(),
      );
      addTearDown(harness.dispose);
      harness.stub._evaluateScript = (_, __) => throw RPCError(
            'evaluate',
            113,
            'Expression compilation error',
            <String, dynamic>{'details': 'Unterminated string literal'},
          );

      final callResult = await harness.connection.callTool(
        CallToolRequest(
          name: 'dusk_evaluate',
          arguments: const {'expression': '1 + 2'},
        ),
      );

      expect(harness.stub.evaluateCalls.single,
          (isolateId: 'isolate-stub', expression: '1 + 2'));
      expect(callResult.isError, isTrue);
      final text = (callResult.content.single as TextContent).text;
      expect(text, contains('### Error'));
      expect(text, contains('Expression compilation error'));
      expect(text, contains('Unterminated string literal'));
    });
  });
}

/// File-private substrate command fake for the artisan_* tool tests.
/// Skips the signature DSL boilerplate and lets the test pin an `onHandle`
/// closure that observes the dispatch path without spinning up a real
/// command implementation.
class _FakeSubstrateCommand extends ArtisanCommand {
  _FakeSubstrateCommand(this._name, this._description, {this.onHandle});

  final String _name;
  final String _description;
  final Future<int> Function(ArtisanContext)? onHandle;

  @override
  String get name => _name;

  @override
  String get description => _description;

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    return onHandle?.call(ctx) ?? 0;
  }
}
