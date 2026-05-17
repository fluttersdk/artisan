/// Typed exceptions for the PluginInstaller DSL.
///
/// All installer-layer errors extend [InstallException] so callers can catch
/// the entire family with a single `on InstallException` clause, or target a
/// specific subtype for finer-grained error handling.
///
/// ## Usage
///
/// ```dart
/// try {
///   await installer.run(context);
/// } on ManifestValidationException catch (e) {
///   print('Manifest error: ${e.message}');
/// } on InstallException catch (e) {
///   print('Install error: ${e.message}  op=${e.offendingOp}');
/// }
/// ```
library;

/// Base exception for all errors raised by the PluginInstaller DSL.
///
/// [message] is a human-readable description of the failure. [offendingOp]
/// holds an optional reference to the install operation that triggered the
/// error; the type is [Object?] so the field compiles before the sealed
/// [InstallOperation] hierarchy is introduced in a later step.
class InstallException implements Exception {
  /// Human-readable description of the failure.
  final String message;

  /// The install operation that caused this exception, or `null` when the
  /// failure is not tied to a specific operation.
  ///
  /// Typed as [Object?] to allow gradual tightening to the sealed
  /// `InstallOperation` hierarchy once that class is defined.
  final Object? offendingOp;

  /// Creates an [InstallException] with a [message] and an optional
  /// [offendingOp] reference.
  const InstallException(this.message, {this.offendingOp});

  @override
  String toString() {
    if (offendingOp != null) {
      return 'InstallException: $message (op: $offendingOp)';
    }
    return 'InstallException: $message';
  }
}

/// Raised when an `install.yaml` manifest fails schema or semantic validation.
///
/// Extends [InstallException] so it can be caught as part of the broader
/// installer exception family.
///
/// ## Usage
///
/// ```dart
/// throw ManifestValidationException(
///   'Missing required key: name.',
///   offendingOp: 'validate_manifest',
/// );
/// ```
class ManifestValidationException extends InstallException {
  /// Creates a [ManifestValidationException] with a [message] describing the
  /// validation failure and an optional [offendingOp] reference.
  const ManifestValidationException(super.message, {super.offendingOp});

  @override
  String toString() {
    if (offendingOp != null) {
      return 'ManifestValidationException: $message (op: $offendingOp)';
    }
    return 'ManifestValidationException: $message';
  }
}
