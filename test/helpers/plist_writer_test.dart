import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// Minimal Apple XML plist fixture with one pre-existing string key.
const String _minimalPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>MyApp</string>
</dict>
</plist>
''';

void main() {
  group('PlistWriter', () {
    late Directory tempDir;
    late String plistPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plist_writer_');
      plistPath = p.join(tempDir.path, 'Info.plist');
      File(plistPath).writeAsStringSync(_minimalPlist);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // setStringKey
    // -------------------------------------------------------------------------

    test('setStringKey inserts a new <key>/<string> pair', () {
      PlistWriter.setStringKey(
          plistPath, 'NSCameraUsageDescription', 'Camera access');

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<key>NSCameraUsageDescription</key>'));
      expect(content, contains('<string>Camera access</string>'));
    });

    test('setStringKey is idempotent when value is unchanged', () {
      PlistWriter.setStringKey(plistPath, 'CFBundleName', 'MyApp');
      PlistWriter.setStringKey(plistPath, 'CFBundleName', 'MyApp');

      final content = File(plistPath).readAsStringSync();
      final keyCount = '<key>CFBundleName</key>'.allMatches(content).length;
      expect(keyCount, 1);
      expect(content, contains('<string>MyApp</string>'));
    });

    test('setStringKey replaces value when key exists with different value',
        () {
      PlistWriter.setStringKey(plistPath, 'CFBundleName', 'UpdatedApp');

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<string>UpdatedApp</string>'));
      expect(content, isNot(contains('<string>MyApp</string>')));
      final keyCount = '<key>CFBundleName</key>'.allMatches(content).length;
      expect(keyCount, 1);
    });

    // -------------------------------------------------------------------------
    // setBoolKey
    // -------------------------------------------------------------------------

    test('setBoolKey writes <true/> for true', () {
      PlistWriter.setBoolKey(plistPath, 'UIFileSharingEnabled', true);

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<key>UIFileSharingEnabled</key>'));
      expect(content, contains('<true/>'));
    });

    test('setBoolKey writes <false/> for false', () {
      PlistWriter.setBoolKey(plistPath, 'UIFileSharingEnabled', false);

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<key>UIFileSharingEnabled</key>'));
      expect(content, contains('<false/>'));
    });

    test('setBoolKey replaces existing bool value', () {
      PlistWriter.setBoolKey(plistPath, 'UIFileSharingEnabled', true);
      PlistWriter.setBoolKey(plistPath, 'UIFileSharingEnabled', false);

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<false/>'));
      expect(content, isNot(contains('<true/>')));
      final keyCount =
          '<key>UIFileSharingEnabled</key>'.allMatches(content).length;
      expect(keyCount, 1);
    });

    // -------------------------------------------------------------------------
    // setArrayKey
    // -------------------------------------------------------------------------

    test('setArrayKey inserts a new <array> when key is absent', () {
      PlistWriter.setArrayKey(plistPath, 'UISupportedInterfaceOrientations', [
        'UIInterfaceOrientationPortrait',
        'UIInterfaceOrientationLandscapeLeft',
      ]);

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<key>UISupportedInterfaceOrientations</key>'));
      expect(content, contains('<array>'));
      expect(
          content, contains('<string>UIInterfaceOrientationPortrait</string>'));
      expect(content,
          contains('<string>UIInterfaceOrientationLandscapeLeft</string>'));
    });

    test('setArrayKey replaces an existing array', () {
      PlistWriter.setArrayKey(plistPath, 'UISupportedInterfaceOrientations', [
        'UIInterfaceOrientationPortrait',
      ]);
      PlistWriter.setArrayKey(plistPath, 'UISupportedInterfaceOrientations', [
        'UIInterfaceOrientationLandscapeLeft',
      ]);

      final content = File(plistPath).readAsStringSync();
      expect(content,
          isNot(contains('<string>UIInterfaceOrientationPortrait</string>')));
      expect(content,
          contains('<string>UIInterfaceOrientationLandscapeLeft</string>'));
      final keyCount = '<key>UISupportedInterfaceOrientations</key>'
          .allMatches(content)
          .length;
      expect(keyCount, 1);
    });

    // -------------------------------------------------------------------------
    // appendToArrayKey
    // -------------------------------------------------------------------------

    test('appendToArrayKey appends to an existing array', () {
      PlistWriter.setArrayKey(plistPath, 'UIBackgroundModes', ['fetch']);
      PlistWriter.appendToArrayKey(
          plistPath, 'UIBackgroundModes', 'remote-notification');

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<string>fetch</string>'));
      expect(content, contains('<string>remote-notification</string>'));
    });

    test('appendToArrayKey is idempotent on duplicate values', () {
      PlistWriter.setArrayKey(plistPath, 'UIBackgroundModes', ['fetch']);
      PlistWriter.appendToArrayKey(plistPath, 'UIBackgroundModes', 'fetch');
      PlistWriter.appendToArrayKey(plistPath, 'UIBackgroundModes', 'fetch');

      final content = File(plistPath).readAsStringSync();
      final count = '<string>fetch</string>'.allMatches(content).length;
      expect(count, 1);
    });

    test('appendToArrayKey creates an array when key is missing', () {
      PlistWriter.appendToArrayKey(plistPath, 'UIBackgroundModes', 'fetch');

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<key>UIBackgroundModes</key>'));
      expect(content, contains('<array>'));
      expect(content, contains('<string>fetch</string>'));
    });

    // -------------------------------------------------------------------------
    // removeKey
    // -------------------------------------------------------------------------

    test('removeKey removes the key element and its sibling value', () {
      PlistWriter.removeKey(plistPath, 'CFBundleName');

      final content = File(plistPath).readAsStringSync();
      expect(content, isNot(contains('<key>CFBundleName</key>')));
      expect(content, isNot(contains('<string>MyApp</string>')));
    });

    test('removeKey is a no-op when the key is missing', () {
      PlistWriter.removeKey(plistPath, 'NonExistentKey');

      final content = File(plistPath).readAsStringSync();
      // Original content must still be intact.
      expect(content, contains('<key>CFBundleName</key>'));
    });

    // -------------------------------------------------------------------------
    // Output quality
    // -------------------------------------------------------------------------

    test('preserves XML preamble and DOCTYPE after write', () {
      PlistWriter.setStringKey(plistPath, 'SomeKey', 'SomeValue');

      final content = File(plistPath).readAsStringSync();
      expect(content, contains('<?xml version="1.0"'));
      expect(content, contains('<!DOCTYPE plist'));
    });

    test('output round-trips through XmlDocument.parse without error', () {
      PlistWriter.setStringKey(plistPath, 'NSCameraUsageDescription', 'Camera');
      PlistWriter.setBoolKey(plistPath, 'UIFileSharingEnabled', true);
      PlistWriter.setArrayKey(plistPath, 'UIBackgroundModes', ['fetch']);

      final content = File(plistPath).readAsStringSync();
      expect(() => XmlDocument.parse(content), returnsNormally);
    });
  });
}
