/// Thrown by [ArtisanRegistry.register] when two providers register a
/// command with the same name without explicit `override: true`.
///
/// Per oracle CRITICAL finding (fluttersdk-ecosystem-split plan), artisan
/// adopts FAIL-FAST collision semantics (modeled on
/// `developer.registerExtension`'s `ArgumentError`) rather than Laravel's
/// silent last-wins via `Symfony Application::add()`. Silent shadowing of
/// a vendor command by an unrelated provider command is a debugging black
/// hole; making it loud forces explicit opt-in.
class ArtisanCommandCollisionException implements Exception {
  ArtisanCommandCollisionException({
    required this.commandName,
    required this.existingProvider,
    required this.newProvider,
  });

  /// The duplicate command name.
  final String commandName;

  /// Name of the provider that registered the command first.
  final String existingProvider;

  /// Name of the provider attempting the duplicate registration.
  final String newProvider;

  String get message =>
      "Command '$commandName' already registered by provider "
      "'$existingProvider'. Pass `override: true` to "
      "$newProvider.registerInto(...) to intentionally replace.";

  @override
  String toString() => 'ArtisanCommandCollisionException: $message';
}
