import '../vm/vm_service_client.dart';
import 'artisan_input.dart';
import 'artisan_output.dart';

/// Execution context handed to every [ArtisanCommand.handle].
///
/// Constructed by [ArtisanApplication.dispatch] based on the command's
/// [CommandBoot] declaration. V1 has 2 constructors (bare, connected); no
/// `app` field because headless mode is deferred to V1.x.
class ArtisanContext {
  ArtisanContext.bare(this.input, this.output) : vmClient = null;

  ArtisanContext.connected(this.input, this.output, VmServiceClient client)
    : vmClient = client;

  final ArtisanInput input;
  final ArtisanOutput output;

  /// Available only when the command's boot is [CommandBoot.connected].
  final VmServiceClient? vmClient;

  /// Calls a VM Service extension on the running app's main isolate.
  /// Throws [StateError] when the context is not connected.
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final client = vmClient;
    if (client == null) {
      throw StateError(
        'ArtisanContext.callExtension called from a non-connected context. '
        'The command must declare `boot => CommandBoot.connected`.',
      );
    }
    final isolateId = await client.getMainIsolateId();
    return await client.callServiceExtension<T>(
      method,
      isolateId: isolateId,
      params: params,
    );
  }

  /// Evaluates a Dart expression in the running app's root library.
  /// Throws [StateError] when the context is not connected.
  Future<dynamic> evaluate(String expression) async {
    final client = vmClient;
    if (client == null) {
      throw StateError(
        'ArtisanContext.evaluate called from a non-connected context. '
        'The command must declare `boot => CommandBoot.connected`.',
      );
    }
    final isolateId = await client.getMainIsolateId();
    return await client.evaluate(isolateId, expression);
  }
}
