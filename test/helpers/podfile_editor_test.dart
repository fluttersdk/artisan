import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Minimal iOS Podfile fixture that mirrors the shape Flutter generates.
const String _iosFixture = """
platform :ios, '12.0'

target 'Runner' do
  use_frameworks!
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
""";

/// Minimal Podfile with no `post_install` block — used to test block creation.
const String _noPostInstallFixture = """
platform :ios, '12.0'

target 'Runner' do
  use_frameworks!
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
""";

/// Minimal Podfile with no `platform` line — used to test insertion.
const String _noPlatformFixture = """
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
""";

/// The `require` line Flutter's `templates/cocoapods/Podfile-*` emit.
///
/// It is the only thing that DEFINES `flutter_install_all_ios_pods` and
/// `flutter_install_all_macos_pods`; a Podfile that calls one of them without
/// this line fails `pod install` with `undefined method`.
const String _podhelperRequire =
    "require File.expand_path(File.join('packages', 'flutter_tools', 'bin', "
    "'podhelper'), flutter_root)";

void main() {
  group('PodfileEditor', () {
    late Directory tempDir;
    late String podfilePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('podfile_editor_');
      podfilePath = p.join(tempDir.path, 'Podfile');
      File(podfilePath).writeAsStringSync(_iosFixture);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // setPlatformVersion
    // -------------------------------------------------------------------------

    test(
        'setPlatformVersion :ios updates existing platform line (12.0 -> 13.0)',
        () {
      PodfileEditor.setPlatformVersion(podfilePath, 'ios', '13.0');

      final content = File(podfilePath).readAsStringSync();
      expect(content, contains("platform :ios, '13.0'"));
      expect(content, isNot(contains("platform :ios, '12.0'")));
    });

    test('setPlatformVersion :ios inserts when no platform line exists', () {
      File(podfilePath).writeAsStringSync(_noPlatformFixture);

      PodfileEditor.setPlatformVersion(podfilePath, 'ios', '13.0');

      final content = File(podfilePath).readAsStringSync();
      expect(content, contains("platform :ios, '13.0'"));
    });

    test('setPlatformVersion :osx writes macOS platform token', () {
      File(podfilePath).writeAsStringSync(_noPlatformFixture);

      PodfileEditor.setPlatformVersion(podfilePath, 'macos', '12.0');

      final content = File(podfilePath).readAsStringSync();
      expect(content, contains("platform :osx, '12.0'"));
    });

    // -------------------------------------------------------------------------
    // addPostInstallHook
    // -------------------------------------------------------------------------

    test('addPostInstallHook appends content inside existing block', () {
      const hookContent =
          "  installer.pods_project.targets.each { |t| t.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0' } }";

      PodfileEditor.addPostInstallHook(podfilePath, hookContent);

      final content = File(podfilePath).readAsStringSync();
      expect(content, contains(hookContent));
    });

    test('addPostInstallHook is idempotent on duplicate content', () {
      const hookContent = "  installer.generate_module_map = false";

      PodfileEditor.addPostInstallHook(podfilePath, hookContent);
      PodfileEditor.addPostInstallHook(podfilePath, hookContent);

      final content = File(podfilePath).readAsStringSync();
      final occurrences = hookContent.allMatches(content).length;
      expect(occurrences, 1);
    });

    test('addPostInstallHook creates post_install block when one is missing',
        () {
      File(podfilePath).writeAsStringSync(_noPostInstallFixture);
      const hookContent = "  installer.generate_module_map = false";

      PodfileEditor.addPostInstallHook(podfilePath, hookContent);

      final content = File(podfilePath).readAsStringSync();
      expect(content, contains('post_install do |installer|'));
      expect(content, contains(hookContent));
    });

    // -------------------------------------------------------------------------
    // addPodLine
    // -------------------------------------------------------------------------

    test('addPodLine inserts pod line inside the named target block', () {
      PodfileEditor.addPodLine(
        podfilePath,
        'Runner',
        "pod 'Firebase/Core', '~> 10.0'",
      );

      final content = File(podfilePath).readAsStringSync();
      expect(content, contains("pod 'Firebase/Core', '~> 10.0'"));
    });

    test('addPodLine is idempotent when pod line already exists', () {
      const podLine = "pod 'Firebase/Core', '~> 10.0'";

      PodfileEditor.addPodLine(podfilePath, 'Runner', podLine);
      PodfileEditor.addPodLine(podfilePath, 'Runner', podLine);

      final content = File(podfilePath).readAsStringSync();
      final occurrences = podLine.allMatches(content).length;
      expect(occurrences, 1);
    });

    // -------------------------------------------------------------------------
    // hasPod
    // -------------------------------------------------------------------------

    test('hasPod returns true when pod line is present', () {
      PodfileEditor.addPodLine(podfilePath, 'Runner', "pod 'Firebase/Core'");

      expect(PodfileEditor.hasPod(podfilePath, 'Firebase/Core'), isTrue);
    });

    test('hasPod returns false when pod is not present', () {
      expect(PodfileEditor.hasPod(podfilePath, 'SomeNonExistentPod'), isFalse);
    });

    // -------------------------------------------------------------------------
    // Create-if-absent
    // -------------------------------------------------------------------------

    test('addPodLine creates an iOS-shaped Podfile when absent', () {
      final absentPodfilePath = p.join(tempDir.path, 'ios', 'Podfile');
      expect(File(absentPodfilePath).existsSync(), isFalse);

      PodfileEditor.addPodLine(
        absentPodfilePath,
        'Runner',
        "pod 'Firebase/Core', '~> 10.0'",
        platform: 'ios',
      );

      final content = File(absentPodfilePath).readAsStringSync();
      expect(content, contains("platform :ios, '15.0'"));
      expect(content, contains("target 'Runner' do"));
      expect(content, contains('use_frameworks!'));
      expect(content, contains(_podhelperRequire));
      expect(content, contains('flutter_install_all_ios_pods'));
      expect(content, isNot(contains('flutter_install_all_macos_pods')));
      expect(content, contains("pod 'Firebase/Core', '~> 10.0'"));
      expect(content, contains('end'));
      expect(_platformLinesIn(content), hasLength(1));
    });

    test('addPodLine creates a macOS-shaped Podfile when absent', () {
      final absentPodfilePath = p.join(tempDir.path, 'macos', 'Podfile');
      expect(File(absentPodfilePath).existsSync(), isFalse);

      PodfileEditor.addPodLine(
        absentPodfilePath,
        'Runner',
        "pod 'OneSignalXCFramework', '5.2.7'",
        platform: 'macos',
      );

      final content = File(absentPodfilePath).readAsStringSync();
      expect(content, contains("platform :osx, '12.0'"));
      expect(content, contains('flutter_install_all_macos_pods'));
      expect(content, isNot(contains('flutter_install_all_ios_pods')));
      expect(content, contains("pod 'OneSignalXCFramework', '5.2.7'"));
      expect(_platformLinesIn(content), hasLength(1));
    });

    test(
        'setPlatformVersion :macos REPLACES the platform line of a Podfile it '
        'just created', () {
      final absentPodfilePath = p.join(tempDir.path, 'macos', 'Podfile');

      // The sequence a manifest install runs: a pod line first (which creates
      // the file), then the deployment-target bump on the same path.
      PodfileEditor.addPodLine(
        absentPodfilePath,
        'Runner',
        "pod 'OneSignalXCFramework', '5.2.7'",
        platform: 'macos',
      );
      PodfileEditor.setPlatformVersion(absentPodfilePath, 'macos', '13.0');

      final content = File(absentPodfilePath).readAsStringSync();
      expect(_platformLinesIn(content), ["platform :osx, '13.0'"]);
      expect(content, contains('flutter_install_all_macos_pods'));
    });

    test(
        'setPlatformVersion :ios REPLACES the platform line of a Podfile it '
        'just created', () {
      final absentPodfilePath = p.join(tempDir.path, 'ios', 'Podfile');

      PodfileEditor.addPodLine(
        absentPodfilePath,
        'Runner',
        "pod 'Firebase/Core'",
        platform: 'ios',
      );
      PodfileEditor.setPlatformVersion(absentPodfilePath, 'ios', '16.0');

      final content = File(absentPodfilePath).readAsStringSync();
      expect(_platformLinesIn(content), ["platform :ios, '16.0'"]);
      expect(content, contains('flutter_install_all_ios_pods'));
    });

    test('setPlatformVersion creates the Podfile for its own platform', () {
      final iosPath = p.join(tempDir.path, 'created_ios', 'Podfile');
      final macosPath = p.join(tempDir.path, 'created_macos', 'Podfile');

      PodfileEditor.setPlatformVersion(iosPath, 'ios', '17.0');
      PodfileEditor.setPlatformVersion(macosPath, 'macos', '14.0');

      final iosContent = File(iosPath).readAsStringSync();
      expect(_platformLinesIn(iosContent), ["platform :ios, '17.0'"]);
      expect(iosContent, contains('flutter_install_all_ios_pods'));

      final macosContent = File(macosPath).readAsStringSync();
      expect(_platformLinesIn(macosContent), ["platform :osx, '14.0'"]);
      expect(macosContent, contains('flutter_install_all_macos_pods'));
    });

    test('addPostInstallHook creates a macOS-shaped Podfile when absent', () {
      final absentPodfilePath = p.join(tempDir.path, 'macos', 'Podfile');

      PodfileEditor.addPostInstallHook(
        absentPodfilePath,
        '  installer.generate_module_map = false',
        platform: 'macos',
      );

      final content = File(absentPodfilePath).readAsStringSync();
      expect(_platformLinesIn(content), ["platform :osx, '12.0'"]);
      expect(content, contains('flutter_install_all_macos_pods'));
      expect(content, contains('  installer.generate_module_map = false'));
    });

    test(
        'a created iOS Podfile defines the helper it calls: podhelper require, '
        'flutter_root, setup', () {
      final absentPodfilePath = p.join(tempDir.path, 'ios', 'Podfile');

      PodfileEditor.addPodLine(
        absentPodfilePath,
        'Runner',
        "pod 'Firebase/Core'",
        platform: 'ios',
      );

      final content = File(absentPodfilePath).readAsStringSync();

      // 1. The require that DEFINES flutter_install_all_ios_pods, and the
      //    flutter_root it needs, resolved from Generated.xcconfig the way
      //    Flutter's own templates/cocoapods/Podfile-ios resolves it.
      expect(content, contains(_podhelperRequire));
      expect(content, contains('def flutter_root'));
      expect(
        content,
        contains("File.join('..', 'Flutter', 'Generated.xcconfig')"),
      );
      expect(
        content,
        contains('unless File.exist?(generated_xcode_build_settings_path)'),
      );
      expect(content, contains('raise'));
      expect(content, contains(r'line.match(/FLUTTER_ROOT\=(.*)/)'));

      // 2. The iOS setup call, after the require and before the target block.
      expect(content, contains('flutter_ios_podfile_setup'));
      expect(content, isNot(contains('flutter_macos_podfile_setup')));
      expect(
        content.indexOf('flutter_ios_podfile_setup'),
        greaterThan(content.indexOf(_podhelperRequire)),
      );
      expect(
        content.indexOf(_podhelperRequire),
        lessThan(content.indexOf("target 'Runner' do")),
      );

      // 3. The platform-matched install and build-settings helpers, once.
      expect(content, contains('flutter_install_all_ios_pods'));
      expect(content, contains('flutter_additional_ios_build_settings'));
      expect(content, isNot(contains('_macos_')));
      expect(_platformLinesIn(content), ["platform :ios, '15.0'"]);
    });

    test(
        'a created macOS Podfile defines the helper it calls: podhelper '
        'require, flutter_root, setup', () {
      final absentPodfilePath = p.join(tempDir.path, 'macos', 'Podfile');

      PodfileEditor.addPodLine(
        absentPodfilePath,
        'Runner',
        "pod 'OneSignalXCFramework', '5.2.7'",
        platform: 'macos',
      );

      final content = File(absentPodfilePath).readAsStringSync();

      // 1. Same require, but macOS reads a different generated xcconfig.
      expect(content, contains(_podhelperRequire));
      expect(content, contains('def flutter_root'));
      expect(
        content,
        contains(
          "File.join('..', 'Flutter', 'ephemeral', 'Flutter-Generated.xcconfig')",
        ),
      );
      expect(
        content,
        contains('unless File.exist?(generated_xcode_build_settings_path)'),
      );
      expect(content, contains('raise'));

      // 2. The macOS setup call, after the require and before the target.
      expect(content, contains('flutter_macos_podfile_setup'));
      expect(content, isNot(contains('flutter_ios_podfile_setup')));
      expect(
        content.indexOf('flutter_macos_podfile_setup'),
        greaterThan(content.indexOf(_podhelperRequire)),
      );
      expect(
        content.indexOf(_podhelperRequire),
        lessThan(content.indexOf("target 'Runner' do")),
      );

      // 3. The platform-matched install and build-settings helpers, once.
      expect(content, contains('flutter_install_all_macos_pods'));
      expect(content, contains('flutter_additional_macos_build_settings'));
      expect(content, isNot(contains('_ios_')));
      expect(_platformLinesIn(content), ["platform :osx, '12.0'"]);
    });

    test('a created Podfile keeps its require when later edits land on it', () {
      final absentPodfilePath = p.join(tempDir.path, 'macos', 'Podfile');

      // The sequence a manifest install runs against one path.
      PodfileEditor.addPodLine(
        absentPodfilePath,
        'Runner',
        "pod 'OneSignalXCFramework', '5.2.7'",
        platform: 'macos',
      );
      PodfileEditor.setPlatformVersion(absentPodfilePath, 'macos', '13.0');
      PodfileEditor.addPostInstallHook(
        absentPodfilePath,
        '  installer.generate_module_map = false',
        platform: 'macos',
      );

      final content = File(absentPodfilePath).readAsStringSync();
      expect(_podhelperRequire.allMatches(content), hasLength(1));
      expect(_platformLinesIn(content), ["platform :osx, '13.0'"]);
      expect(content, contains("pod 'OneSignalXCFramework', '5.2.7'"));
      expect(content, contains('  installer.generate_module_map = false'));
    });

    test('addPodLine refuses to create a Podfile with no platform given', () {
      final absentPodfilePath = p.join(tempDir.path, 'unknown', 'Podfile');

      expect(
        () => PodfileEditor.addPodLine(
          absentPodfilePath,
          'Runner',
          "pod 'Firebase/Core'",
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(absentPodfilePath).existsSync(), isFalse);
    });

    test(
        'addPostInstallHook refuses to create a Podfile with no platform given',
        () {
      final absentPodfilePath = p.join(tempDir.path, 'unknown', 'Podfile');

      expect(
        () => PodfileEditor.addPostInstallHook(
          absentPodfilePath,
          '  installer.generate_module_map = false',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(absentPodfilePath).existsSync(), isFalse);
    });

    test('a rejected platform never creates a Podfile', () {
      final absentPodfilePath = p.join(tempDir.path, 'tvos', 'Podfile');

      expect(
        () => PodfileEditor.addPodLine(
          absentPodfilePath,
          'Runner',
          "pod 'Firebase/Core'",
          platform: 'tvos',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(File(absentPodfilePath).existsSync(), isFalse);
    });
  });
}

/// Return every `platform :<token>, '<version>'` declaration in [content].
///
/// The Podfile DSL takes a single global platform, so a file carrying two of
/// them is broken regardless of which two: CocoaPods reads the last one and
/// the operator reads the first.
///
/// @param content  Full Podfile text read back off disk.
/// @return The matched declaration lines, in file order.
List<String> _platformLinesIn(String content) {
  return RegExp(r"^platform :\w+, '[^']*'", multiLine: true)
      .allMatches(content)
      .map((match) => match.group(0)!)
      .toList();
}
