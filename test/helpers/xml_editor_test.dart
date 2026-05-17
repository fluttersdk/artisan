import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _manifestXml = '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">
    <application android:name=".MainApp" android:label="MyApp">
        <activity android:name=".MainActivity"/>
    </application>
</manifest>
''';

const String _plistXml = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MyApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.app</string>
</dict>
</plist>
''';

void main() {
  group('XmlEditor', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_xml_editor_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('read returns content / throws when missing', () {
      final filePath = p.join(tempDir.path, 'manifest.xml');
      File(filePath).writeAsStringSync(_manifestXml);

      expect(XmlEditor.read(filePath), contains('manifest'));
      expect(
        () => XmlEditor.read(p.join(tempDir.path, 'missing.xml')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('hasElement returns true / false / false-when-missing', () {
      final filePath = p.join(tempDir.path, 'manifest.xml');
      File(filePath).writeAsStringSync(_manifestXml);

      expect(XmlEditor.hasElement(filePath, '<application'), isTrue);
      expect(XmlEditor.hasElement(filePath, '<receiver'), isFalse);
      expect(
        XmlEditor.hasElement(p.join(tempDir.path, 'missing.xml'), '<x'),
        isFalse,
      );
    });

    test('addElement inserts content + is idempotent', () {
      final filePath = p.join(tempDir.path, 'manifest.xml');
      File(filePath).writeAsStringSync(_manifestXml);

      XmlEditor.addElement(filePath, '</manifest>', '<service name="A"/>');
      XmlEditor.addElement(filePath, '</manifest>', '<service name="A"/>');

      final content = File(filePath).readAsStringSync();
      final occurrences = '<service name="A"/>'.allMatches(content).length;
      expect(occurrences, 1);
    });

    test('addElement throws when anchor missing', () {
      final filePath = p.join(tempDir.path, 'manifest.xml');
      File(filePath).writeAsStringSync('<root></root>');

      expect(
        () => XmlEditor.addElement(filePath, '</nope>', '<x/>'),
        throwsA(isA<StateError>()),
      );
    });

    test('addAndroidPermission injects + idempotent', () {
      final filePath = p.join(tempDir.path, 'manifest.xml');
      File(filePath).writeAsStringSync(_manifestXml);

      XmlEditor.addAndroidPermission(
        filePath,
        'android.permission.POST_NOTIFICATIONS',
      );
      XmlEditor.addAndroidPermission(
        filePath,
        'android.permission.POST_NOTIFICATIONS',
      );

      final content = File(filePath).readAsStringSync();
      final occurrences =
          'android.permission.POST_NOTIFICATIONS'.allMatches(content).length;
      expect(occurrences, 1);
    });

    test('addAndroidPermission throws when </manifest> missing', () {
      final filePath = p.join(tempDir.path, 'broken.xml');
      File(filePath).writeAsStringSync('<root></root>');

      expect(
        () => XmlEditor.addAndroidPermission(filePath, 'X'),
        throwsA(isA<StateError>()),
      );
    });

    test('addAndroidMetaData injects + idempotent', () {
      final filePath = p.join(tempDir.path, 'manifest.xml');
      File(filePath).writeAsStringSync(_manifestXml);

      XmlEditor.addAndroidMetaData(
        filePath,
        name: 'io.flutter.embedding.android.NormalTheme',
        value: '@style/NormalTheme',
      );
      XmlEditor.addAndroidMetaData(
        filePath,
        name: 'io.flutter.embedding.android.NormalTheme',
        value: '@style/NormalTheme',
      );

      final content = File(filePath).readAsStringSync();
      final occurrences =
          'io.flutter.embedding.android.NormalTheme'.allMatches(content).length;
      expect(occurrences, 1);
    });

    test('addAndroidMetaData throws when <application> missing', () {
      final filePath = p.join(tempDir.path, 'broken.xml');
      File(filePath).writeAsStringSync('<manifest></manifest>');

      expect(
        () => XmlEditor.addAndroidMetaData(filePath, name: 'x', value: 'y'),
        throwsA(isA<StateError>()),
      );
    });

    test('readPlist extracts <key>/<string> pairs', () {
      final filePath = p.join(tempDir.path, 'Info.plist');
      File(filePath).writeAsStringSync(_plistXml);

      final plist = XmlEditor.readPlist(filePath);

      expect(plist['CFBundleName'], 'MyApp');
      expect(plist['CFBundleIdentifier'], 'com.example.app');
    });
  });
}
