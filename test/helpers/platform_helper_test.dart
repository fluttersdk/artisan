import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PlatformHelper', () {
    late Directory projectRoot;

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync('artisan_platform_');
    });

    tearDown(() {
      if (projectRoot.existsSync()) projectRoot.deleteSync(recursive: true);
    });

    test('detectPlatforms returns empty when no platform dirs exist', () {
      expect(PlatformHelper.detectPlatforms(projectRoot.path), isEmpty);
    });

    test('detectPlatforms returns platforms in canonical order', () {
      Directory(p.join(projectRoot.path, 'web')).createSync();
      Directory(p.join(projectRoot.path, 'android')).createSync();
      Directory(p.join(projectRoot.path, 'macos')).createSync();

      expect(
        PlatformHelper.detectPlatforms(projectRoot.path),
        <String>['android', 'web', 'macos'],
      );
    });

    test('hasPlatform returns true only when the directory exists', () {
      Directory(p.join(projectRoot.path, 'ios')).createSync();

      expect(PlatformHelper.hasPlatform(projectRoot.path, 'ios'), isTrue);
      expect(PlatformHelper.hasPlatform(projectRoot.path, 'android'), isFalse);
    });

    test('canonical path helpers compose root + relative subpath', () {
      const root = '/x';

      expect(
        PlatformHelper.androidManifestPath(root),
        '/x/android/app/src/main/AndroidManifest.xml',
      );
      expect(
        PlatformHelper.androidBuildGradlePath(root),
        '/x/android/app/build.gradle',
      );
      expect(PlatformHelper.infoPlistPath(root), '/x/ios/Runner/Info.plist');
      expect(PlatformHelper.webIndexPath(root), '/x/web/index.html');
      expect(PlatformHelper.webManifestPath(root), '/x/web/manifest.json');
    });

    test('all six canonical platforms are recognised', () {
      for (final platform in <String>[
        'android',
        'ios',
        'web',
        'macos',
        'linux',
        'windows',
      ]) {
        Directory(p.join(projectRoot.path, platform)).createSync();
      }

      expect(
        PlatformHelper.detectPlatforms(projectRoot.path),
        <String>['android', 'ios', 'web', 'macos', 'linux', 'windows'],
      );
    });
  });
}
