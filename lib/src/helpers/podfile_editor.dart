import 'dart:io';

/// iOS and macOS Podfile manipulation helper for CLI install commands.
///
/// Provides pure regex-based utilities for reading and modifying Ruby Podfiles
/// without requiring a Dart Ruby AST parser (none exists; regex is the industry
/// standard approach, following FlutterFire CLI's own Gradle-file strategy).
/// All mutation methods are idempotent unless the task spec states otherwise.
///
/// Supported DSL constructs:
/// - `platform :ios, '<version>'` and `platform :osx, '<version>'`
/// - `target '<name>' do ... end` blocks
/// - `post_install do |installer| ... end` blocks
///
/// ## Usage
///
/// ```dart
/// // Bump the minimum iOS deployment target.
/// PodfileEditor.setPlatformVersion(
///   'ios/Podfile',
///   'ios',
///   '13.0',
/// );
///
/// // Inject a build-settings hook into post_install.
/// PodfileEditor.addPostInstallHook(
///   'ios/Podfile',
///   "  installer.pods_project.targets.each { |t| ... }",
/// );
///
/// // Add a CocoaPod dependency to the Runner target. Passing `platform`
/// // lets the helper create a Podfile of the matching shape when the
/// // project has none (a Swift Package Manager project never does).
/// PodfileEditor.addPodLine(
///   'macos/Podfile',
///   'Runner',
///   "pod 'Firebase/Core', '~> 10.0'",
///   platform: 'macos',
/// );
///
/// // Check whether a pod is already declared.
/// final present = PodfileEditor.hasPod('ios/Podfile', 'Firebase/Core');
/// ```
class PodfileEditor {
  PodfileEditor._();

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Deployment target a created iOS Podfile declares.
  ///
  /// Flutter 3.47's own `flutter create` template ships
  /// `# platform :ios, '15.0'` in `templates/cocoapods/Podfile-ios`, and the
  /// only consumer of this helper in the workspace carries
  /// `IPHONEOS_DEPLOYMENT_TARGET = 15.0` at all three build configurations.
  /// The value is a floor rather than a reading: the project's real target
  /// lives in `Runner.xcodeproj/project.pbxproj`, which this helper is not
  /// given a path to. Declaring less than the project does is the harmful
  /// direction, since CocoaPods would then resolve pod versions older than
  /// the project can use.
  static const String _iosCreatedPlatformVersion = '15.0';

  /// Deployment target a created macOS Podfile declares.
  ///
  /// Mirrors Flutter 3.47's `templates/cocoapods/Podfile-macos`, which
  /// declares `platform :osx, '12.0'` outright (the iOS template leaves its
  /// line commented out).
  static const String _macosCreatedPlatformVersion = '12.0';

  /// Read [podfilePath] and return its contents.
  ///
  /// When the file does not exist yet and [platform] is given, a Flutter-shaped
  /// Podfile for that platform is created first (matching the layout
  /// `flutter create` generates), since a consumer that resolves plugins
  /// through Swift Package Manager may never have had a Podfile at all.
  ///
  /// When [platform] is `null` the absent file is a hard error, which is what
  /// this helper did before create-if-absent existed. A Podfile is
  /// platform-shaped down to the `flutter_install_all_*_pods` call it makes,
  /// so a caller that cannot name its platform cannot have one written for it:
  /// creating the wrong Podfile is worse than creating none.
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param platform     `'ios'`, `'macos'`, or `null` to refuse creation.
  /// @return The file contents.
  /// @throws [FileSystemException] if the file is absent and [platform] is
  ///                               `null`.
  /// @throws [ArgumentError]       if [platform] is neither `'ios'` nor
  ///                               `'macos'`.
  static String _read(String podfilePath, String? platform) {
    final file = File(podfilePath);
    if (!file.existsSync()) {
      if (platform == null) {
        throw FileSystemException('Podfile not found', podfilePath);
      }
      _createFlutterPodfile(file, _platformToken(platform));
    }
    return file.readAsStringSync();
  }

  /// Map a caller-facing platform name onto its CocoaPods DSL token.
  ///
  /// @param platform  Either `'ios'` or `'macos'`.
  /// @return `'ios'` or `'osx'`.
  /// @throws [ArgumentError] if [platform] is not `'ios'` or `'macos'`.
  static String _platformToken(String platform) {
    if (platform == 'ios') {
      return 'ios';
    }
    if (platform == 'macos') {
      return 'osx';
    }
    throw ArgumentError.value(
      platform,
      'platform',
      "Must be 'ios' or 'macos'.",
    );
  }

  /// The `flutter_root` resolver Flutter's `templates/cocoapods/Podfile-ios`
  /// ships, verbatim.
  ///
  /// `podhelper.rb` lives inside the Flutter SDK, whose location is not known
  /// to a Podfile; the SDK writes it into `ios/Flutter/Generated.xcconfig` as
  /// `FLUTTER_ROOT` during `flutter pub get`, and this function reads it back
  /// out. The two `raise` calls are the template's own: a Podfile that cannot
  /// find the SDK has to say why, since the alternative is an `undefined
  /// method` from the first podhelper call.
  static const String _iosFlutterRootFunction = r'''
def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure flutter pub get is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Generated.xcconfig, then run flutter pub get"
end''';

  /// The `flutter_root` resolver Flutter's `templates/cocoapods/Podfile-macos`
  /// ships, verbatim.
  ///
  /// Same job as [_iosFlutterRootFunction] against a different file: the macOS
  /// tooling writes `macos/Flutter/ephemeral/Flutter-Generated.xcconfig`, so a
  /// Podfile reading the iOS path here would raise on every macOS project.
  static const String _macosFlutterRootFunction = r'''
def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'ephemeral', 'Flutter-Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure \"flutter pub get\" is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Flutter-Generated.xcconfig, then run \"flutter pub get\""
end''';

  /// The line that loads Flutter's `podhelper.rb`, relative to `flutter_root`.
  ///
  /// Everything else the created Podfile calls (`flutter_*_podfile_setup`,
  /// `flutter_install_all_*_pods`, `flutter_additional_*_build_settings`) is
  /// defined by this require and by nothing else.
  static const String _podhelperRequire =
      "require File.expand_path(File.join('packages', 'flutter_tools', 'bin', "
      "'podhelper'), flutter_root)";

  /// Create [file] with a Flutter-shaped Podfile for [token], creating parent
  /// directories as needed.
  ///
  /// The content mirrors Flutter 3.47's `templates/cocoapods/Podfile-ios` and
  /// `Podfile-macos`, which is the only shape `pod install` accepts: the
  /// helper calls a Podfile makes are Ruby methods that `podhelper.rb`
  /// defines, so the `flutter_root` resolver and the `require` above them are
  /// load-bearing rather than boilerplate. Emitting the call without the
  /// definition fails with `undefined method` on both platforms.
  ///
  /// The platform decides five things at once and they have to agree: the
  /// `platform :<token>` declaration [setPlatformVersion] later matches on,
  /// the deployment target, the generated xcconfig `flutter_root` reads, the
  /// `flutter_*_podfile_setup` call, and the `flutter_install_all_*_pods` one.
  /// `flutter_install_all_ios_pods` does not exist on the macOS side of
  /// `podhelper.rb`, so writing the iOS shape into `macos/Podfile` fails
  /// `pod install` rather than merely reading oddly.
  ///
  /// Two deliberate divergences from the templates, both so the file survives
  /// this helper's own later edits and a project that is not `flutter create`
  /// fresh:
  ///
  /// - The iOS `platform` line is written uncommented (the template ships it
  ///   commented out). [setPlatformVersion] edits that line, and a commented
  ///   one would leave the bump inert.
  /// - The nested `target 'RunnerTests'` block is omitted. CocoaPods aborts
  ///   when a named target is absent from `Runner.xcodeproj`, and a project
  ///   old enough to have lost its Podfile may have no test target.
  ///
  /// @param file   Target Podfile, which must not exist yet.
  /// @param token  CocoaPods platform token, `'ios'` or `'osx'`.
  static void _createFlutterPodfile(File file, String token) {
    final isIos = token == 'ios';
    final version =
        isIos ? _iosCreatedPlatformVersion : _macosCreatedPlatformVersion;
    final flutterRoot =
        isIos ? _iosFlutterRootFunction : _macosFlutterRootFunction;
    final podfileSetup =
        isIos ? 'flutter_ios_podfile_setup' : 'flutter_macos_podfile_setup';
    final installAllPods = isIos
        ? 'flutter_install_all_ios_pods'
        : 'flutter_install_all_macos_pods';
    final buildSettings = isIos
        ? 'flutter_additional_ios_build_settings'
        : 'flutter_additional_macos_build_settings';

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      "platform :$token, '$version'\n"
      '\n'
      '# CocoaPods analytics sends network stats synchronously affecting '
      'flutter build latency.\n'
      "ENV['COCOAPODS_DISABLE_STATS'] = 'true'\n"
      '\n'
      "project 'Runner', {\n"
      "  'Debug' => :debug,\n"
      "  'Profile' => :release,\n"
      "  'Release' => :release,\n"
      '}\n'
      '\n'
      '$flutterRoot\n'
      '\n'
      '$_podhelperRequire\n'
      '\n'
      '$podfileSetup\n'
      '\n'
      "target 'Runner' do\n"
      '  use_frameworks!\n'
      '\n'
      '  $installAllPods File.dirname(File.realpath(__FILE__))\n'
      'end\n'
      '\n'
      'post_install do |installer|\n'
      '  installer.pods_project.targets.each do |target|\n'
      '    $buildSettings(target)\n'
      '  end\n'
      'end\n',
    );
  }

  /// Overwrite [podfilePath] with [content].
  static void _write(String podfilePath, String content) {
    File(podfilePath).writeAsStringSync(content);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Update or insert the `platform :<token>, '<version>'` line in a Podfile.
  ///
  /// For iOS targets pass `platform = 'ios'`; for macOS pass `platform = 'macos'`
  /// (the method maps `'macos'` to the CocoaPods `:osx` token automatically).
  /// The operation is idempotent: calling it twice with the same version is a
  /// no-op.
  ///
  /// When no matching `platform :*` line exists the declaration is prepended to
  /// the file so it appears before the first `target` block, which matches the
  /// canonical Flutter Podfile layout.
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param platform     Either `'ios'` or `'macos'`.
  /// @param version      CocoaPods deployment target string, e.g. `'13.0'`.
  ///
  /// If [podfilePath] does not exist, a Flutter-shaped Podfile for [platform]
  /// is created first (see [_read]), and the declaration this method writes
  /// then REPLACES the created one instead of joining it.
  ///
  /// @throws [ArgumentError] if [platform] is not `'ios'` or `'macos'`.
  static void setPlatformVersion(
    String podfilePath,
    String platform,
    String version,
  ) {
    // 1. Resolve the CocoaPods DSL token for the requested platform.
    final token = _platformToken(platform);

    var content = _read(podfilePath, platform);

    // 2. Replace an existing `platform :<token>, '...'` line with the new one.
    final existingLine = RegExp("platform :$token, '[^']*'");
    if (existingLine.hasMatch(content)) {
      content = content.replaceFirst(
        existingLine,
        "platform :$token, '$version'",
      );
      _write(podfilePath, content);
      return;
    }

    // 3. No platform line found, prepend the declaration so it precedes all
    //    target blocks (canonical Flutter Podfile layout).
    _write(podfilePath, "platform :$token, '$version'\n\n$content");
  }

  /// Insert [hookContent] inside the `post_install do |installer| ... end`
  /// block of a Podfile.
  ///
  /// If the block does not exist it is created at the end of the file. The
  /// operation is idempotent: if [hookContent] is already present anywhere in
  /// the file it will not be inserted again.
  ///
  /// The [hookContent] string is inserted as-is immediately before the `end`
  /// that closes the post_install block. Callers are responsible for providing
  /// correct indentation (two-space indent is standard for iOS Podfiles).
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param hookContent  One or more Ruby statement lines to inject.
  /// @param platform     `'ios'` or `'macos'`, naming the shape to create when
  ///                     [podfilePath] does not exist yet. Omit it and an
  ///                     absent file throws instead (see [_read]).
  ///
  /// @throws [FileSystemException] if the file is absent and no [platform] was
  ///                               given.
  /// @throws [ArgumentError]       if [platform] is neither `'ios'` nor
  ///                               `'macos'`.
  static void addPostInstallHook(
    String podfilePath,
    String hookContent, {
    String? platform,
  }) {
    var content = _read(podfilePath, platform);

    // 1. Idempotency, skip when hookContent already appears in the file.
    if (content.contains(hookContent)) {
      return;
    }

    // 2. Locate the post_install block and inject before its closing `end`.
    //    The regex matches `post_install do |installer|` followed by any body
    //    and the trailing `end`, capturing everything so we can reconstruct.
    final blockPattern = RegExp(
      r'(post_install do \|installer\|)(.*?)(^end)',
      dotAll: true,
      multiLine: true,
    );

    final match = blockPattern.firstMatch(content);
    if (match != null) {
      // Insert the hook line before the closing `end`.
      final open = match.group(1)!;
      final body = match.group(2)!;
      final close = match.group(3)!;
      content = content.replaceFirst(
        match.group(0)!,
        '$open$body$hookContent\n$close',
      );
      _write(podfilePath, content);
      return;
    }

    // 3. No post_install block exists, append a new one at the end of file.
    final block = '\npost_install do |installer|\n$hookContent\nend\n';
    _write(podfilePath, '${content.trimRight()}\n$block');
  }

  /// Insert [podLine] inside the `target '<targetName>' do ... end` block.
  ///
  /// [podLine] should be a fully-formed CocoaPods pod declaration, e.g.
  /// `pod 'Firebase/Core', '~> 10.0'`. The operation is idempotent: if
  /// [podLine] already appears anywhere in the file it will not be inserted.
  ///
  /// The line is inserted immediately before the `end` that closes the target
  /// block and indented with two spaces, matching Flutter's generated Podfile
  /// style.
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param targetName   CocoaPods target name, typically `'Runner'`.
  /// @param podLine      Full `pod '...'` declaration line.
  /// @param platform     `'ios'` or `'macos'`, naming the shape to create when
  ///                     [podfilePath] does not exist yet. Omit it and an
  ///                     absent file throws instead (see [_read]).
  ///
  /// @throws [StateError]          if no target block matching [targetName] is
  ///                               found in the file.
  /// @throws [FileSystemException] if the file is absent and no [platform] was
  ///                               given.
  /// @throws [ArgumentError]       if [platform] is neither `'ios'` nor
  ///                               `'macos'`.
  static void addPodLine(
    String podfilePath,
    String targetName,
    String podLine, {
    String? platform,
  }) {
    var content = _read(podfilePath, platform);

    // 1. Idempotency, skip when podLine already appears in the file.
    if (content.contains(podLine)) {
      return;
    }

    // 2. Locate the target block for [targetName].
    //    The regex matches `target '<name>' do` … closing `end` non-greedily.
    final blockPattern = RegExp(
      "(target '$targetName' do)(.*?)(^end)",
      dotAll: true,
      multiLine: true,
    );

    final match = blockPattern.firstMatch(content);
    if (match == null) {
      throw StateError(
        "Cannot find target '$targetName' block in Podfile: $podfilePath",
      );
    }

    // 3. Insert the pod line before the block's closing `end`.
    final open = match.group(1)!;
    final body = match.group(2)!;
    final close = match.group(3)!;
    content = content.replaceFirst(
      match.group(0)!,
      '$open$body  $podLine\n$close',
    );

    _write(podfilePath, content);
  }

  /// Return `true` if `pod '<podName>'` is declared anywhere in the Podfile.
  ///
  /// This is a simple substring search, not a structural query. It matches
  /// any line that contains `pod '<podName>'`, regardless of indentation,
  /// version constraint, or surrounding whitespace.
  ///
  /// @param podfilePath  Absolute or relative path to the `Podfile`.
  /// @param podName      The CocoaPods pod name to search for, e.g.
  ///                     `'Firebase/Core'`.
  /// @return `true` if found, `false` otherwise (including when the file
  ///         does not exist).
  static bool hasPod(String podfilePath, String podName) {
    final file = File(podfilePath);
    if (!file.existsSync()) {
      return false;
    }
    return file.readAsStringSync().contains("pod '$podName'");
  }
}
