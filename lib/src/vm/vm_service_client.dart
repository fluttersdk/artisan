import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// Wrapper around `package:vm_service` exposing the fluttersdk-house-style
/// surface that artisan connected-mode commands consume.
///
/// Critical design choice: `getMainIsolateId()` calls `getVM` on EVERY
/// invocation (NO closure caching). The ai-test MCP server's prior
/// implementation cached the isolate id at first lookup and broke on
/// device-target switches when the underlying app restarted on a different
/// isolate. The fix was to drop the cache; this wrapper inherits that
/// correctness over speed trade-off (sub-ms cost on local WebSocket).
///
/// DDS namespace mapping is handled transparently by `package:vm_service`
/// when the WebSocket URI points at a DDS endpoint (which `flutter run`
/// does by default).
class VmServiceClient {
  VmServiceClient(this.wsUri);

  final String wsUri;
  vm.VmService? _service;

  bool get isConnected => _service != null;

  Future<void> connect() async {
    if (_service != null) return;
    _service = await vmServiceConnectUri(wsUri);
  }

  Future<void> disconnect() async {
    final s = _service;
    if (s == null) return;
    await s.dispose();
    _service = null;
  }

  /// Fresh isolate-id lookup on every call (no cache). See class doc.
  Future<String> getMainIsolateId() async {
    final s = _requireConnected();
    final v = await s.getVM();
    final first = v.isolates?.first;
    if (first == null) {
      throw StateError(
        'VM Service reported no isolates; is the Flutter app fully booted?',
      );
    }
    return first.id!;
  }

  /// Returns the list of `ext.*` extension RPCs registered on the isolate.
  /// Used by fluttersdk_mcp for runtime tool discovery.
  Future<List<String>> getExtensionRPCs(String isolateId) async {
    final s = _requireConnected();
    final iso = await s.getIsolate(isolateId);
    return iso.extensionRPCs ?? const <String>[];
  }

  /// Call a VM Service extension method (delegates to
  /// `vm.callServiceExtension` which is DDS-namespace transparent).
  Future<T> callServiceExtension<T>(
    String method, {
    required String isolateId,
    Map<String, dynamic>? params,
  }) async {
    final s = _requireConnected();
    final resp = await s.callServiceExtension(
      method,
      isolateId: isolateId,
      args: params,
    );
    return resp.json as T;
  }

  /// Evaluate a Dart expression in the running app's root library.
  /// Wraps the expression in `(() async => $expr)()` when it contains `await`
  /// so the caller doesn't need to think about await-awareness.
  Future<vm.Response> evaluate(String isolateId, String expression) async {
    final s = _requireConnected();
    final iso = await s.getIsolate(isolateId);
    final rootLibId = iso.rootLib?.id;
    if (rootLibId == null) {
      throw StateError('Isolate has no root library; cannot evaluate.');
    }
    final wrapped = expression.contains('await')
        ? '(() async => $expression)()'
        : expression;
    return await s.evaluate(isolateId, rootLibId, wrapped);
  }

  /// Stream of isolate-level events (used by magic_tinker to invalidate its
  /// autocomplete corpus on `kIsolateReload`).
  Stream<vm.Event> get onIsolateEvent => _requireConnected().onIsolateEvent;

  Future<void> streamListen(String streamId) async {
    final s = _requireConnected();
    await s.streamListen(streamId);
  }

  vm.VmService _requireConnected() {
    final s = _service;
    if (s == null) {
      throw StateError(
        'VmServiceClient is not connected. Call connect() first.',
      );
    }
    return s;
  }
}
