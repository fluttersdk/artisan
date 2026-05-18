/// Thrown by [ArtisanRegistry.registerMcpToolsFor] when two providers register
/// an MCP tool with the same name.
///
/// MCP tool names map 1:1 to the JSON-RPC method surface exposed to the LLM
/// client. Duplicate names would silently shadow one provider's tool with
/// another's, making the resulting behaviour unpredictable and undebuggable.
/// Fail-fast at registration time forces the plugin author to rename the tool
/// before any client ever connects, mirroring the semantics of
/// [ArtisanCommandCollisionException] at the command layer.
final class ArtisanMcpToolCollisionException implements Exception {
  ArtisanMcpToolCollisionException({
    required this.toolName,
    required this.existingProvider,
    required this.newProvider,
  });

  /// The duplicate MCP tool name.
  final String toolName;

  /// Name of the provider that registered the tool first.
  final String existingProvider;

  /// Name of the provider attempting the duplicate registration.
  final String newProvider;

  @override
  String toString() =>
      'MCP tool collision: $toolName already registered by $existingProvider; '
      'cannot also register from $newProvider';
}
