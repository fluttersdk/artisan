/// A value type describing a single MCP tool contributed by an
/// [ArtisanServiceProvider] via its [mcpTools] override.
///
/// The four fields are mandatory; there are no defaults. Plugin authors
/// construct descriptors in code and return them from [mcpTools]; the
/// framework never parses descriptors from external JSON, so no [fromJson]
/// factory is provided.
///
/// Wire shape note: [toJson] emits only [name], [description], and
/// [inputSchema]. The [extensionMethod] field is an internal routing key
/// used by the MCP server to dispatch incoming tool calls to the correct VM
/// Service extension; it is intentionally absent from the MCP protocol
/// payload.
///
/// dart_mcp integration note: when passed to dart_mcp v0.5.1's
/// [registerTool], the [inputSchema] map must be wrapped as
/// `ObjectSchema.fromMap(inputSchema)` at the registerTool call site (Step 7
/// handles the wrap). Keeping the descriptor field as [Map] avoids leaking
/// dart_mcp's [ObjectSchema] extension type into plugin author code.
///
/// Collision diagnostics: [toString] includes [name] and [extensionMethod]
/// so that [ArtisanMcpToolCollisionException] messages identify the duplicate
/// at a glance.
final class McpToolDescriptor {
  /// Constructs an immutable MCP tool descriptor.
  ///
  /// All four parameters are required; the class is const-constructible so
  /// providers may declare their tools as compile-time constants.
  const McpToolDescriptor({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.extensionMethod,
  });

  /// Tool name exposed to the MCP client.
  ///
  /// Follow the snake_case service-prefix pattern documented by Anthropic
  /// (e.g. `dusk_tap`, `telescope_tail`, `tinker_evaluate`). The name must
  /// be unique across all providers loaded in a single artisan session; the
  /// registry throws [ArtisanMcpToolCollisionException] on collision.
  final String name;

  /// Human-readable, LLM-targeted description of what the tool does.
  ///
  /// Action-oriented phrasing works best. The MCP client surface (Claude
  /// Code, Cursor, etc.) uses this string when deciding which tool to invoke.
  final String description;

  /// JSON Schema object describing the tool's accepted input.
  ///
  /// Declared as [Map] for framework-neutrality at the descriptor layer.
  /// When passed to dart_mcp v0.5.1's [registerTool], the caller must wrap
  /// this as `ObjectSchema.fromMap(inputSchema)` (Step 7 handles the wrap).
  /// The schema must conform to JSON Schema draft 7 as expected by the MCP
  /// protocol.
  final Map<String, dynamic> inputSchema;

  /// The VM Service extension method this tool dispatches to at runtime.
  ///
  /// Must match an extension registered via `registerExtension` /
  /// `registerExtensionIdempotent` in the running Flutter isolate (e.g.
  /// `ext.dusk.tap`, `ext.telescope.tail`, `ext.tinker.evaluate`). Not
  /// included in [toJson]; it is an internal routing key, not an MCP wire
  /// field.
  final String extensionMethod;

  /// Serialises to the MCP protocol tool object.
  ///
  /// Includes [name], [description], and [inputSchema]. Excludes
  /// [extensionMethod] because that field is an internal routing key and has
  /// no place in the MCP wire shape.
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };

  @override
  String toString() =>
      'McpToolDescriptor(name: $name, extensionMethod: $extensionMethod)';
}
