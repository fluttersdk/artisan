/// Thrown by [VmServiceClient.callServiceExtension] when the running app has
/// no handler for [method] (JSON-RPC `-32601`, method not found).
///
/// The usual cause is timing: a connected command ran while the app was still
/// booting, before its plugin registered the extension, and the same call
/// succeeds a few seconds later. A release build (which registers no service
/// extensions) or a plugin that is not installed in the app answers the same
/// way. The dispatcher prints [message] as one line and exits with
/// [ArtisanCommand.exitTryAgain]; a command that wants to wait for the
/// extension can catch this type without importing `package:vm_service`.
final class ExtensionNotRegisteredException implements Exception {
  const ExtensionNotRegisteredException(this.method);

  /// The extension that was called, e.g. `ext.dusk.snapshot`.
  final String method;

  String get message => '$method is not registered in the running app yet '
      '(still booting, a release build, or the plugin is not installed). '
      'Retry in a few seconds.';

  @override
  String toString() => message;
}
