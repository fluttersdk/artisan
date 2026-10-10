import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

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

/// Mirrors the shape of a real Flutter app manifest: MainActivity with
/// singleTop and a host-wide autoVerify App Link filter, the Flutter
/// deep-linking meta-data, comments, and the nodes around `<application>`.
const String _appShapedManifest =
    '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="Example"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <!-- The portrait lock below is deliberate; a phone-only design. -->
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <!-- Hands the App Link back to the validated handler. -->
            <meta-data
                android:name="flutter_deeplinking_enabled"
                android:value="false"/>
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="http"/>
                <data android:scheme="https"/>
                <data android:host="app.example.com"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below. -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
</manifest>
''';

// Debug signs with Runner.entitlements and Release with its twin, the way a
// project with a per-build aps-environment does.
const String _splitPbxproj = r'''// !$*UTF8*$!
{
  archiveVersion = 1;
  objects = {
    1A00000000000000000001 /* Runner */ = {
      isa = PBXNativeTarget;
      buildConfigurationList = 1A00000000000000000002 /* Runner */;
      name = Runner;
      productType = "com.apple.product-type.application";
    };
    1A00000000000000000002 /* Runner */ = {
      isa = XCConfigurationList;
      buildConfigurations = (
        1A00000000000000000003 /* Debug */,
        1A00000000000000000004 /* Release */,
      );
    };
    1A00000000000000000003 /* Debug */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;
      };
      name = Debug;
    };
    1A00000000000000000004 /* Release */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements;
      };
      name = Release;
    };
  };
  rootObject = 1A00000000000000000000 /* Project object */;
}
''';

const String _emptyEntitlements = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
</dict>
</plist>
''';

const String _callbackName = 'com.linusu.flutter_web_auth_2.CallbackActivity';

const AndroidIntentFilter _callbackFilter = AndroidIntentFilter(
  autoVerify: true,
  actions: ['android.intent.action.VIEW'],
  categories: [
    'android.intent.category.DEFAULT',
    'android.intent.category.BROWSABLE',
  ],
  data: [
    AndroidIntentData(
      scheme: 'https',
      host: 'auth.example.com',
      path: '/social/callback',
    ),
  ],
);

void _writeAppShapedManifest(Directory root, [String? content]) {
  File(p.join(
    root.path,
    'android',
    'app',
    'src',
    'main',
    'AndroidManifest.xml',
  ))
    ..createSync(recursive: true)
    ..writeAsStringSync(content ?? _appShapedManifest);
}

String _readManifest(Directory root) => File(p.join(
      root.path,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    )).readAsStringSync();

int _callbackActivityCount(String manifest) => XmlDocument.parse(manifest)
    .findAllElements('activity')
    .where((e) => e.getAttribute('android:name') == _callbackName)
    .length;

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

    test('injectAndroidActivity enqueues an op carrying every field', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectAndroidActivity(
        name: _callbackName,
        exported: true,
        taskAffinity: '',
        intentFilters: const [_callbackFilter],
      );

      final op = installer.pendingOps.single as InjectAndroidActivity;
      expect(op.name, _callbackName);
      expect(op.exported, isTrue);
      expect(op.taskAffinity, '');
      expect(op.intentFilters, const [_callbackFilter]);
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

    test('injectInfoPlistUrlScheme enqueues with the ios default', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectInfoPlistUrlScheme(scheme: 'com.example.app');
      final op = installer.pendingOps.single as InjectInfoPlistUrlScheme;
      expect(op.platform, 'ios');
      expect(op.scheme, 'com.example.app');
    });

    test('injectInfoPlistUrlScheme carries an explicit platform', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectInfoPlistUrlScheme(
              scheme: 'com.example.app', platform: 'macos');
      expect(
        (installer.pendingOps.single as InjectInfoPlistUrlScheme).platform,
        'macos',
      );
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

  group('PluginInstaller: injectAndroidActivity dispatcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_nat_activity_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    PluginInstaller installerFor(InstallContext ctx) {
      return PluginInstaller(ctx, pluginName: 'demo').injectAndroidActivity(
        name: _callbackName,
        exported: true,
        taskAffinity: '',
        intentFilters: const [_callbackFilter],
      );
    }

    test(
        'lands the activity inside <application> and leaves MainActivity alone',
        () async {
      _writeAppShapedManifest(tempDir);

      final result = await installerFor(_ctxFor(tempDir)).commit(force: true);

      expect(result, isA<Success>());
      final manifest = _readManifest(tempDir);
      expect(_callbackActivityCount(manifest), 1);
      // The original text is intact on both sides of the new block.
      final seam = _appShapedManifest.indexOf('    </application>');
      expect(manifest, startsWith(_appShapedManifest.substring(0, seam)));
      expect(manifest, endsWith(_appShapedManifest.substring(seam)));
    });

    test('an existing activity with another host is kept and reported',
        () async {
      final handEdited = _appShapedManifest.replaceFirst(
        '    </application>',
        '''        <activity android:name="$_callbackName" android:exported="true">
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="old.example.com" android:path="/social/callback"/>
            </intent-filter>
        </activity>
    </application>''',
      );
      _writeAppShapedManifest(tempDir, handEdited);
      final ctx = _ctxFor(tempDir);

      final result = await installerFor(ctx).commit(force: true);

      expect(result, isA<Success>());
      expect(_readManifest(tempDir), handEdited);
      final output = (ctx.artisanContext.output as BufferedOutput).content;
      expect(output, contains(_callbackName));
      expect(output, contains('AndroidManifest.xml'));
      // The warning carries the block that would have been written.
      expect(output, contains('android:host="auth.example.com"'));
      expect(output, contains('android:path="/social/callback"'));
    });

    test('a project without android/ is a no-op', () async {
      final result = await installerFor(_ctxFor(tempDir)).commit();

      expect(result, isA<Success>());
      expect(Directory(p.join(tempDir.path, 'android')).existsSync(), isFalse);
    });
  });

  group('PluginInstaller: social callback install on RealFs', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('plinst_nat_social_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
        'URL scheme, split entitlements and CallbackActivity in one run, twice: '
        'the second run leaves every file byte-identical', () async {
      _writeAppShapedManifest(root);
      File(p.join(root.path, 'ios', 'Runner', 'Info.plist'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>Runner</string>
</dict>
</plist>
''');
      for (final name in const ['Runner', 'RunnerRelease']) {
        File(p.join(root.path, 'ios', 'Runner', '$name.entitlements'))
            .writeAsStringSync(_emptyEntitlements);
      }
      File(p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_splitPbxproj);
      final files = <String, File>{
        'Info.plist': File(p.join(root.path, 'ios', 'Runner', 'Info.plist')),
        'Runner.entitlements':
            File(p.join(root.path, 'ios', 'Runner', 'Runner.entitlements')),
        'RunnerRelease.entitlements': File(
            p.join(root.path, 'ios', 'Runner', 'RunnerRelease.entitlements')),
        'project.pbxproj': File(
            p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj')),
        'AndroidManifest.xml': File(p.join(
            root.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')),
      };

      Future<void> run() async {
        final result = await PluginInstaller(
          _ctxFor(root),
          pluginName: 'demo',
        ).injectInfoPlistUrlScheme(scheme: 'com.example.app').injectEntitlement(
          platform: 'ios',
          key: 'com.apple.developer.applesignin',
          value: const ['Default'],
        ).injectAndroidActivity(
          name: _callbackName,
          exported: true,
          taskAffinity: '',
          intentFilters: const [_callbackFilter],
        ).commit(force: true);
        expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');
      }

      await run();
      final afterFirst = {
        for (final entry in files.entries)
          entry.key: entry.value.readAsStringSync(),
      };

      // 1. The first run did the work in every file.
      expect(afterFirst['Info.plist'],
          contains('<string>com.example.app</string>'));
      for (final name in const [
        'Runner.entitlements',
        'RunnerRelease.entitlements',
      ]) {
        expect(afterFirst[name], contains('com.apple.developer.applesignin'));
        expect(afterFirst[name], contains('<string>Default</string>'));
      }
      expect(afterFirst['project.pbxproj'], _splitPbxproj);
      expect(_callbackActivityCount(afterFirst['AndroidManifest.xml']!), 1);

      // 2. The second run changes nothing.
      await run();
      for (final entry in files.entries) {
        expect(entry.value.readAsStringSync(), afterFirst[entry.key],
            reason: '${entry.key} drifted on the second run');
      }
      expect(
          _callbackActivityCount(
              files['AndroidManifest.xml']!.readAsStringSync()),
          1);
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
