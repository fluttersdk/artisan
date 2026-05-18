import 'package:test/test.dart';

// ignore_for_file: unused_local_variable
// Tests import the implementation once it exists.
// This file is the red-phase: all tests will fail until install_operation.dart
// is written.

import 'package:fluttersdk_artisan/artisan.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AddDependency
  // ---------------------------------------------------------------------------

  test('AddDependency.describe outputs [add-dep] for a regular dependency', () {
    const op = AddDependency(name: 'foo', version: '^1.0.0');
    expect(op.describe(), '[add-dep] foo: ^1.0.0');
  });

  test('AddDependency.describe outputs [add-dev-dep] for a dev dependency', () {
    const op = AddDependency(name: 'foo', version: '^1.0.0', isDev: true);
    expect(op.describe(), '[add-dev-dep] foo: ^1.0.0');
  });

  // ---------------------------------------------------------------------------
  // AddPathDependency
  // ---------------------------------------------------------------------------

  test('AddPathDependency.describe outputs [add-path-dep]', () {
    const op = AddPathDependency(name: 'my_lib', path: '../my_lib');
    expect(op.describe(), '[add-path-dep] my_lib: ../my_lib');
  });

  // ---------------------------------------------------------------------------
  // RemoveDependency
  // ---------------------------------------------------------------------------

  test('RemoveDependency.describe outputs [remove-dep]', () {
    const op = RemoveDependency(name: 'old_lib');
    expect(op.describe(), '[remove-dep] old_lib');
  });

  // ---------------------------------------------------------------------------
  // AddPubspecAsset
  // ---------------------------------------------------------------------------

  test('AddPubspecAsset.describe outputs [add-asset]', () {
    const op = AddPubspecAsset(assetPath: 'assets/config.json');
    expect(op.describe(), '[add-asset] assets/config.json');
  });

  // ---------------------------------------------------------------------------
  // PublishFile
  // ---------------------------------------------------------------------------

  test('PublishFile.describe outputs [publish] with arrow between paths', () {
    const op = PublishFile(
      sourceStubName: 'config/x.stub',
      targetPath: 'lib/config/x.dart',
      replacements: <String, String>{'KEY': 'value'},
    );
    expect(op.describe(), '[publish] config/x.stub -> lib/config/x.dart');
  });

  // ---------------------------------------------------------------------------
  // WriteFile
  // ---------------------------------------------------------------------------

  test('WriteFile.describe outputs [write-file] with target path', () {
    const op =
        WriteFile(targetPath: 'lib/generated/foo.dart', content: '// auto');
    expect(op.describe(), '[write-file] lib/generated/foo.dart');
  });

  // ---------------------------------------------------------------------------
  // DeleteFile
  // ---------------------------------------------------------------------------

  test('DeleteFile.describe outputs [delete-file] with target path', () {
    const op = DeleteFile(targetPath: 'lib/old/legacy.dart');
    expect(op.describe(), '[delete-file] lib/old/legacy.dart');
  });

  // ---------------------------------------------------------------------------
  // CopyFile
  // ---------------------------------------------------------------------------

  test('CopyFile.describe outputs [copy-file] with source and target', () {
    const op = CopyFile(
        sourcePath: 'assets/template.dart', targetPath: 'lib/out.dart');
    expect(op.describe(), '[copy-file] assets/template.dart -> lib/out.dart');
  });

  // ---------------------------------------------------------------------------
  // MergeJson
  // ---------------------------------------------------------------------------

  test('MergeJson.describe outputs [merge-json] for additive merge', () {
    const op = MergeJson(
      targetPath: 'assets/lang/en.json',
      sourceData: <String, dynamic>{'key': 'val'},
    );
    expect(op.describe(), '[merge-json] assets/lang/en.json (additive)');
  });

  test(
      'MergeJson.describe outputs [merge-json] with override mode when additive=false',
      () {
    const op = MergeJson(
      targetPath: 'assets/lang/en.json',
      sourceData: <String, dynamic>{'key': 'val'},
      additive: false,
    );
    expect(op.describe(), '[merge-json] assets/lang/en.json (override)');
  });

  // ---------------------------------------------------------------------------
  // InjectImport
  // ---------------------------------------------------------------------------

  test('InjectImport.describe outputs [inject-import] with file and statement',
      () {
    const op = InjectImport(
      targetFile: 'lib/main.dart',
      importStatement: "import 'package:my_pkg/my_pkg.dart';",
    );
    expect(
      op.describe(),
      "[inject-import] lib/main.dart: import 'package:my_pkg/my_pkg.dart';",
    );
  });

  // ---------------------------------------------------------------------------
  // InjectBeforePattern
  // ---------------------------------------------------------------------------

  test(
      'InjectBeforePattern.describe outputs [inject-before] with file and pattern',
      () {
    final op = InjectBeforePattern(
      targetFile: 'lib/main.dart',
      pattern: RegExp(r'Magic\.init'),
      code: '// setup',
    );
    expect(op.describe(), contains('[inject-before] lib/main.dart:'));
  });

  // ---------------------------------------------------------------------------
  // InjectAfterPattern
  // ---------------------------------------------------------------------------

  test(
      'InjectAfterPattern.describe outputs [inject-after] with file and pattern',
      () {
    final op = InjectAfterPattern(
      targetFile: 'lib/main.dart',
      pattern: RegExp(r'Magic\.init'),
      code: '// teardown',
    );
    expect(op.describe(), contains('[inject-after] lib/main.dart:'));
  });

  // ---------------------------------------------------------------------------
  // InjectAndroidPermission
  // ---------------------------------------------------------------------------

  test('InjectAndroidPermission.describe outputs [inject-android-perm]', () {
    const op =
        InjectAndroidPermission(permission: 'android.permission.INTERNET');
    expect(op.describe(), '[inject-android-perm] android.permission.INTERNET');
  });

  // ---------------------------------------------------------------------------
  // InjectAndroidMetaData
  // ---------------------------------------------------------------------------

  test('InjectAndroidMetaData.describe outputs [inject-android-meta]', () {
    const op = InjectAndroidMetaData(
        name: 'com.google.firebase.messaging.default_icon',
        value: '@mipmap/ic_launcher');
    expect(
      op.describe(),
      '[inject-android-meta] com.google.firebase.messaging.default_icon = @mipmap/ic_launcher',
    );
  });

  // ---------------------------------------------------------------------------
  // InjectInfoPlistKey
  // ---------------------------------------------------------------------------

  test('InjectInfoPlistKey.describe outputs [inject-plist-key:<platform>]', () {
    const op = InjectInfoPlistKey(
        key: 'NSCameraUsageDescription', value: 'Camera needed');
    expect(op.describe(),
        '[inject-plist-key:ios] NSCameraUsageDescription = Camera needed');
  });

  test('InjectInfoPlistKey.describe carries an explicit macos platform tag',
      () {
    const op = InjectInfoPlistKey(
      key: 'NSCameraUsageDescription',
      value: 'Camera needed',
      platform: 'macos',
    );
    expect(op.describe(),
        '[inject-plist-key:macos] NSCameraUsageDescription = Camera needed');
  });

  // ---------------------------------------------------------------------------
  // InjectEntitlement
  // ---------------------------------------------------------------------------

  test('InjectEntitlement.describe outputs [inject-entitlement] with platform',
      () {
    const op = InjectEntitlement(
      platform: 'ios',
      key: 'com.apple.security.network.client',
      value: true,
    );
    expect(op.describe(),
        '[inject-entitlement] ios: com.apple.security.network.client = true');
  });

  // ---------------------------------------------------------------------------
  // InjectPodfileLine
  // ---------------------------------------------------------------------------

  test('InjectPodfileLine.describe outputs [inject-podfile]', () {
    const op =
        InjectPodfileLine(platform: 'ios', line: "pod 'Firebase/Messaging'");
    expect(op.describe(), "[inject-podfile] ios: pod 'Firebase/Messaging'");
  });

  // ---------------------------------------------------------------------------
  // InjectGradlePlugin
  // ---------------------------------------------------------------------------

  test(
      'InjectGradlePlugin.describe outputs [inject-gradle-plugin] with version when present',
      () {
    const op = InjectGradlePlugin(
        pluginId: 'com.google.gms.google-services', version: '4.4.2');
    expect(op.describe(),
        '[inject-gradle-plugin] com.google.gms.google-services:4.4.2');
  });

  test('InjectGradlePlugin.describe omits version when null', () {
    const op = InjectGradlePlugin(pluginId: 'com.google.gms.google-services');
    expect(
        op.describe(), '[inject-gradle-plugin] com.google.gms.google-services');
  });

  // ---------------------------------------------------------------------------
  // InjectGradleDependency
  // ---------------------------------------------------------------------------

  test('InjectGradleDependency.describe outputs [inject-gradle-dep]', () {
    const op = InjectGradleDependency(
      scope: 'implementation',
      notation: 'com.google.firebase:firebase-analytics:21.0.0',
    );
    expect(
      op.describe(),
      '[inject-gradle-dep] implementation: com.google.firebase:firebase-analytics:21.0.0',
    );
  });

  // ---------------------------------------------------------------------------
  // InjectEnvVar
  // ---------------------------------------------------------------------------

  test('InjectEnvVar.describe outputs [inject-env]', () {
    const op = InjectEnvVar(key: 'API_KEY', value: 'secret123');
    expect(op.describe(), '[inject-env] API_KEY=secret123');
  });

  // ---------------------------------------------------------------------------
  // InjectIntoWebHead
  // ---------------------------------------------------------------------------

  test(
      'InjectIntoWebHead.describe outputs [inject-web-head] with content preview',
      () {
    const op = InjectIntoWebHead(content: '<script src="app.js"></script>');
    expect(op.describe(), '[inject-web-head] <script src="app.js"></script>');
  });

  // ---------------------------------------------------------------------------
  // AddWebMetaTag
  // ---------------------------------------------------------------------------

  test('AddWebMetaTag.describe outputs [add-web-meta] with attributes', () {
    const op = AddWebMetaTag(attributes: <String, String>{
      'name': 'viewport',
      'content': 'width=device-width'
    });
    expect(op.describe(), contains('[add-web-meta]'));
  });

  // ---------------------------------------------------------------------------
  // InjectMainDartImport
  // ---------------------------------------------------------------------------

  test('InjectMainDartImport.describe outputs [inject-main-import]', () {
    const op = InjectMainDartImport(
        importStatement: "import 'package:analytics/analytics.dart';");
    expect(
      op.describe(),
      "[inject-main-import] import 'package:analytics/analytics.dart';",
    );
  });

  // ---------------------------------------------------------------------------
  // InjectIntoMainDart
  // ---------------------------------------------------------------------------

  test('InjectIntoMainDart.describe outputs [inject-main] with placement label',
      () {
    const op = InjectIntoMainDart(
        placement: MainDartPlacement.beforeInit, code: 'setup();');
    expect(op.describe(), '[inject-main:before-init] setup();');
  });

  test('InjectIntoMainDart.describe reflects afterInit placement', () {
    const op = InjectIntoMainDart(
        placement: MainDartPlacement.afterInit, code: 'bootstrap();');
    expect(op.describe(), '[inject-main:after-init] bootstrap();');
  });

  test('InjectIntoMainDart.describe reflects wrapRunApp placement', () {
    const op = InjectIntoMainDart(
        placement: MainDartPlacement.wrapRunApp,
        code: 'ProviderScope(child: #app#)');
    expect(op.describe(),
        '[inject-main:wrap-run-app] ProviderScope(child: #app#)');
  });

  // ---------------------------------------------------------------------------
  // InjectRouteRegistration
  // ---------------------------------------------------------------------------

  test('InjectRouteRegistration.describe outputs [inject-route]', () {
    const op = InjectRouteRegistration(functionName: 'analyticsRoutes');
    expect(op.describe(), '[inject-route] analyticsRoutes()');
  });

  // ---------------------------------------------------------------------------
  // RunShell
  // ---------------------------------------------------------------------------

  test('RunShell.describe outputs [run-shell] with full command line', () {
    const op = RunShell(command: 'dart', args: <String>['format', '.']);
    expect(op.describe(), '[run-shell] dart format .');
  });

  test('RunShell.describe includes working dir when supplied', () {
    const op = RunShell(
        command: 'flutter',
        args: <String>['pub', 'get'],
        workingDir: 'packages/my_plugin');
    expect(
        op.describe(), '[run-shell] flutter pub get (in packages/my_plugin)');
  });

  // ---------------------------------------------------------------------------
  // Exhaustive switch dispatch (Dart 3 sealed completeness check)
  //
  // If a new subclass is added to InstallOperation without updating this
  // switch, `dart analyze` will report a non_exhaustive_pattern_match error,
  // which is the intended safety net.
  // ---------------------------------------------------------------------------

  test('exhaustive switch dispatch covers all InstallOperation subclasses', () {
    final List<InstallOperation> ops = <InstallOperation>[
      const AddDependency(name: 'a', version: '^1.0.0'),
      const AddPathDependency(name: 'b', path: '../b'),
      const RemoveDependency(name: 'c'),
      const AddPubspecAsset(assetPath: 'assets/x.json'),
      const PublishFile(
          sourceStubName: 'x.stub',
          targetPath: 'lib/x.dart',
          replacements: <String, String>{}),
      const WriteFile(targetPath: 'lib/g.dart', content: ''),
      const DeleteFile(targetPath: 'lib/old.dart'),
      const CopyFile(sourcePath: 'src.dart', targetPath: 'dst.dart'),
      const MergeJson(
          targetPath: 'assets/en.json', sourceData: <String, dynamic>{}),
      const InjectImport(
          targetFile: 'lib/main.dart', importStatement: "import 'x.dart';"),
      InjectBeforePattern(
          targetFile: 'lib/main.dart',
          pattern: RegExp(r'init'),
          code: '// before'),
      InjectAfterPattern(
          targetFile: 'lib/main.dart',
          pattern: RegExp(r'init'),
          code: '// after'),
      const InjectAndroidPermission(permission: 'android.permission.CAMERA'),
      const InjectAndroidMetaData(name: 'com.example.key', value: 'v'),
      const InjectInfoPlistKey(key: 'NSPhotoUsageDescription', value: 'Photos'),
      const InjectEntitlement(
          platform: 'ios', key: 'com.apple.developer.maps', value: true),
      const InjectPodfileLine(platform: 'ios', line: "pod 'Foo'"),
      const InjectGradlePlugin(pluginId: 'com.example'),
      const InjectGradleDependency(
          scope: 'implementation', notation: 'com.example:lib:1.0'),
      const InjectEnvVar(key: 'FOO', value: 'bar'),
      const InjectIntoWebHead(content: '<link rel="stylesheet" href="x.css">'),
      const AddWebMetaTag(attributes: <String, String>{
        'name': 'theme-color',
        'content': '#fff'
      }),
      const InjectMainDartImport(importStatement: "import 'pkg.dart';"),
      const InjectIntoMainDart(
          placement: MainDartPlacement.afterInit, code: 'init();'),
      const InjectRouteRegistration(functionName: 'myRoutes'),
      const RunShell(command: 'dart', args: <String>['analyze']),
    ];

    final List<String> labels = <String>[];

    for (final InstallOperation op in ops) {
      // Dart 3 exhaustive switch: analyzer errors if a subclass is missing.
      final String label = switch (op) {
        AddDependency() => 'add-dependency',
        AddPathDependency() => 'add-path-dependency',
        RemoveDependency() => 'remove-dependency',
        AddPubspecAsset() => 'add-pubspec-asset',
        PublishFile() => 'publish-file',
        WriteFile() => 'write-file',
        DeleteFile() => 'delete-file',
        CopyFile() => 'copy-file',
        MergeJson() => 'merge-json',
        InjectImport() => 'inject-import',
        InjectBeforePattern() => 'inject-before-pattern',
        InjectAfterPattern() => 'inject-after-pattern',
        InjectAndroidPermission() => 'inject-android-permission',
        InjectAndroidMetaData() => 'inject-android-meta-data',
        InjectInfoPlistKey() => 'inject-info-plist-key',
        InjectEntitlement() => 'inject-entitlement',
        InjectPodfileLine() => 'inject-podfile-line',
        InjectGradlePlugin() => 'inject-gradle-plugin',
        InjectGradleDependency() => 'inject-gradle-dependency',
        InjectEnvVar() => 'inject-env-var',
        InjectIntoWebHead() => 'inject-into-web-head',
        AddWebMetaTag() => 'add-web-meta-tag',
        InjectMainDartImport() => 'inject-main-dart-import',
        InjectIntoMainDart() => 'inject-into-main-dart',
        InjectRouteRegistration() => 'inject-route-registration',
        RunShell() => 'run-shell',
      };
      labels.add(label);
    }

    // 26 subclasses must all be dispatched.
    expect(labels, hasLength(26));
  });
}
