import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only driver fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

class _SilentPromptDriver implements PromptDriver {
  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) =>
      defaultValue ?? '';

  @override
  bool confirm(String question, {bool defaultValue = false}) => defaultValue;

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) =>
      defaultValue ?? options.first;

  @override
  String secret(String question) => '';
}

class _SilentStubDriver implements StubDriver {
  @override
  String load(String name, {List<String>? searchPaths}) => '';

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) => '';
}

InstallContext _ctxFor(Directory tempDir) {
  return InstallContext.test(
    fs: const RealFs(),
    prompt: _SilentPromptDriver(),
    stubs: _SilentStubDriver(),
    projectRoot: tempDir.path,
  );
}

// ---------------------------------------------------------------------------
// Fixture writers
// ---------------------------------------------------------------------------

void _writeAndroidManifest(Directory root) {
  final path =
      p.join(root.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
  File(path).createSync(recursive: true);
  File(path).writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">
    <application
        android:label="app"
        android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" />
    </application>
</manifest>
''');
}

void _writeAppBuildGradleKts(Directory root) {
  final path = p.join(root.path, 'android', 'app', 'build.gradle.kts');
  File(path).createSync(recursive: true);
  File(path).writeAsStringSync('''
plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.app"
    compileSdk = 34
}

dependencies {
    implementation("androidx.core:core-ktx:1.10.0")
}
''');
}

void _writeIosPlistAndPodfile(Directory root, {String platform = 'ios'}) {
  final plistPath = p.join(root.path, platform, 'Runner', 'Info.plist');
  File(plistPath).createSync(recursive: true);
  File(plistPath).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>Runner</string>
</dict>
</plist>
''');

  final podfilePath = p.join(root.path, platform, 'Podfile');
  File(podfilePath).createSync(recursive: true);
  File(podfilePath).writeAsStringSync('''
platform :ios, '13.0'

target 'Runner' do
  use_frameworks!
end
''');

  // Runner.entitlements
  final entitlementsPath =
      p.join(root.path, platform, 'Runner', 'Runner.entitlements');
  File(entitlementsPath).createSync(recursive: true);
  File(entitlementsPath).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
</dict>
</plist>
''');
}

void main() {
  group('PluginInstaller — native chain methods (enqueue)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_nat_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectAndroidPermission / injectAndroidMetaData enqueue ops', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectAndroidPermission('android.permission.INTERNET')
          .injectAndroidMetaData(name: 'io.app.icon', value: '@mipmap/ic');

      expect(installer.pendingCount, 2);
      expect(installer.pendingOps[0], isA<InjectAndroidPermission>());
      expect(installer.pendingOps[1], isA<InjectAndroidMetaData>());
    });

    test('injectInfoPlistKey carries explicit platform', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectInfoPlistKey(
        key: 'NSCameraUsageDescription',
        value: 'Camera',
        platform: 'macos',
      );
      final op = installer.pendingOps.single as InjectInfoPlistKey;
      expect(op.platform, 'macos');
      expect(op.value, 'Camera');
    });

    test('injectEntitlement enqueues with explicit platform', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectEntitlement(
        platform: 'macos',
        key: 'com.apple.security.network.client',
        value: true,
      );
      final op = installer.pendingOps.single as InjectEntitlement;
      expect(op.platform, 'macos');
      expect(op.value, isTrue);
    });

    test(
        'injectPodfileLine / injectGradlePlugin / injectGradleDependency '
        'enqueue ops', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectPodfileLine(line: "pod 'Firebase/Core'")
          .injectGradlePlugin(
              pluginId: 'com.google.gms.google-services', version: '4.4.2')
          .injectGradleDependency(
              scope: 'implementation', notation: 'androidx.x:x:1.0');

      expect(installer.pendingCount, 3);
      expect(installer.pendingOps[0], isA<InjectPodfileLine>());
      expect(installer.pendingOps[1], isA<InjectGradlePlugin>());
      expect(installer.pendingOps[2], isA<InjectGradleDependency>());
    });
  });

  group('PluginInstaller — native dispatcher (Android present)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_nat_droid_');
      _writeAndroidManifest(tempDir);
      _writeAppBuildGradleKts(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectAndroidPermission writes <uses-permission> tag', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectAndroidPermission('android.permission.INTERNET');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final manifest = File(p.join(tempDir.path, 'android', 'app', 'src',
              'main', 'AndroidManifest.xml'))
          .readAsStringSync();
      expect(manifest, contains('android.permission.INTERNET'));
    });

    test('injectAndroidMetaData writes <meta-data> entry', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectAndroidMetaData(name: 'io.icon', value: '@mipmap/ic');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final manifest = File(p.join(tempDir.path, 'android', 'app', 'src',
              'main', 'AndroidManifest.xml'))
          .readAsStringSync();
      expect(manifest, contains('io.icon'));
      expect(manifest, contains('@mipmap/ic'));
    });

    test('injectGradlePlugin adds id("...") inside plugins block', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectGradlePlugin(
              pluginId: 'com.google.gms.google-services', version: '4.4.2');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final gradle =
          File(p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'))
              .readAsStringSync();
      expect(gradle, contains('com.google.gms.google-services'));
      expect(gradle, contains('"4.4.2"'));
    });

    test('injectGradleDependency adds line inside dependencies block',
        () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectGradleDependency(
              scope: 'implementation', notation: 'com.x:y:1.0');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final gradle =
          File(p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'))
              .readAsStringSync();
      expect(gradle, contains('implementation("com.x:y:1.0")'));
    });
  });

  group('PluginInstaller — native dispatcher (iOS present)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_nat_ios_');
      _writeIosPlistAndPodfile(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectInfoPlistKey (String value) calls setStringKey', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectInfoPlistKey(
        key: 'NSCameraUsageDescription',
        value: 'Camera access needed.',
      );

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final plist = File(p.join(tempDir.path, 'ios', 'Runner', 'Info.plist'))
          .readAsStringSync();
      expect(plist, contains('NSCameraUsageDescription'));
      expect(plist, contains('Camera access needed.'));
    });

    test('injectInfoPlistKey (bool value) calls setBoolKey', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectInfoPlistKey(
        key: 'UIRequiresFullScreen',
        value: true,
      );

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final plist = File(p.join(tempDir.path, 'ios', 'Runner', 'Info.plist'))
          .readAsStringSync();
      expect(plist, contains('UIRequiresFullScreen'));
      expect(plist, contains('<true/>'));
    });

    test('injectInfoPlistKey returns Error for unsupported value type',
        () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectInfoPlistKey(key: 'Bad', value: 42);

      final result = await installer.commit(force: true);
      expect(result, isA<Error>());
      expect((result as Error).error, contains('unsupported value type'));
    });

    test('injectEntitlement writes bool key to Runner.entitlements', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectEntitlement(
        platform: 'ios',
        key: 'com.apple.security.network.client',
        value: true,
      );

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final entitlements =
          File(p.join(tempDir.path, 'ios', 'Runner', 'Runner.entitlements'))
              .readAsStringSync();
      expect(entitlements, contains('com.apple.security.network.client'));
      expect(entitlements, contains('<true/>'));
    });

    test('injectPodfileLine appends inside Runner target block', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectPodfileLine(line: "pod 'Firebase/Core'");

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final podfile =
          File(p.join(tempDir.path, 'ios', 'Podfile')).readAsStringSync();
      expect(podfile, contains("pod 'Firebase/Core'"));
    });
  });

  group('PluginInstaller — native dispatcher (platform absent = no-op)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_nat_empty_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectAndroidPermission on non-Android project commits Success',
        () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectAndroidPermission('android.permission.INTERNET');

      final result = await installer.commit();
      expect(result, isA<Success>());
      // No android/ dir created as a side effect.
      expect(Directory(p.join(tempDir.path, 'android')).existsSync(), isFalse);
    });

    test('injectInfoPlistKey on non-iOS project commits Success', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectInfoPlistKey(key: 'NSCameraUsageDescription', value: 'X');

      final result = await installer.commit();
      expect(result, isA<Success>());
      expect(Directory(p.join(tempDir.path, 'ios')).existsSync(), isFalse);
    });

    test('injectPodfileLine on non-iOS project commits Success', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectPodfileLine(line: "pod 'Firebase/Core'");

      final result = await installer.commit();
      expect(result, isA<Success>());
    });
  });
}
