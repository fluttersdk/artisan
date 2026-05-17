import 'artisan_command.dart';

/// Base for any package that contributes commands to an [ArtisanApplication].
///
/// Magic-style ServiceProvider semantics: each provider returns the list of
/// commands it ships; [ArtisanRegistry] merges them under fail-fast
/// collision rules. Discovery is explicit (host app lists providers in
/// `appConfig['artisan']['providers']`, mirroring magic's existing
/// `app.providers` pattern).
abstract class ArtisanServiceProvider {
  /// Human-readable provider name (used in collision error messages).
  /// Defaults to the runtime class name.
  String get providerName => runtimeType.toString();

  /// Returns the commands this provider contributes to the application.
  List<ArtisanCommand> commands();
}
