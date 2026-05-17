/// Sealed operation taxonomy for the PluginInstaller DSL.
///
/// Every install action is represented as a plain data-carrier subclass of
/// [InstallOperation]. The hierarchy is intentionally sealed so that
/// downstream dispatch via Dart 3 exhaustive `switch` expressions is
/// compiler-checked: adding a new subclass without updating every `switch`
/// site becomes a static analysis error (`non_exhaustive_pattern_match`).
///
/// All subclasses are pure data: no IO, no side effects. The [describe]
/// method returns a human-readable dry-run line suitable for logging and the
/// `--dry-run` output renderer.
///
/// ## Usage
///
/// ```dart
/// // Build a list of operations.
/// final ops = <InstallOperation>[
///   AddDependency(name: 'firebase_core', version: '^3.0.0'),
///   InjectAndroidPermission(permission: 'android.permission.INTERNET'),
///   RunShell(command: 'dart', args: ['format', '.']),
/// ];
///
/// // Dry-run rendering.
/// for (final op in ops) {
///   print(op.describe());
/// }
///
/// // Exhaustive dispatch.
/// for (final op in ops) {
///   switch (op) {
///     case AddDependency(): executor.addDep(op);
///     case InjectAndroidPermission(): executor.injectPermission(op);
///     // ... all 26 cases required by the sealed contract.
///   }
/// }
/// ```
library;

/// Placement anchor for code injected into `lib/main.dart`.
///
/// Used by [InjectIntoMainDart] to specify where in `main.dart` the snippet
/// should be inserted relative to the `Magic.init()` call and `runApp()`.
enum MainDartPlacement {
  /// Insert the snippet before the `Magic.init(...)` call.
  beforeInit,

  /// Insert the snippet after the `Magic.init(...)` call.
  afterInit,

  /// Wrap the `runApp(...)` argument with the supplied expression.
  /// Use `#app#` as the placeholder for the original widget.
  wrapRunApp,
}

/// Base sealed class for all PluginInstaller DSL operations.
///
/// Subclasses are pure data carriers. They carry no behavior beyond [describe]
/// which returns a human-readable dry-run line used for logging and the
/// `--dry-run` output renderer.
///
/// The sealed modifier enforces exhaustive `switch` dispatch at compile time.
sealed class InstallOperation {
  /// Allows subclasses to declare `const` constructors.
  const InstallOperation();

  /// Returns a human-readable dry-run line for this operation.
  ///
  /// The format starts with a bracket-prefixed tag (e.g. `[add-dep]`) so
  /// dry-run output is grep-friendly by operation kind.
  String describe();
}

// =============================================================================
// Pubspec / dependency operations
// =============================================================================

/// Adds a package dependency to `pubspec.yaml`.
///
/// When [isDev] is `true` the dependency is placed under `dev_dependencies`
/// instead of `dependencies`.
///
/// ## Example
///
/// ```dart
/// AddDependency(name: 'firebase_core', version: '^3.0.0')
/// AddDependency(name: 'build_runner', version: '^2.4.0', isDev: true)
/// ```
final class AddDependency extends InstallOperation {
  /// The package name as it appears on pub.dev.
  final String name;

  /// The version constraint to write (e.g. `'^1.0.0'`, `'any'`).
  final String version;

  /// When `true`, the dependency is added to `dev_dependencies`.
  final bool isDev;

  /// Creates an [AddDependency] operation.
  const AddDependency({
    required this.name,
    required this.version,
    this.isDev = false,
  });

  @override
  String describe() {
    final String tag = isDev ? '[add-dev-dep]' : '[add-dep]';
    return '$tag $name: $version';
  }
}

/// Adds a path dependency to `pubspec.yaml`.
///
/// Useful when a plugin ships a companion package that should be referenced
/// by relative path rather than a published version.
///
/// ## Example
///
/// ```dart
/// AddPathDependency(name: 'my_lib', path: '../my_lib')
/// ```
final class AddPathDependency extends InstallOperation {
  /// The package name as it appears in `pubspec.yaml`.
  final String name;

  /// The relative filesystem path to the package root.
  final String path;

  /// Creates an [AddPathDependency] operation.
  const AddPathDependency({required this.name, required this.path});

  @override
  String describe() => '[add-path-dep] $name: $path';
}

/// Removes a dependency from `pubspec.yaml` (from either `dependencies` or
/// `dev_dependencies`).
///
/// ## Example
///
/// ```dart
/// RemoveDependency(name: 'legacy_pkg')
/// ```
final class RemoveDependency extends InstallOperation {
  /// The package name to remove.
  final String name;

  /// Creates a [RemoveDependency] operation.
  const RemoveDependency({required this.name});

  @override
  String describe() => '[remove-dep] $name';
}

/// Appends an asset path to the `flutter.assets` list in `pubspec.yaml`.
///
/// ## Example
///
/// ```dart
/// AddPubspecAsset(assetPath: 'assets/config.json')
/// ```
final class AddPubspecAsset extends InstallOperation {
  /// The asset path to append (relative to the project root).
  final String assetPath;

  /// Creates an [AddPubspecAsset] operation.
  const AddPubspecAsset({required this.assetPath});

  @override
  String describe() => '[add-asset] $assetPath';
}

// =============================================================================
// File operations
// =============================================================================

/// Resolves a stub template, applies token [replacements], and writes the
/// result to [targetPath].
///
/// The [sourceStubName] is a logical stub name resolved by [StubDriver]; it
/// is NOT a filesystem path.
///
/// ## Example
///
/// ```dart
/// PublishFile(
///   sourceStubName: 'config/firebase.stub',
///   targetPath: 'lib/config/firebase.dart',
///   replacements: {'PROJECT_ID': 'my-app'},
/// )
/// ```
final class PublishFile extends InstallOperation {
  /// Logical stub name resolved by [StubDriver].
  final String sourceStubName;

  /// Destination path relative to the project root.
  final String targetPath;

  /// Token-to-value map applied to the stub content before writing.
  final Map<String, String> replacements;

  /// Creates a [PublishFile] operation.
  const PublishFile({
    required this.sourceStubName,
    required this.targetPath,
    required this.replacements,
  });

  @override
  String describe() => '[publish] $sourceStubName -> $targetPath';
}

/// Writes raw [content] directly to [targetPath], overwriting any existing
/// file.
///
/// Prefer [PublishFile] when the content comes from a stub template; use
/// [WriteFile] for programmatically generated content.
///
/// ## Example
///
/// ```dart
/// WriteFile(targetPath: 'lib/generated/routes.dart', content: generatedCode)
/// ```
final class WriteFile extends InstallOperation {
  /// Destination path relative to the project root.
  final String targetPath;

  /// Raw content to write.
  final String content;

  /// Creates a [WriteFile] operation.
  const WriteFile({required this.targetPath, required this.content});

  @override
  String describe() => '[write-file] $targetPath';
}

/// Deletes the file at [targetPath] if it exists.
///
/// ## Example
///
/// ```dart
/// DeleteFile(targetPath: 'lib/old/legacy.dart')
/// ```
final class DeleteFile extends InstallOperation {
  /// Path of the file to delete, relative to the project root.
  final String targetPath;

  /// Creates a [DeleteFile] operation.
  const DeleteFile({required this.targetPath});

  @override
  String describe() => '[delete-file] $targetPath';
}

/// Copies a file from [sourcePath] to [targetPath].
///
/// Both paths are relative to the project root.
///
/// ## Example
///
/// ```dart
/// CopyFile(sourcePath: 'assets/template.dart', targetPath: 'lib/out.dart')
/// ```
final class CopyFile extends InstallOperation {
  /// Source path relative to the project root.
  final String sourcePath;

  /// Destination path relative to the project root.
  final String targetPath;

  /// Creates a [CopyFile] operation.
  const CopyFile({required this.sourcePath, required this.targetPath});

  @override
  String describe() => '[copy-file] $sourcePath -> $targetPath';
}

/// Deep-merges [sourceData] into the JSON file at [targetPath].
///
/// When [additive] is `true` (the default), existing keys in the target file
/// are preserved and only new keys are inserted. When `false`, conflicting
/// keys are overwritten by the source value.
///
/// ## Example
///
/// ```dart
/// MergeJson(
///   targetPath: 'assets/lang/en.json',
///   sourceData: {'errors': {'notFound': 'Not found.'}},
/// )
/// ```
final class MergeJson extends InstallOperation {
  /// Path to the target JSON file, relative to the project root.
  final String targetPath;

  /// Data to merge into the target file.
  final Map<String, dynamic> sourceData;

  /// When `true`, existing keys are preserved (additive merge). When `false`,
  /// conflicting keys are overwritten.
  final bool additive;

  /// Creates a [MergeJson] operation.
  const MergeJson({
    required this.targetPath,
    required this.sourceData,
    this.additive = true,
  });

  @override
  String describe() {
    final String mode = additive ? 'additive' : 'override';
    return '[merge-json] $targetPath ($mode)';
  }
}

// =============================================================================
// Dart source injection operations
// =============================================================================

/// Injects an import statement into [targetFile] if not already present.
///
/// Idempotent: the executor must guard with a `contains` check before writing.
///
/// ## Example
///
/// ```dart
/// InjectImport(
///   targetFile: 'lib/main.dart',
///   importStatement: "import 'package:my_pkg/my_pkg.dart';",
/// )
/// ```
final class InjectImport extends InstallOperation {
  /// Target Dart file relative to the project root.
  final String targetFile;

  /// The full import statement to inject (including `import '...';`).
  final String importStatement;

  /// Creates an [InjectImport] operation.
  const InjectImport({required this.targetFile, required this.importStatement});

  @override
  String describe() => '[inject-import] $targetFile: $importStatement';
}

/// Inserts [code] immediately before the first match of [pattern] in
/// [targetFile].
///
/// ## Example
///
/// ```dart
/// InjectBeforePattern(
///   targetFile: 'lib/main.dart',
///   pattern: RegExp(r'Magic\.init'),
///   code: 'AnalyticsPlugin.configure();',
/// )
/// ```
final class InjectBeforePattern extends InstallOperation {
  /// Target Dart file relative to the project root.
  final String targetFile;

  /// Pattern whose first match determines the insertion point.
  final Pattern pattern;

  /// Code snippet to insert before the matched pattern.
  final String code;

  /// Creates an [InjectBeforePattern] operation.
  const InjectBeforePattern({
    required this.targetFile,
    required this.pattern,
    required this.code,
  });

  @override
  String describe() => '[inject-before] $targetFile: $pattern';
}

/// Inserts [code] immediately after the first match of [pattern] in
/// [targetFile].
///
/// ## Example
///
/// ```dart
/// InjectAfterPattern(
///   targetFile: 'lib/main.dart',
///   pattern: RegExp(r'Magic\.init\(.*?\);', dotAll: true),
///   code: 'AnalyticsPlugin.boot();',
/// )
/// ```
final class InjectAfterPattern extends InstallOperation {
  /// Target Dart file relative to the project root.
  final String targetFile;

  /// Pattern whose first match determines the insertion point.
  final Pattern pattern;

  /// Code snippet to insert after the matched pattern.
  final String code;

  /// Creates an [InjectAfterPattern] operation.
  const InjectAfterPattern({
    required this.targetFile,
    required this.pattern,
    required this.code,
  });

  @override
  String describe() => '[inject-after] $targetFile: $pattern';
}

// =============================================================================
// Android-native injection operations
// =============================================================================

/// Adds a `<uses-permission>` element to `AndroidManifest.xml`.
///
/// ## Example
///
/// ```dart
/// InjectAndroidPermission(permission: 'android.permission.INTERNET')
/// ```
final class InjectAndroidPermission extends InstallOperation {
  /// Fully-qualified Android permission name.
  final String permission;

  /// Creates an [InjectAndroidPermission] operation.
  const InjectAndroidPermission({required this.permission});

  @override
  String describe() => '[inject-android-perm] $permission';
}

/// Adds a `<meta-data>` element inside `<application>` in
/// `AndroidManifest.xml`.
///
/// ## Example
///
/// ```dart
/// InjectAndroidMetaData(
///   name: 'com.google.firebase.messaging.default_icon',
///   value: '@mipmap/ic_launcher',
/// )
/// ```
final class InjectAndroidMetaData extends InstallOperation {
  /// The `android:name` attribute value.
  final String name;

  /// The `android:value` attribute value.
  final String value;

  /// Creates an [InjectAndroidMetaData] operation.
  const InjectAndroidMetaData({required this.name, required this.value});

  @override
  String describe() => '[inject-android-meta] $name = $value';
}

// =============================================================================
// iOS/macOS native injection operations
// =============================================================================

/// Sets a key-value pair in `ios/Runner/Info.plist`.
///
/// [value] may be a [String], [bool], [List], or [Map] matching the plist
/// value types. The executor is responsible for serializing [value] into the
/// correct plist XML node type.
///
/// ## Example
///
/// ```dart
/// InjectInfoPlistKey(key: 'NSCameraUsageDescription', value: 'Camera access needed.')
/// ```
final class InjectInfoPlistKey extends InstallOperation {
  /// The plist key to set.
  final String key;

  /// The plist value. Must be a [String], [bool], [List], or [Map].
  final Object value;

  /// Creates an [InjectInfoPlistKey] operation.
  const InjectInfoPlistKey({required this.key, required this.value});

  @override
  String describe() => '[inject-plist-key] $key = $value';
}

/// Sets a key-value pair in the `.entitlements` file for [platform].
///
/// [platform] must be `'ios'` or `'macos'`. [value] may be a [String],
/// [bool], [List], or [Map].
///
/// ## Example
///
/// ```dart
/// InjectEntitlement(
///   platform: 'ios',
///   key: 'com.apple.security.network.client',
///   value: true,
/// )
/// ```
final class InjectEntitlement extends InstallOperation {
  /// Target platform: `'ios'` or `'macos'`.
  final String platform;

  /// The entitlement key.
  final String key;

  /// The entitlement value. Must be a [String], [bool], [List], or [Map].
  final Object value;

  /// Creates an [InjectEntitlement] operation.
  const InjectEntitlement({
    required this.platform,
    required this.key,
    required this.value,
  });

  @override
  String describe() => '[inject-entitlement] $platform: $key = $value';
}

/// Appends a line to the `Podfile` target block for [platform].
///
/// [platform] should be `'ios'` or `'macos'`.
///
/// ## Example
///
/// ```dart
/// InjectPodfileLine(platform: 'ios', line: "pod 'Firebase/Messaging'")
/// ```
final class InjectPodfileLine extends InstallOperation {
  /// Target platform: `'ios'` or `'macos'`.
  final String platform;

  /// The Podfile line to append inside the target block.
  final String line;

  /// Creates an [InjectPodfileLine] operation.
  const InjectPodfileLine({required this.platform, required this.line});

  @override
  String describe() => '[inject-podfile] $platform: $line';
}

// =============================================================================
// Android Gradle injection operations
// =============================================================================

/// Adds a plugin to the `plugins` block in `android/settings.gradle`.
///
/// When [version] is provided it is appended after a colon separator in the
/// describe output.
///
/// ## Example
///
/// ```dart
/// InjectGradlePlugin(pluginId: 'com.google.gms.google-services', version: '4.4.2')
/// ```
final class InjectGradlePlugin extends InstallOperation {
  /// The Gradle plugin ID (e.g. `'com.google.gms.google-services'`).
  final String pluginId;

  /// Optional plugin version constraint.
  final String? version;

  /// Creates an [InjectGradlePlugin] operation.
  const InjectGradlePlugin({required this.pluginId, this.version});

  @override
  String describe() {
    if (version != null) {
      return '[inject-gradle-plugin] $pluginId:$version';
    }
    return '[inject-gradle-plugin] $pluginId';
  }
}

/// Adds a dependency declaration to `android/app/build.gradle`.
///
/// [scope] is typically `'implementation'` or `'classpath'`. [notation] is
/// the full Maven coordinate string.
///
/// ## Example
///
/// ```dart
/// InjectGradleDependency(
///   scope: 'implementation',
///   notation: 'com.google.firebase:firebase-analytics:21.0.0',
/// )
/// ```
final class InjectGradleDependency extends InstallOperation {
  /// Gradle dependency scope (e.g. `'implementation'`, `'classpath'`).
  final String scope;

  /// Full Maven coordinate notation.
  final String notation;

  /// Creates an [InjectGradleDependency] operation.
  const InjectGradleDependency({required this.scope, required this.notation});

  @override
  String describe() => '[inject-gradle-dep] $scope: $notation';
}

// =============================================================================
// Environment / web operations
// =============================================================================

/// Writes a key-value pair to the project's `.env` file.
///
/// The file is treated as a Flutter asset (per the project's `pubspec.yaml`
/// convention) so the entry is appended in `KEY=value` format.
///
/// ## Example
///
/// ```dart
/// InjectEnvVar(key: 'API_KEY', value: 'secret123')
/// ```
final class InjectEnvVar extends InstallOperation {
  /// Environment variable name (upper-snake-case by convention).
  final String key;

  /// The value to write.
  final String value;

  /// Creates an [InjectEnvVar] operation.
  const InjectEnvVar({required this.key, required this.value});

  @override
  String describe() => '[inject-env] $key=$value';
}

/// Injects raw HTML [content] before the closing `</head>` tag in
/// `web/index.html`.
///
/// ## Example
///
/// ```dart
/// InjectIntoWebHead(content: '<script src="app.js"></script>')
/// ```
final class InjectIntoWebHead extends InstallOperation {
  /// Raw HTML content to inject before `</head>`.
  final String content;

  /// Creates an [InjectIntoWebHead] operation.
  const InjectIntoWebHead({required this.content});

  @override
  String describe() => '[inject-web-head] $content';
}

/// Adds a `<meta>` tag to `web/index.html` with the given [attributes].
///
/// ## Example
///
/// ```dart
/// AddWebMetaTag(attributes: {'name': 'viewport', 'content': 'width=device-width'})
/// ```
final class AddWebMetaTag extends InstallOperation {
  /// Attribute map for the `<meta>` element (e.g. `name`, `content`, `charset`).
  final Map<String, String> attributes;

  /// Creates an [AddWebMetaTag] operation.
  const AddWebMetaTag({required this.attributes});

  @override
  String describe() {
    final String attrs =
        attributes.entries.map((e) => '${e.key}="${e.value}"').join(' ');
    return '[add-web-meta] $attrs';
  }
}

// =============================================================================
// main.dart injection operations
// =============================================================================

/// Injects an import statement specifically into `lib/main.dart`.
///
/// Equivalent to [InjectImport] but targets `main.dart` explicitly and is
/// distinguished in the dry-run output so log filtering can identify
/// main.dart mutations as a group.
///
/// ## Example
///
/// ```dart
/// InjectMainDartImport(importStatement: "import 'package:analytics/analytics.dart';")
/// ```
final class InjectMainDartImport extends InstallOperation {
  /// The full import statement to inject into `lib/main.dart`.
  final String importStatement;

  /// Creates an [InjectMainDartImport] operation.
  const InjectMainDartImport({required this.importStatement});

  @override
  String describe() => '[inject-main-import] $importStatement';
}

/// Injects [code] into `lib/main.dart` at the position specified by
/// [placement].
///
/// See [MainDartPlacement] for the three supported anchor points.
///
/// ## Example
///
/// ```dart
/// InjectIntoMainDart(
///   placement: MainDartPlacement.afterInit,
///   code: 'AnalyticsPlugin.boot();',
/// )
/// ```
final class InjectIntoMainDart extends InstallOperation {
  /// Where in `lib/main.dart` the snippet should be inserted.
  final MainDartPlacement placement;

  /// The code snippet to inject.
  final String code;

  /// Creates an [InjectIntoMainDart] operation.
  const InjectIntoMainDart({required this.placement, required this.code});

  @override
  String describe() {
    final String label = switch (placement) {
      MainDartPlacement.beforeInit => 'before-init',
      MainDartPlacement.afterInit => 'after-init',
      MainDartPlacement.wrapRunApp => 'wrap-run-app',
    };
    return '[inject-main:$label] $code';
  }
}

// =============================================================================
// Route registration
// =============================================================================

/// Registers a route function by appending a call to [functionName] in the
/// project's route registry file.
///
/// The executor resolves the exact injection site; this operation carries only
/// the function name so the dry-run output remains concise.
///
/// ## Example
///
/// ```dart
/// InjectRouteRegistration(functionName: 'analyticsRoutes')
/// ```
final class InjectRouteRegistration extends InstallOperation {
  /// Name of the top-level route registration function to call.
  final String functionName;

  /// Creates an [InjectRouteRegistration] operation.
  const InjectRouteRegistration({required this.functionName});

  @override
  String describe() => '[inject-route] $functionName()';
}

// =============================================================================
// Shell execution
// =============================================================================

/// Executes an arbitrary shell command after all file mutations have been
/// committed.
///
/// [args] is a positional list (no shell quoting or globbing is applied by
/// the executor). [workingDir] defaults to the project root when `null`.
///
/// ## Example
///
/// ```dart
/// RunShell(command: 'dart', args: ['format', '.'])
/// RunShell(command: 'flutter', args: ['pub', 'get'], workingDir: 'packages/plugin')
/// ```
final class RunShell extends InstallOperation {
  /// The executable to run (without arguments).
  final String command;

  /// Positional arguments passed to the executable.
  final List<String> args;

  /// Optional working directory. When `null`, defaults to the project root.
  final String? workingDir;

  /// Creates a [RunShell] operation.
  const RunShell({
    required this.command,
    required this.args,
    this.workingDir,
  });

  @override
  String describe() {
    final String cmdLine = [command, ...args].join(' ');
    if (workingDir != null) {
      return '[run-shell] $cmdLine (in $workingDir)';
    }
    return '[run-shell] $cmdLine';
  }
}
