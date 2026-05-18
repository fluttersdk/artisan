import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:stream_channel/stream_channel.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/artisan_input.dart';
import '../console/artisan_output.dart';
import '../console/artisan_registry.dart';
import '../state/state_file.dart';
import '../vm/vm_service_client.dart';
import 'mcp_filter_config.dart';
import 'mcp_tool_descriptor.dart';

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
    //    `artisan start`. State file absence is NOT fatal: the MCP server
    //    stays online, registers every tool, and individual tool calls
    //    soft-fail at dispatch time with an actionable "run artisan start"
    //    message. This lets MCP clients (Claude Code, Cursor, Windsurf) stay
    //    connected across the natural dev cycle of starting / stopping the
    //    Flutter app without having to reconnect the server every time.
    final state = await _stateReader();
    final wsUri = state?['vmServiceUri'] as String?;
    if (wsUri != null && wsUri.isNotEmpty) {
      try {
        final vmClient = _vmClientFactory(wsUri);
        await vmClient.connect();
        final isolateId = await vmClient.getMainIsolateId();
        _vmClient = vmClient;
        _isolateId = isolateId;
      } catch (e) {
        stderr.writeln(
          '[fluttersdk_artisan_mcp] VM Service connect failed: $e. '
          'Tool calls requiring VM connection will return an error; '
          'restart the Flutter app and the next call will reconnect.',
        );
      }
    } else {
      stderr.writeln(
        '[fluttersdk_artisan_mcp] no running Flutter app detected '
        '(~/.artisan/state.json missing or empty). Tools register but VM '
        'Service calls will fail until you run `artisan start`.',
      );
    }

    // 3. Apply the filter once; survivors get registered, denied tools never
    //    reach `registerTool` so dart_mcp's native "no tool" error covers
    //    denied call attempts. The plugin-side tools (registry.mcpTools) AND
    //    the substrate-side tools (artisan command adapter below) flow
    //    through the same filter so a deny rule like `tools.deny:
    //    [artisan_start]` works the same as `tools.deny: [dusk_snap]`.
    final pluginTools = registry.mcpTools;
    final substrateTools = _artisanCommandTools();
    final allTools = <McpToolDescriptor>[...pluginTools, ...substrateTools];
    final filtered = filter.apply(
      allTools,
      (tool) {
        // Substrate tools belong to the synthetic provider 'fluttersdk_artisan';
        // plugin tools defer to the registry's provider lookup.
        if (tool.extensionMethod.startsWith(_artisanDispatchPrefix)) {
          return 'fluttersdk_artisan';
        }
        return registry.providerNameFor(tool.name) ?? '';
      },
    );

    // 4. Register each surviving tool with its dispatch handler. dart_mcp
    //    auto-validates arguments against the wrapped ObjectSchema. The
    //    handler routes by `extensionMethod` prefix: substrate commands
    //    (prefix `artisan:`) run in-process via the registry; everything
    //    else dispatches through the VM Service.
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
      '(${allTools.length - filtered.length} filtered; '
      '${pluginTools.length} plugin + ${substrateTools.length} substrate)',
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
    // Substrate command: extensionMethod looks like `artisan:<cmd>`. Routes
    // in-process via the registry; no VM Service required. Lets MCP clients
    // bootstrap the Flutter app (`artisan_start`) before any plugin tool
    // becomes available.
    if (extensionMethod.startsWith(_artisanDispatchPrefix)) {
      return _dispatchArtisanCommand(
        request,
        extensionMethod.substring(_artisanDispatchPrefix.length),
      );
    }

    // Lazy-reconnect: when initialize ran without a Flutter app present
    // (state.json absent) the VM Service client is null. Retry connect on
    // every dispatch so users can `artisan start` AFTER the MCP server is
    // already serving and the very next tool call picks up the new app
    // without a reconnect cycle.
    if (_vmClient == null) {
      final state = await _stateReader();
      final wsUri = state?['vmServiceUri'] as String?;
      if (wsUri != null && wsUri.isNotEmpty) {
        try {
          final vmClient = _vmClientFactory(wsUri);
          await vmClient.connect();
          final isolateId = await vmClient.getMainIsolateId();
          _vmClient = vmClient;
          _isolateId = isolateId;
          stderr.writeln(
            '[fluttersdk_artisan_mcp] lazy-connected to VM Service at '
            '$wsUri',
          );
        } catch (e) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: '### Error\nVM Service connect failed: $e\n\n'
                    'Run `artisan start` to launch the Flutter app, then '
                    'retry the tool call.',
              ),
            ],
          );
        }
      }
    }

    final vmClient = _vmClient;
    final isolateId = _isolateId;
    if (vmClient == null || isolateId == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text: '### Error\nNo Flutter app detected '
                '(~/.artisan/state.json missing or has no vmServiceUri).\n\n'
                'Run `artisan start` to launch the Flutter app, then retry '
                'the tool call. The MCP server will lazy-connect on the '
                'next invocation.',
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

  /// Walks the registry's command list and emits an [McpToolDescriptor] for
  /// every command in [_safeArtisanCommandNames]. The allowlist excludes
  /// interactive (`tinker`, `help`), codegen (`make:*`, `*:refresh`), MCP
  /// meta (`mcp:*`), installer (`plugin:*`, `consumer:scaffold`) commands
  /// that either need a TTY or recurse into the MCP server itself.
  ///
  /// Tool names are normalized from `cmd:name` to `cmd_name` because MCP
  /// tool names must match `[a-zA-Z][a-zA-Z0-9_]*` (no colons). The
  /// substrate's CLI name is recovered from the extensionMethod prefix
  /// during dispatch.
  List<McpToolDescriptor> _artisanCommandTools() {
    final tools = <McpToolDescriptor>[];
    for (final command in registry.all()) {
      if (!_safeArtisanCommandNames.contains(command.name)) continue;
      // MCP tool names are kebab-incompatible in some clients; replace both
      // `:` (namespace) and `-` (kebab) with `_` so every name matches
      // `[a-zA-Z][a-zA-Z0-9_]*` cleanly.
      final toolName =
          'artisan_${command.name.replaceAll(':', '_').replaceAll('-', '_')}';
      tools.add(McpToolDescriptor(
        name: toolName,
        description: command.description,
        inputSchema: _commandInputSchema(command),
        extensionMethod: '$_artisanDispatchPrefix${command.name}',
      ));
    }
    return tools;
  }

  /// Per-command JSON Schema. V1 covers the parameter surface of the 9
  /// allowlisted commands explicitly. Auto-deriving from
  /// [ArtisanCommand.signature] is a follow-up.
  Map<String, dynamic> _commandInputSchema(ArtisanCommand command) {
    switch (command.name) {
      case 'start':
        return <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'device': <String, dynamic>{
              'type': 'string',
              'description': 'Target device id (`chrome`, `macos`, `<serial>`)',
            },
            'port': <String, dynamic>{
              'type': 'integer',
              'description': 'Web port for `chrome` device',
            },
            'profile': <String, dynamic>{
              'type': 'string',
              'enum': <String>['debug', 'profile', 'release'],
            },
          },
        };
      case 'logs':
        return <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'tail': <String, dynamic>{
              'type': 'integer',
              'description': 'How many recent log lines to return',
            },
          },
        };
      case 'stop':
      case 'status':
      case 'restart':
      case 'reload':
      case 'hot-restart':
      case 'doctor':
      case 'list':
        return <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        };
      default:
        return <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        };
    }
  }

  /// In-process dispatch for substrate commands. Builds a [MapInput] from
  /// the MCP arguments, captures stdout/stderr via a [BufferedOutput], and
  /// returns the combined output (plus exit code) as MCP text content.
  Future<CallToolResult> _dispatchArtisanCommand(
    CallToolRequest request,
    String commandName,
  ) async {
    final command = registry.find(commandName);
    if (command == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: '### Error\nUnknown artisan command: $commandName'),
        ],
      );
    }

    final args =
        request.arguments?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final output = BufferedOutput();
    final input = MapInput(args);
    final ctx = ArtisanContext.bare(input, output, registry: registry);

    try {
      final exitCode = await command.handle(ctx);
      final combined = StringBuffer()
        ..writeln('# `artisan $commandName` exit $exitCode')
        ..writeln()
        ..write(output.content);
      return CallToolResult(
        isError: exitCode != 0,
        content: [TextContent(text: combined.toString())],
      );
    } catch (e, s) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: '### Error\n$e\n\n$s'),
        ],
      );
    }
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

/// Prefix that marks a substrate command in an [McpToolDescriptor]
/// `extensionMethod`. The dispatcher routes any descriptor whose method
/// starts with this prefix through the in-process command runner instead of
/// the VM Service.
const String _artisanDispatchPrefix = 'artisan:';

/// Substrate commands the MCP server exposes as tools by default. The
/// allowlist intentionally excludes interactive (`tinker`, `help`), codegen
/// (`make:*`, `*:refresh`), installer (`plugin:*`, `consumer:scaffold`),
/// and MCP meta (`mcp:*`) commands because they either need a TTY, mutate
/// source on disk in ways better served by the client's own file tools, or
/// recurse into the MCP server itself.
const Set<String> _safeArtisanCommandNames = <String>{
  'start',
  'stop',
  'status',
  'logs',
  'restart',
  'reload',
  'hot-restart',
  'doctor',
  'list',
};
