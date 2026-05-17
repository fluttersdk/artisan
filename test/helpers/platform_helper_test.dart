import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/helpers/platform_helper.dart';

/// Tests for [PlatformHelper] — Flutter platform detection.
///
/// All tests use a temporary directory that is cleaned up after each test.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_test_platform');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // detectPlatforms()
  // ---------------------------------------------------------------------------
  group('PlatformHelper.detectPlatforms()', () {
    test('returns only platforms whose directory exists', () {
      Directory('${tempDir.path}/android').createSync();
      Directory('${tempDir.path}/ios').createSync();

      final platforms = PlatformHelper.detectPlatforms(tempDir.path);

      expect(platforms, containsAll(['android', 'ios']));
      expect(platforms, isNot(contains('web')));
      expect(platforms, isNot(contains('macos')));
      expect(platforms, isNot(contains('linux')));
      expect(platforms, isNot(contains('windows')));
    });

    test('returns all 6 platforms when all directories exist', () {
      for (final platform in [
        'android',
        'ios',
        'web',
        'macos',
        'linux',
        'windows',
      ]) {
        Directory('${tempDir.path}/$platform').createSync();
      }

      final platforms = PlatformHelper.detectPlatforms(tempDir.path);

      expect(
        platforms,
        containsAll(['android', 'ios', 'web', 'macos', 'linux', 'windows']),
      );
      expect(platforms.length, equals(6));
    });

    test('returns empty list when no platform directories exist', () {
      final platforms = PlatformHelper.detectPlatforms(tempDir.path);

      expect(platforms, isEmpty);
    });

    test('returns platforms in a consistent order', () {
      Directory('${tempDir.path}/ios').createSync();
      Directory('${tempDir.path}/android').createSync();

      final platforms = PlatformHelper.detectPlatforms(tempDir.path);

      // android should appear before ios in the canonical list order
      final androidIndex = platforms.indexOf('android');
      final iosIndex = platforms.indexOf('ios');
      expect(androidIndex, lessThan(iosIndex));
    });
  });

  // ---------------------------------------------------------------------------
  // hasPlatform()
  // ---------------------------------------------------------------------------
  group('PlatformHelper.hasPlatform()', () {
    test('returns true when the platform directory exists', () {
      Directory('${tempDir.path}/web').createSync();

      expect(PlatformHelper.hasPlatform(tempDir.path, 'web'), isTrue);
    });

    test('returns false when the platform directory does not exist', () {
      expect(PlatformHelper.hasPlatform(tempDir.path, 'linux'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Path helpers
  // ---------------------------------------------------------------------------
  group('PlatformHelper — path helpers', () {
    test('androidManifestPath returns correct path', () {
      expect(
        PlatformHelper.androidManifestPath('/my/project'),
        equals('/my/project/android/app/src/main/AndroidManifest.xml'),
      );
    });

    test('androidBuildGradlePath returns correct path', () {
      expect(
        PlatformHelper.androidBuildGradlePath('/my/project'),
        equals('/my/project/android/app/build.gradle'),
      );
    });

    test('infoPlistPath returns correct path', () {
      expect(
        PlatformHelper.infoPlistPath('/my/project'),
        equals('/my/project/ios/Runner/Info.plist'),
      );
    });

    test('webIndexPath returns correct path', () {
      expect(
        PlatformHelper.webIndexPath('/my/project'),
        equals('/my/project/web/index.html'),
      );
    });

    test('webManifestPath returns correct path', () {
      expect(
        PlatformHelper.webManifestPath('/my/project'),
        equals('/my/project/web/manifest.json'),
      );
    });
  });
}
