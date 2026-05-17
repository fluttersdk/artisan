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
  });
}
