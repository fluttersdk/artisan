import 'dart:async';

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
  ///
  /// When the call returns a `Sentinel` (the underlying isolate is gone —
  /// usually because a hot-restart minted a new isolate id and the caller
  /// held a stale one) the method refreshes the isolate via
  /// [getMainIsolateId] and retries ONCE. The retry only fires when the
  /// fresh id differs from [isolateId]; otherwise the sentinel propagates.
  /// This makes every connected-mode handler tolerant of the standard
  /// `artisan_hot_restart` → next-MCP-call workflow without forcing every
  /// caller to invalidate its own cache.
  Future<T> callServiceExtension<T>(
    String method, {
    required String isolateId,
    Map<String, dynamic>? params,
  }) async {
    final s = _requireConnected();
    try {
      final resp = await s.callServiceExtension(
        method,
        isolateId: isolateId,
        args: params,
      );
      return resp.json as T;
    } on vm.SentinelException catch (e) {
      // Sentinel almost always means "isolate gone". Refresh once and try
      // again; if the id has not actually changed, the sentinel is
      // genuine (isolate genuinely unreachable) and we re-throw.
      final String fresh;
      try {
        fresh = await getMainIsolateId();
      } catch (_) {
        rethrow;
      }
      if (fresh == isolateId) rethrow;
      final resp = await s.callServiceExtension(
        method,
        isolateId: fresh,
        args: params,
      );
      // Surface the fresh id to interested callers (mcp_server caches it)
      // via the dedicated event stream.
      _lastResolvedIsolateId = fresh;
      _isolateRefreshController.add(fresh);
      _markRefreshFromException(e);
      return resp.json as T;
    }
  }

  /// Reports the last isolate id this client transparently refreshed away
  /// from. Callers that cache the isolate id can listen on
  /// [onIsolateRefreshed] and update their cache without reaching into
  /// `getMainIsolateId` after every tool call.
  String? get lastResolvedIsolateId => _lastResolvedIsolateId;
  String? _lastResolvedIsolateId;

  /// Broadcasts whenever the retry path inside [callServiceExtension]
  /// recovers from a stale-isolate sentinel by reaching for a fresh id.
  /// Single subscriber per cache (mcp_server uses one); broadcast so
  /// multiple commands can listen without contention.
  Stream<String> get onIsolateRefreshed => _isolateRefreshController.stream;
  final StreamController<String> _isolateRefreshController =
      StreamController<String>.broadcast();

  // Records the exception so a future trace flag can correlate the silent
  // recovery with the original RPC failure. No-op today; the hook exists
  // so the retry path is visible in tests.
  void _markRefreshFromException(vm.SentinelException _) {}

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

  /// Hot reload — incremental Dart source re-import without losing isolate
  /// state. Equivalent to pressing `r` in `flutter run`. Caller invokes
  /// `ext.flutter.reassemble` afterwards to rebuild the widget tree.
  ///
  /// `force=true` reimports every library even when unchanged (slower; used
  /// by hot restart simulations).
  Future<vm.ReloadReport> reloadSources(
    String isolateId, {
    bool force = false,
  }) async {
    final s = _requireConnected();
    return await s.reloadSources(isolateId, force: force);
  }

  /// Stream of isolate-level events (used by tinker autocomplete to
  /// invalidate its cached corpus on `kIsolateReload`).
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
