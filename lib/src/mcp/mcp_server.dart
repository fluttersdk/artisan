import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:stream_channel/stream_channel.dart';

import '../console/artisan_registry.dart';
import '../state/state_file.dart';
import '../vm/vm_service_client.dart';
import 'mcp_filter_config.dart';

/// Signature for the VM Service client factory.
///
/// Production code passes [VmServiceClient.new]; tests inject a stub that
/// records `callServiceExtension` invocations without spawning Flutter.
typedef VmServiceClientFactory = VmServiceClient Function(String wsUri);

/// Signature for the state-file reader.
///
/// Production code passes [StateFile.read]; tests inject a closure returning
/// a canned map so initialize is hermetic.
typedef StateReader = Future<Map<String, dynamic>?> Function();

/// MCP server that exposes [ArtisanRegistry.mcpTools] to a connected MCP
/// client (Claude Code, Cursor, etc.) over a [StreamChannel] of newline-
/// delimited JSON-RPC.
///
/// Architectural choices:
///
/// - Static tool set: tools are filtered + registered ONCE inside [initialize].
///   No `sendToolListChanged()` calls in V1 (per Oracle C1 revise; the SIGHUP
///   reload path is V1.1 BACKLOG). `capabilities.tools.listChanged` stays at
///   the library-default `true` so the advertised capability matches reality
///   once that path lands; never mutate it to `false` here, that would fight
///   `ToolsSupport`'s own initialize.
///
/// - Filter at registration, not at dispatch: a denied tool never reaches
///   [registerTool], so dart_mcp's built-in "no tool registered with the
///   name X" error covers the denied case automatically.
///
/// - VM Service connection owned by [serve]: the connection lifetime is the
///   server's lifetime. No cross-server caching (single-server-per-process
///   model; matches the prior `fluttersdk_mcp/lib/src/mcp_server.dart`
///   behaviour we replaced).
///
/// - Stdio transport: production wiring goes through [dart_mcp]'s
///   [stdioChannel] helper, leaving stderr free for diagnostic logging.
final class McpServer extends MCPServer with ToolsSupport {
  /// Primary constructor; consumers should prefer [McpServer.stdio] for
  /// production and [McpServer.test] for unit tests.
  McpServer._({
    required StreamChannel<String> channel,
    required this.registry,
    required this.filter,
    required VmServiceClientFactory vmClientFactory,
    required StateReader stateReader,
  })  : _vmClientFactory = vmClientFactory,
        _stateReader = stateReader,
        super.fromStreamChannel(
          channel,
          implementation: Implementation(
            name: 'fluttersdk_artisan_mcp',
            version: '0.0.1',
          ),
        );

  /// Production factory: wires stdin / stdout through [stdioChannel] and
  /// uses the real [VmServiceClient] + [StateFile.read] for discovery.
  factory McpServer.stdio({
    required ArtisanRegistry registry,
    required McpFilterConfig filter,
  }) =>
      McpServer._(
        channel: stdioChannel(input: stdin, output: stdout),
        registry: registry,
        filter: filter,
        vmClientFactory: VmServiceClient.new,
        stateReader: StateFile.read,
      );

  /// Test factory: caller supplies the channel + every external seam.
  factory McpServer.test({
    required StreamChannel<String> channel,
    required ArtisanRegistry registry,
    required McpFilterConfig filter,
    required VmServiceClientFactory vmClientFactory,
    required StateReader stateReader,
  }) =>
      McpServer._(
        channel: channel,
        registry: registry,
        filter: filter,
        vmClientFactory: vmClientFactory,
        stateReader: stateReader,
      );

  /// Source of the tool catalog and provider attribution.
  final ArtisanRegistry registry;

  /// Effective allow/deny axes applied once at initialize time.
  final McpFilterConfig filter;

  final VmServiceClientFactory _vmClientFactory;
  final StateReader _stateReader;

  /// VM Service client owned by this server; non-null after [initialize].
  VmServiceClient? _vmClient;

  /// Main isolate id captured at initialize time; reused for every dispatch.
  String? _isolateId;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    // 1. Let ToolsSupport register its request handlers and seed the result.
    //    DO NOT mutate `result.capabilities.tools.listChanged`; the mixin
    //    has already set it to true and our V1 contract honors that.
    final result = await super.initialize(request);

    // 2. Discover the running Flutter app via the state file written by
    //    `artisan start`. Without a vmServiceUri there is nothing for any
    //    registered tool to dispatch to, so surface the error early instead
    //    of registering tools that will all fail at call time.
    final state = await _stateReader();
    final wsUri = state?['vmServiceUri'] as String?;
    if (wsUri == null || wsUri.isEmpty) {
      throw StateError(
        'McpServer: ~/.artisan/state.json is missing or has no '
        'vmServiceUri. Run `artisan start` before connecting the MCP client.',
      );
    }

    final vmClient = _vmClientFactory(wsUri);
    await vmClient.connect();
    final isolateId = await vmClient.getMainIsolateId();
    _vmClient = vmClient;
    _isolateId = isolateId;

    // 3. Apply the filter once; survivors get registered, denied tools never
    //    reach `registerTool` so dart_mcp's native "no tool" error covers
    //    denied call attempts.
    final allTools = registry.mcpTools;
    final filtered = filter.apply(
      allTools,
      (tool) =>
          registry.providerNameFor(tool.name) ??
          // A descriptor in `mcpTools` always has a registered provider;
          // the empty-string fallback only exists so the lookup is total
          // and the filter never crashes on a desync we did not anticipate.
          '',
    );

    // 4. Register each surviving tool with its dispatch handler. dart_mcp
    //    auto-validates arguments against the wrapped ObjectSchema.
    for (final descriptor in filtered) {
      registerTool(
        Tool(
          name: descriptor.name,
          description: descriptor.description,
          inputSchema: ObjectSchema.fromMap(descriptor.inputSchema),
        ),
        (request) => _dispatch(request, descriptor.extensionMethod),
      );
    }

    stderr.writeln(
      '[fluttersdk_artisan_mcp] initialized with ${filtered.length} tools '
      '(${allTools.length - filtered.length} filtered)',
    );

    return result;
  }

  /// Dispatches a tool call to the matching VM Service extension and wraps
  /// the result as text content. Errors surface as `isError: true` rather
  /// than RPC failures so the client model can self-correct.
  Future<CallToolResult> _dispatch(
    CallToolRequest request,
    String extensionMethod,
  ) async {
    final vmClient = _vmClient;
    final isolateId = _isolateId;
    if (vmClient == null || isolateId == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text: '### Error\nMcpServer not initialized; '
                'no VM Service connection.',
          ),
        ],
      );
    }

    try {
      final args = request.arguments?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final result = await vmClient.callServiceExtension<Object?>(
        extensionMethod,
        isolateId: isolateId,
        params: args,
      );
      return CallToolResult(
        content: [TextContent(text: jsonEncode(result))],
      );
    } catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: '### Error\n$e')],
      );
    }
  }

  @override
  Future<void> shutdown() async {
    await _vmClient?.disconnect();
    _vmClient = null;
    _isolateId = null;
    await super.shutdown();
  }

  /// Convenience entry: build a stdio-wired server and block until the
  /// peer closes the channel. Intended for `bin/mcp.dart` (Step 22).
  static Future<void> serve({
    required ArtisanRegistry registry,
    required McpFilterConfig filter,
  }) async {
    final server = McpServer.stdio(registry: registry, filter: filter);
    await server.done;
  }
}
