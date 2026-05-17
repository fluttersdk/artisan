import 'dart:io';

/// Flutter platform detection and path resolution helper for CLI commands.
///
/// Inspects a Flutter project root to determine which platform directories
/// are present and returns canonical file-system paths for common
/// platform-specific configuration files.
///
/// ## Supported Platforms
///
/// `android`, `ios`, `web`, `macos`, `linux`, `windows`
///
/// ## Usage
///
/// ```dart
/// final root = FileHelper.findProjectRoot();
///
/// // Detect which platforms the project targets
/// final platforms = PlatformHelper.detectPlatforms(root);
/// // => ['android', 'ios', 'web']
///
/// // Check a single platform
/// if (PlatformHelper.hasPlatform(root, 'android')) {
///   final manifestPath = PlatformHelper.androidManifestPath(root);
///   XmlEditor.addAndroidPermission(manifestPath, 'android.permission.INTERNET');
/// }
/// ```
class PlatformHelper {
  PlatformHelper._();

  /// Canonical ordered list of all Flutter platforms.
  ///
  /// The order defines the output order of [detectPlatforms].
  static const List<String> _allPlatforms = [
    'android',
    'ios',
    'web',
    'macos',
    'linux',
    'windows',
  ];

  // -------------------------------------------------------------------------
  // Detection
  // -------------------------------------------------------------------------

  /// Return every platform whose top-level directory exists under [projectRoot].
  ///
  /// Results are always returned in the canonical order:
  /// android → ios → web → macos → linux → windows.
  ///
  /// @param projectRoot  Absolute path to the Flutter project root.
  /// @return An ordered [List<String>] of present platform names.
  static List<String> detectPlatforms(String projectRoot) {
    return _allPlatforms
        .where((platform) => hasPlatform(projectRoot, platform))
        .toList();
  }

  /// Check whether [platform] directory exists under [projectRoot].
  ///
  /// @param projectRoot  Absolute path to the Flutter project root.
  /// @param platform     One of: `android`, `ios`, `web`, `macos`, `linux`,
  ///                     `windows`.
  /// @return `true` if the directory is present, `false` otherwise.
  static bool hasPlatform(String projectRoot, String platform) {
    return Directory('$projectRoot/$platform').existsSync();
  }

  // -------------------------------------------------------------------------
  // Path helpers
  // -------------------------------------------------------------------------

  /// Canonical path to `AndroidManifest.xml` for [root].
  ///
  /// @param root  Flutter project root.
  /// @return Absolute-style path string.
  static String androidManifestPath(String root) {
    return '$root/android/app/src/main/AndroidManifest.xml';
  }

  /// Canonical path to `build.gradle` for [root].
  ///
  /// @param root  Flutter project root.
  /// @return Absolute-style path string.
  static String androidBuildGradlePath(String root) {
    return '$root/android/app/build.gradle';
  }

  /// Canonical path to `Info.plist` for [root].
  ///
  /// @param root  Flutter project root.
  /// @return Absolute-style path string.
  static String infoPlistPath(String root) {
    return '$root/ios/Runner/Info.plist';
  }

  /// Canonical path to `web/index.html` for [root].
  ///
  /// @param root  Flutter project root.
  /// @return Absolute-style path string.
  static String webIndexPath(String root) {
    return '$root/web/index.html';
  }

  /// Canonical path to `web/manifest.json` for [root].
  ///
  /// @param root  Flutter project root.
  /// @return Absolute-style path string.
  static String webManifestPath(String root) {
    return '$root/web/manifest.json';
  }
}
