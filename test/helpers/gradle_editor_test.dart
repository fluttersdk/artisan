import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// KTS fixture (build.gradle.kts)
// ---------------------------------------------------------------------------

const String _ktsFixture = r'''
plugins {
    id("com.android.application")
    id("kotlin-android")
}

android {
    namespace = "com.example.app"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.app"
        minSdk = 21
        targetSdk = 34
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.10.0")
}
''';

// ---------------------------------------------------------------------------
// Groovy fixture (build.gradle)
// ---------------------------------------------------------------------------

const String _groovyFixture = r'''
plugins {
    id 'com.android.application'
    id 'kotlin-android'
}

android {
    compileSdkVersion 34
    defaultConfig {
        applicationId "com.example.app"
        minSdkVersion 21
        targetSdkVersion 34
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.10.0'
}
''';

void main() {
  // -------------------------------------------------------------------------
  // KTS group
  // -------------------------------------------------------------------------

  group('GradleEditor — KTS syntax (build.gradle.kts)', () {
    late Directory tempDir;
    late String ktsPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_gradle_kts_');
      ktsPath = p.join(tempDir.path, 'build.gradle.kts');
      File(ktsPath).writeAsStringSync(_ktsFixture);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // 1. addPlugin KTS
    test('addPlugin inserts id("foo") version "1.0" inside plugins{}', () {
      GradleEditor.addPlugin(ktsPath, 'com.google.gms.google-services',
          version: '4.4.0');

      final content = File(ktsPath).readAsStringSync();
      expect(
        content,
        contains('id("com.google.gms.google-services") version "4.4.0"'),
      );
    });

    // 3. addPlugin idempotent (tested from KTS side)
    test('addPlugin is idempotent — no double-insert', () {
      GradleEditor.addPlugin(ktsPath, 'com.google.gms.google-services',
          version: '4.4.0');
      GradleEditor.addPlugin(ktsPath, 'com.google.gms.google-services',
          version: '4.4.0');

      final content = File(ktsPath).readAsStringSync();
      final occurrences =
          'com.google.gms.google-services'.allMatches(content).length;
      expect(occurrences, 1);
    });

    // 4. addDependency KTS
    test('addDependency inserts implementation("foo:bar:1.0")', () {
      GradleEditor.addDependency(
          ktsPath, 'implementation', 'com.google.firebase:firebase-bom:32.0.0');

      final content = File(ktsPath).readAsStringSync();
      expect(
        content,
        contains('implementation("com.google.firebase:firebase-bom:32.0.0")'),
      );
    });

    // 6. addDependency idempotent (KTS side)
    test('addDependency is idempotent — no double-insert', () {
      GradleEditor.addDependency(
          ktsPath, 'implementation', 'com.google.firebase:firebase-bom:32.0.0');
      GradleEditor.addDependency(
          ktsPath, 'implementation', 'com.google.firebase:firebase-bom:32.0.0');

      final content = File(ktsPath).readAsStringSync();
      final occurrences =
          'com.google.firebase:firebase-bom:32.0.0'.allMatches(content).length;
      expect(occurrences, 1);
    });

    // 7. setMinSdkVersion KTS
    test('setMinSdkVersion updates existing minSdk = 21 to 24', () {
      GradleEditor.setMinSdkVersion(ktsPath, 24);

      final content = File(ktsPath).readAsStringSync();
      expect(content, contains('minSdk = 24'));
      expect(content, isNot(contains('minSdk = 21')));
    });

    // addPlugin without version — no version clause expected
    test('addPlugin without version omits version clause', () {
      GradleEditor.addPlugin(ktsPath, 'org.jetbrains.kotlin.android');

      final content = File(ktsPath).readAsStringSync();
      expect(content, contains('id("org.jetbrains.kotlin.android")'));
      // Must NOT append an empty version string.
      expect(content, isNot(contains('version ""')));
    });
  });

  // -------------------------------------------------------------------------
  // Groovy group
  // -------------------------------------------------------------------------

  group('GradleEditor — Groovy syntax (build.gradle)', () {
    late Directory tempDir;
    late String groovyPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_gradle_groovy_');
      groovyPath = p.join(tempDir.path, 'build.gradle');
      File(groovyPath).writeAsStringSync(_groovyFixture);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // 2. addPlugin Groovy
    test("addPlugin inserts id 'foo' version '1.0' inside plugins{}", () {
      GradleEditor.addPlugin(groovyPath, 'com.google.gms.google-services',
          version: '4.4.0');

      final content = File(groovyPath).readAsStringSync();
      expect(
        content,
        contains("id 'com.google.gms.google-services' version '4.4.0'"),
      );
    });

    // 5. addDependency Groovy
    test("addDependency inserts implementation 'foo:bar:1.0'", () {
      GradleEditor.addDependency(groovyPath, 'implementation',
          'com.google.firebase:firebase-bom:32.0.0');

      final content = File(groovyPath).readAsStringSync();
      expect(
        content,
        contains("implementation 'com.google.firebase:firebase-bom:32.0.0'"),
      );
    });

    // 8. setMinSdkVersion Groovy
    test('setMinSdkVersion updates existing minSdkVersion 21 to 24', () {
      GradleEditor.setMinSdkVersion(groovyPath, 24);

      final content = File(groovyPath).readAsStringSync();
      expect(content, contains('minSdkVersion 24'));
      expect(content, isNot(contains('minSdkVersion 21')));
    });

    // Groovy addPlugin idempotent
    test('addPlugin is idempotent — no double-insert (Groovy)', () {
      GradleEditor.addPlugin(groovyPath, 'com.google.gms.google-services',
          version: '4.4.0');
      GradleEditor.addPlugin(groovyPath, 'com.google.gms.google-services',
          version: '4.4.0');

      final content = File(groovyPath).readAsStringSync();
      final occurrences =
          'com.google.gms.google-services'.allMatches(content).length;
      expect(occurrences, 1);
    });

    // Groovy addDependency idempotent
    test('addDependency is idempotent — no double-insert (Groovy)', () {
      GradleEditor.addDependency(groovyPath, 'implementation',
          'com.google.firebase:firebase-bom:32.0.0');
      GradleEditor.addDependency(groovyPath, 'implementation',
          'com.google.firebase:firebase-bom:32.0.0');

      final content = File(groovyPath).readAsStringSync();
      final occurrences =
          'com.google.firebase:firebase-bom:32.0.0'.allMatches(content).length;
      expect(occurrences, 1);
    });
  });

  // -------------------------------------------------------------------------
  // addClasspath group (delegates to addDependency)
  // -------------------------------------------------------------------------

  group('GradleEditor.addClasspath', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_gradle_cp_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // 9. addClasspath delegates with scope 'classpath'
    test('addClasspath delegates to addDependency with classpath scope', () {
      // Root build.gradle.kts fixture: must have a dependencies{} block.
      const rootKts = '''
buildscript {
    dependencies {
    }
}
''';
      final rootPath = p.join(tempDir.path, 'build.gradle.kts');
      File(rootPath).writeAsStringSync(rootKts);

      GradleEditor.addClasspath(
          rootPath, 'com.google.gms:google-services:4.4.0');

      final content = File(rootPath).readAsStringSync();
      expect(
        content,
        contains('classpath("com.google.gms:google-services:4.4.0")'),
      );
    });

    test('addClasspath is idempotent', () {
      const rootKts = '''
buildscript {
    dependencies {
    }
}
''';
      final rootPath = p.join(tempDir.path, 'build.gradle.kts');
      File(rootPath).writeAsStringSync(rootKts);

      GradleEditor.addClasspath(
          rootPath, 'com.google.gms:google-services:4.4.0');
      GradleEditor.addClasspath(
          rootPath, 'com.google.gms:google-services:4.4.0');

      final content = File(rootPath).readAsStringSync();
      final occurrences =
          'com.google.gms:google-services:4.4.0'.allMatches(content).length;
      expect(occurrences, 1);
    });
  });

  // -------------------------------------------------------------------------
  // Edge-case / error path group
  // -------------------------------------------------------------------------

  group('GradleEditor — error paths and edge cases', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_gradle_edge_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('_read throws FileSystemException when file does not exist', () {
      expect(
        () => GradleEditor.addPlugin(
          p.join(tempDir.path, 'nonexistent.gradle.kts'),
          'some.plugin',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('setMinSdkVersion inserts minSdk when directive is absent (KTS)', () {
      // A KTS file WITHOUT an existing minSdk line.
      const noMinSdk = '''
android {
    defaultConfig {
        applicationId = "com.example.app"
    }
}
''';
      final path = p.join(tempDir.path, 'build.gradle.kts');
      File(path).writeAsStringSync(noMinSdk);

      GradleEditor.setMinSdkVersion(path, 24);

      final content = File(path).readAsStringSync();
      expect(content, contains('minSdk = 24'));
    });

    test(
        'setMinSdkVersion inserts minSdkVersion when directive is absent (Groovy)',
        () {
      const noMinSdk = '''
android {
    defaultConfig {
        applicationId "com.example.app"
    }
}
''';
      final path = p.join(tempDir.path, 'build.gradle');
      File(path).writeAsStringSync(noMinSdk);

      GradleEditor.setMinSdkVersion(path, 24);

      final content = File(path).readAsStringSync();
      expect(content, contains('minSdkVersion 24'));
    });

    test('addPlugin throws StateError when plugins{} block is absent', () {
      final path = p.join(tempDir.path, 'broken.gradle.kts');
      File(path).writeAsStringSync('// no plugins block\n');

      expect(
        () => GradleEditor.addPlugin(path, 'some.plugin'),
        throwsA(isA<StateError>()),
      );
    });

    test('addDependency throws StateError when dependencies{} block is absent',
        () {
      final path = p.join(tempDir.path, 'broken.gradle.kts');
      File(path).writeAsStringSync('// no dependencies block\n');

      expect(
        () => GradleEditor.addDependency(path, 'implementation', 'foo:bar:1.0'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
