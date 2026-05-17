import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/helpers/xml_editor.dart';

/// Tests for [XmlEditor] — XML/Plist file manipulation.
///
/// All tests use a temporary directory that is cleaned up after each test.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_test_xml_editor');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // read()
  // ---------------------------------------------------------------------------
  group('XmlEditor.read()', () {
    test('returns the file content as a string', () {
      final file = File('${tempDir.path}/test.xml');
      file.writeAsStringSync('<root><child/></root>');

      final content = XmlEditor.read(file.path);

      expect(content, equals('<root><child/></root>'));
    });

    test('throws FileSystemException when file does not exist', () {
      expect(
        () => XmlEditor.read('${tempDir.path}/nonexistent.xml'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // hasElement()
  // ---------------------------------------------------------------------------
  group('XmlEditor.hasElement()', () {
    test('returns true when pattern is present in file', () {
      final file = File('${tempDir.path}/manifest.xml');
      file.writeAsStringSync(
        '<manifest>\n  <uses-permission android:name="android.permission.INTERNET"/>\n</manifest>',
      );

      expect(XmlEditor.hasElement(file.path, 'INTERNET'), isTrue);
    });

    test('returns false when pattern is absent from file', () {
      final file = File('${tempDir.path}/manifest.xml');
      file.writeAsStringSync('<manifest></manifest>');

      expect(XmlEditor.hasElement(file.path, 'POST_NOTIFICATIONS'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // addAndroidPermission()
  // ---------------------------------------------------------------------------
  group('XmlEditor.addAndroidPermission()', () {
    test('inserts permission tag before </manifest>', () {
      final file = File('${tempDir.path}/AndroidManifest.xml');
      file.writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application/>\n'
        '</manifest>',
      );

      XmlEditor.addAndroidPermission(
        file.path,
        'android.permission.POST_NOTIFICATIONS',
      );

      final content = file.readAsStringSync();
      expect(
        content,
        contains(
          '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
        ),
      );
      expect(content, contains('</manifest>'));
    });

    test('is idempotent — does not duplicate an existing permission', () {
      final file = File('${tempDir.path}/AndroidManifest.xml');
      file.writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
        '</manifest>',
      );

      XmlEditor.addAndroidPermission(
        file.path,
        'android.permission.POST_NOTIFICATIONS',
      );

      final content = file.readAsStringSync();
      final count = 'POST_NOTIFICATIONS'.allMatches(content).length;
      expect(count, equals(1));
    });

    test('throws StateError when </manifest> closing tag is missing', () {
      final file = File('${tempDir.path}/broken.xml');
      file.writeAsStringSync('<manifest>');

      expect(
        () => XmlEditor.addAndroidPermission(
          file.path,
          'android.permission.INTERNET',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // addAndroidMetaData()
  // ---------------------------------------------------------------------------
  group('XmlEditor.addAndroidMetaData()', () {
    test('inserts meta-data element inside <application>', () {
      final file = File('${tempDir.path}/AndroidManifest.xml');
      file.writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application android:label="App">\n'
        '    <activity android:name=".MainActivity"/>\n'
        '  </application>\n'
        '</manifest>',
      );

      XmlEditor.addAndroidMetaData(
        file.path,
        name: 'com.onesignal.NotificationServiceExtension',
        value: 'com.example.app.NotificationExtender',
      );

      final content = file.readAsStringSync();
      expect(
        content,
        contains(
          'android:name="com.onesignal.NotificationServiceExtension"',
        ),
      );
      expect(
        content,
        contains(
          'android:value="com.example.app.NotificationExtender"',
        ),
      );
    });

    test('is idempotent — does not duplicate existing meta-data', () {
      final file = File('${tempDir.path}/AndroidManifest.xml');
      file.writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application>\n'
        '    <meta-data android:name="com.example.KEY" android:value="value1"/>\n'
        '  </application>\n'
        '</manifest>',
      );

      XmlEditor.addAndroidMetaData(
        file.path,
        name: 'com.example.KEY',
        value: 'value1',
      );

      final content = file.readAsStringSync();
      final count = 'com.example.KEY'.allMatches(content).length;
      expect(count, equals(1));
    });

    test('throws StateError when <application> tag is missing', () {
      final file = File('${tempDir.path}/no_app.xml');
      file.writeAsStringSync('<manifest></manifest>');

      expect(
        () => XmlEditor.addAndroidMetaData(
          file.path,
          name: 'key',
          value: 'val',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // addElement()
  // ---------------------------------------------------------------------------
  group('XmlEditor.addElement()', () {
    test('inserts element before the given closing tag pattern', () {
      final file = File('${tempDir.path}/config.xml');
      file.writeAsStringSync('<config>\n</config>');

      XmlEditor.addElement(file.path, '</config>', '<item value="foo"/>');

      final content = file.readAsStringSync();
      expect(content, contains('<item value="foo"/>'));
      expect(content, contains('</config>'));
    });

    test('does not insert when the element content already exists', () {
      final file = File('${tempDir.path}/config.xml');
      file.writeAsStringSync(
        '<config>\n  <item value="foo"/>\n</config>',
      );

      XmlEditor.addElement(file.path, '</config>', '<item value="foo"/>');

      final content = file.readAsStringSync();
      final count = '<item value="foo"/>'.allMatches(content).length;
      expect(count, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // readPlist()
  // ---------------------------------------------------------------------------
  group('XmlEditor.readPlist()', () {
    test('parses basic string key-value pairs from a plist file', () {
      final file = File('${tempDir.path}/Info.plist');
      file.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MyApp</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>''');

      final result = XmlEditor.readPlist(file.path);

      expect(result['CFBundleName'], equals('MyApp'));
      expect(result['CFBundleVersion'], equals('1.0'));
    });

    test('returns empty map for a plist with no dict entries', () {
      final file = File('${tempDir.path}/empty.plist');
      file.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
</dict>
</plist>''');

      final result = XmlEditor.readPlist(file.path);
      expect(result, isEmpty);
    });
  });
}
