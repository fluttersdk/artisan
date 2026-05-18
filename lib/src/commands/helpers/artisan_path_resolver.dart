import 'package:path/path.dart' as p;

/// Resolves relative paths between the fluttersdk_artisan package root and a
/// consumer package directory, suitable for use as a YAML `path:` value in a
/// generated `pubspec.yaml`.
class ArtisanPathResolver {
  const ArtisanPathResolver._();

  /// Compute the relative path from [targetDir] to [artisanRoot] suitable
  /// for use as a YAML `path:` value in a generated pubspec.yaml.
  ///
  /// Both paths must be absolute. Returns a forward-slash-normalized
  /// relative path (e.g. `../../fluttersdk_artisan` for nested; `../foo/`
  /// for sibling).
  ///
  /// Special cases:
  /// - When [artisanRoot] equals [targetDir] the method returns `'.'`.
  /// - A leading `./` produced by `p.relative` is stripped so the result is
  ///   always clean for YAML embedding.
  static String computeRelative({
    required String artisanRoot,
    required String targetDir,
  }) {
    // p.relative handles cross-platform separators; normalize output.
    final raw = p.relative(artisanRoot, from: targetDir);

    // Strip leading `./` if present (path package returns it for
    // sibling-of-target cases sometimes).
    if (raw.startsWith('./')) return raw.substring(2);

    // Empty or '.' means same dir — return '.' explicitly per convention.
    if (raw.isEmpty || raw == '.') return '.';

    return raw;
  }
}
