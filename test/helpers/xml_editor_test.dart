import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

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

/// The shape of a real Flutter app manifest: a commented MainActivity with
/// singleTop, a host-wide autoVerify App Link filter and the Flutter
/// deep-linking meta-data, plus the nodes that sit around `<application>`.
const String _appManifestXml =
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
            android:taskAffinity="">
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

const String _androidNs = 'http://schemas.android.com/apk/res/android';

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

/// What `addAndroidActivity` must splice in for [_callbackFilter], spelled out
/// by hand so the test does not derive its expectation from the renderer.
const String _callbackBlock = '''        <activity
            android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
            android:exported="true"
            android:taskAffinity="">
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="auth.example.com" android:path="/social/callback"/>
            </intent-filter>
        </activity>
''';

/// The `<activity>` elements named [name] under `<application>` of the
/// manifest at [path], parsed with package `xml` so a comment never counts.
List<XmlElement> _activitiesNamed(String path, String name) {
  return XmlDocument.parse(File(path).readAsStringSync())
      .rootElement
      .findElements('application')
      .single
      .findElements('activity')
      .where((e) => e.getAttribute('android:name') == name)
      .toList();
}

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

    group('addAndroidActivity', () {
      late String manifest;

      setUp(() {
        manifest = p.join(tempDir.path, 'AndroidManifest.xml');
        File(manifest).writeAsStringSync(_appManifestXml);
      });

      AndroidActivityOutcome add({
        String name = _callbackName,
        List<AndroidIntentFilter> filters = const [_callbackFilter],
      }) {
        return XmlEditor.addAndroidActivity(
          manifest,
          name: name,
          exported: true,
          taskAffinity: '',
          intentFilters: filters,
        );
      }

      test('splices the activity before </application> and nothing else', () {
        expect(add(), AndroidActivityOutcome.added);

        // The diff is the inserted block and only that: MainActivity, the
        // comments and the nodes around <application> keep their bytes.
        expect(
          File(manifest).readAsStringSync(),
          _appManifestXml.replaceFirst(
            '    </application>',
            '$_callbackBlock    </application>',
          ),
        );

        final activity = _activitiesNamed(manifest, _callbackName).single;
        expect(activity.getAttribute('android:exported'), 'true');
        expect(activity.getAttribute('android:taskAffinity'), '');
        final filter = activity.findElements('intent-filter').single;
        expect(filter.getAttribute('android:autoVerify'), 'true');
        final data = filter.findElements('data').single;
        expect(data.getAttribute('android:host'), 'auth.example.com');
        expect(data.getAttribute('android:path'), '/social/callback');
      });

      test('a second run is a byte-identical no-op', () {
        add();
        final afterFirst = File(manifest).readAsStringSync();

        expect(add(), AndroidActivityOutcome.unchanged);

        expect(File(manifest).readAsStringSync(), afterFirst);
        expect(_activitiesNamed(manifest, _callbackName), hasLength(1));
      });

      test('an equal filter set written in another order is a no-op', () {
        // The same single filter, hand-written: categories reversed,
        // attributes in another order, a formatting of its own.
        final handWritten = _appManifestXml.replaceFirst(
          '    </application>',
          '''        <activity android:taskAffinity="" android:exported="true"
            android:name="$_callbackName">
            <intent-filter android:autoVerify="true">
                <category android:name="android.intent.category.BROWSABLE"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <action android:name="android.intent.action.VIEW"/>
                <data android:path="/social/callback" android:host="auth.example.com"
                    android:scheme="https"/>
            </intent-filter>
        </activity>
    </application>''',
        );
        File(manifest).writeAsStringSync(handWritten);

        expect(add(), AndroidActivityOutcome.unchanged);

        expect(File(manifest).readAsStringSync(), handWritten);
      });

      test('an existing activity with a different host is left untouched', () {
        final differentHost = _appManifestXml.replaceFirst(
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
        File(manifest).writeAsStringSync(differentHost);

        expect(add(), AndroidActivityOutcome.conflict);

        expect(File(manifest).readAsStringSync(), differentHost);
        expect(_activitiesNamed(manifest, _callbackName), hasLength(1));
      });

      test('an existing activity with no filter is a conflict, not a rewrite',
          () {
        final bare = _appManifestXml.replaceFirst(
          '    </application>',
          '        <activity android:name="$_callbackName"/>\n'
              '    </application>',
        );
        File(manifest).writeAsStringSync(bare);

        expect(add(), AndroidActivityOutcome.conflict);

        expect(File(manifest).readAsStringSync(), bare);
      });

      test('a name that only appears inside a comment does not count', () {
        final commented = _appManifestXml.replaceFirst(
          '    </application>',
          '        <!-- <activity android:name="$_callbackName"/> -->\n'
              '    </application>',
        );
        File(manifest).writeAsStringSync(commented);

        expect(add(), AndroidActivityOutcome.added);

        expect(
          File(manifest).readAsStringSync(),
          contains('<!-- <activity android:name="$_callbackName"/> -->'),
        );
        expect(_activitiesNamed(manifest, _callbackName), hasLength(1));
      });

      test('a commented </application> is not mistaken for the real anchor',
          () {
        final decoy = _appManifestXml.replaceFirst(
          '</manifest>',
          '<!-- </application> -->\n</manifest>',
        );
        File(manifest).writeAsStringSync(decoy);

        expect(add(), AndroidActivityOutcome.added);

        expect(_activitiesNamed(manifest, _callbackName), hasLength(1));
      });

      test('an activity named like another one is a different activity', () {
        add(name: '$_callbackName.Other');

        expect(add(), AndroidActivityOutcome.added);

        expect(_activitiesNamed(manifest, _callbackName), hasLength(1));
        expect(
            _activitiesNamed(manifest, '$_callbackName.Other'), hasLength(1));
      });

      test('throws StateError when the manifest has no <application> block',
          () {
        File(manifest).writeAsStringSync(
          '<manifest xmlns:android="$_androidNs"/>',
        );

        expect(add, throwsA(isA<StateError>()));
      });

      test('throws StateError for a self-closing <application/>', () {
        File(manifest).writeAsStringSync(
          '<manifest xmlns:android="$_androidNs">\n'
          '    <application android:label="x"/>\n'
          '</manifest>\n',
        );

        expect(add, throwsA(isA<StateError>()));
      });

      test('throws FileSystemException when the manifest is missing', () {
        expect(
          () => XmlEditor.addAndroidActivity(
            p.join(tempDir.path, 'missing.xml'),
            name: _callbackName,
            exported: true,
            intentFilters: const [],
          ),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('renderAndroidActivity', () {
      test('omits taskAffinity when null and renders exported false', () {
        final block = XmlEditor.renderAndroidActivity(
          name: '.Foo',
          exported: false,
          intentFilters: const [],
        );

        expect(block, '''<activity
    android:name=".Foo"
    android:exported="false"/>''');
      });

      test('renders pathPrefix, a plain filter and escaped attribute values',
          () {
        final block = XmlEditor.renderAndroidActivity(
          name: '.Foo',
          exported: true,
          intentFilters: const [
            AndroidIntentFilter(
              actions: ['android.intent.action.VIEW'],
              data: [AndroidIntentData(scheme: 'app', pathPrefix: '/a&b')],
            ),
          ],
        );

        expect(block, contains('<intent-filter>'));
        expect(
          block,
          contains(
              '<data android:scheme="app" android:pathPrefix="/a&amp;b"/>'),
        );
      });
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
