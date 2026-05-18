import '../vm/vm_service_client.dart';
import 'artisan_input.dart';
import 'artisan_output.dart';
import 'artisan_registry.dart';

/// Execution context handed to every [ArtisanCommand.handle].
///
/// Constructed by [ArtisanApplication.dispatch] based on the command's
/// [CommandBoot] declaration. V1 has 2 constructors (bare, connected); no
/// `app` field because headless mode is deferred to V1.x.
///
/// [registry] is populated by [ArtisanApplication.dispatch] so command
/// handlers can call `ctx.registry?.find('cmd')?.handle(ctx)` for in-process
/// command chaining. It is nullable for backward compatibility with bare
/// contexts constructed in tests or outside [ArtisanApplication.dispatch].
class ArtisanContext {
  ArtisanContext.bare(this.input, this.output, {this.registry})
      : vmClient = null;

  ArtisanContext.connected(
    this.input,
    this.output,
    VmServiceClient client, {
    this.registry,
  }) : vmClient = client;

  final ArtisanInput input;
  final ArtisanOutput output;

  /// Available only when the command's boot is [CommandBoot.connected].
  final VmServiceClient? vmClient;

  /// The application's command registry.
  ///
  /// Non-null when constructed by [ArtisanApplication.dispatch]; null when
  /// constructed as a bare context (e.g. in tests). Use the null-safe `?.`
  /// operator: `ctx.registry?.find('plugins:refresh')?.handle(ctx)`.
  final ArtisanRegistry? registry;

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
