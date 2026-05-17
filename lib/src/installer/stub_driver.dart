import '../stubs/stub_loader.dart';

/// Contract for stub template I/O in the PluginInstaller DSL.
///
/// Mirrors the three-method surface of the static [StubLoader] class so that
/// [InstallContext] can hold an instance field and tests can inject a
/// `FakeStubDriver` with in-memory fixtures without touching the filesystem.
///
/// ## Usage
///
/// ```dart
/// final driver = RealStubDriver();
/// final content = driver.load('model');
/// final result = driver.make('model', {'className': 'Monitor'});
/// ```
abstract class StubDriver {
  /// Load a `.stub` file by name and return its raw content.
  ///
  /// [name] is the stub name without extension (e.g., `model`,
  /// `controller.resource`). [searchPaths] are optional custom directories
  /// to search before the package default `assets/stubs/`.
  ///
  /// @param name         Stub name without the `.stub` extension.
  /// @param searchPaths  Optional ordered list of directories to search first.
  /// @return Raw stub content as a string.
  /// @throws FileSystemException if the stub file is not found.
  String load(String name, {List<String>? searchPaths});

  /// Replace all `{{ key }}` placeholders in [stub] with values from
  /// [replacements].
  ///
  /// Handles flexible whitespace: both `{{key}}` and `{{ key }}` are matched
  /// when the underlying implementation normalises spaces.
  ///
  /// @param stub          Raw stub content returned by [load].
  /// @param replacements  Map of placeholder names to replacement values.
  /// @return Processed content with all matching placeholders substituted.
  String replace(String stub, Map<String, String> replacements);

  /// Load a stub and replace all placeholders in one step.
  ///
  /// Convenience method combining [load] and [replace].
  ///
  /// @param name          Stub name without the `.stub` extension.
  /// @param replacements  Map of placeholder names to replacement values.
  /// @return Fully resolved stub content.
  /// @throws FileSystemException if the stub file is not found.
  String make(String name, Map<String, String> replacements);
}

/// Production [StubDriver] that delegates every call to the static
/// [StubLoader] class.
///
/// For tests that need in-memory stubs without filesystem access, define a
/// `FakeStubDriver` in the test file (it must NOT be exported from `lib/`).
///
/// ## Usage
///
/// ```dart
/// final driver = RealStubDriver();
/// final content = driver.make('model', {'className': 'Monitor'});
/// ```
class RealStubDriver implements StubDriver {
  /// Creates a [RealStubDriver].
  const RealStubDriver();

  @override
  String load(String name, {List<String>? searchPaths}) =>
      StubLoader.load(name, searchPaths: searchPaths);

  @override
  String replace(String stub, Map<String, String> replacements) =>
      StubLoader.replace(stub, replacements);

  @override
  String make(String name, Map<String, String> replacements) =>
      StubLoader.make(name, replacements);
}
