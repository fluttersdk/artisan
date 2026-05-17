import 'dart:developer' as developer;

/// Calls [developer.registerExtension] swallowing the duplicate-registration
/// [ArgumentError] that fires when the same extension name is registered twice
/// within a single isolate.
///
/// Why: VM Service extension table persists across hot-restart, so a second
/// `install()` call on the plugin layer would otherwise throw. Wrapping the
/// registration call in this idempotent helper keeps host-side
/// `<Plugin>Plugin.install()` safe to call repeatedly (or to be called by
/// both the host app and an integration adapter shipped from a sibling
/// package without coordination).
///
/// Hot-restart-safety contract documented in the V3 ai-test plugin's
/// `v3_register.dart` and inherited by fluttersdk_artisan as the substrate
/// for dusk + telescope + tinker + magic_tinker extension registrations.
void registerExtensionIdempotent(
  String method,
  developer.ServiceExtensionHandler handler,
) {
  try {
    developer.registerExtension(method, handler);
  } on ArgumentError catch (e) {
    // VM rejects duplicate registration of the same method name. Swallow the
    // specific "already registered" message; rethrow anything else.
    final msg = e.message?.toString() ?? '';
    if (!msg.contains('already registered') && !msg.contains('Extension')) {
      rethrow;
    }
    // Idempotent re-registration: silently no-op.
  }
}
