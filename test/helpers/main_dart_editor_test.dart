import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Fixture: minimal single-line Magic.init.
const _singleLineFixture = '''
import 'package:magic/magic.dart';

void main() async {
  await Magic.init();
  runApp(MyApp());
}
''';

/// Fixture: multi-line Magic.init matching the uptizm-app shape.
const _multiLineFixture = '''
import 'package:magic/magic.dart';
import 'config/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => routingConfig,
    ],
  );
  runApp(MyApp());
}
''';

void main() {
  group('MainDartEditor', () {
    late Directory tempDir;
    late String singleLinePath;
    late String multiLinePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('main_dart_editor_');
      singleLinePath = p.join(tempDir.path, 'main_single.dart');
      multiLinePath = p.join(tempDir.path, 'main_multi.dart');
      File(singleLinePath).writeAsStringSync(_singleLineFixture);
      File(multiLinePath).writeAsStringSync(_multiLineFixture);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // 1. addImport delegates to ConfigEditor.addImportToFile.
    test('addImport adds an import statement to the file', () {
      MainDartEditor.addImport(
        singleLinePath,
        "import 'package:flutter/material.dart'",
      );

      final content = File(singleLinePath).readAsStringSync();
      expect(content, contains("import 'package:flutter/material.dart';"));
    });

    // 2. injectBeforeMagicInit single-line.
    test('injectBeforeMagicInit inserts code before single-line Magic.init',
        () {
      MainDartEditor.injectBeforeMagicInit(
        singleLinePath,
        '  WidgetsFlutterBinding.ensureInitialized();\n',
      );

      final content = File(singleLinePath).readAsStringSync();
      final initIndex = content.indexOf('await Magic.init()');
      final insertedIndex = content.indexOf('WidgetsFlutterBinding');
      expect(insertedIndex, isNonNegative);
      expect(insertedIndex, lessThan(initIndex));
    });

    // 3. injectBeforeMagicInit multi-line.
    test('injectBeforeMagicInit inserts code before multi-line Magic.init', () {
      MainDartEditor.injectBeforeMagicInit(
        multiLinePath,
        '  DuskPlugin.install();\n',
      );

      final content = File(multiLinePath).readAsStringSync();
      final initIndex = content.indexOf('await Magic.init(');
      final insertedIndex = content.indexOf('DuskPlugin.install()');
      expect(insertedIndex, isNonNegative);
      expect(insertedIndex, lessThan(initIndex));
    });

    // 4. injectBeforeMagicInit idempotent.
    test('injectBeforeMagicInit does not double-insert on repeated call', () {
      const block = '  SomeSetup.call();\n';
      MainDartEditor.injectBeforeMagicInit(singleLinePath, block);
      MainDartEditor.injectBeforeMagicInit(singleLinePath, block);

      final content = File(singleLinePath).readAsStringSync();
      expect('SomeSetup.call()'.allMatches(content).length, 1);
    });

    // 5. injectAfterMagicInit single-line.
    test('injectAfterMagicInit inserts code after single-line Magic.init', () {
      MainDartEditor.injectAfterMagicInit(
        singleLinePath,
        '  PostInitSetup.run();\n',
      );

      final content = File(singleLinePath).readAsStringSync();
      final initIndex = content.indexOf('await Magic.init()');
      final insertedIndex = content.indexOf('PostInitSetup.run()');
      expect(insertedIndex, isNonNegative);
      expect(insertedIndex, greaterThan(initIndex));
    });

    // 6. injectAfterMagicInit multi-line (closing ); is past the ] + , of configFactories).
    test('injectAfterMagicInit inserts code after multi-line Magic.init', () {
      MainDartEditor.injectAfterMagicInit(
        multiLinePath,
        '  MagicDuskIntegration.install();\n',
      );

      final content = File(multiLinePath).readAsStringSync();
      // Locate the Magic.init block's closing ); by finding the await line,
      // then scanning forward for the matching closing paren line.
      final initIndex = content.indexOf('await Magic.init(');
      // The string '  );' appears on the line that closes Magic.init's arg list.
      final magicInitClosingIndex = content.indexOf(
        '\n  );\n',
        initIndex,
      );
      final insertedIndex = content.indexOf('MagicDuskIntegration.install()');
      final runAppIndex = content.indexOf('runApp(');
      expect(insertedIndex, isNonNegative);
      expect(insertedIndex, greaterThan(magicInitClosingIndex));
      expect(insertedIndex, lessThan(runAppIndex));
    });

    // 7. injectAfterMagicInit idempotent.
    test('injectAfterMagicInit does not double-insert on repeated call', () {
      const block = '  PostInit.run();\n';
      MainDartEditor.injectAfterMagicInit(singleLinePath, block);
      MainDartEditor.injectAfterMagicInit(singleLinePath, block);

      final content = File(singleLinePath).readAsStringSync();
      expect('PostInit.run()'.allMatches(content).length, 1);
    });

    // 8. wrapRunApp wraps a single-argument runApp.
    test('wrapRunApp wraps runApp with the given wrapper name', () {
      MainDartEditor.wrapRunApp(singleLinePath, 'SentryWidget');

      final content = File(singleLinePath).readAsStringSync();
      expect(content, contains('runApp(SentryWidget(MyApp()))'));
    });

    // 9. wrapRunApp idempotent (already-wrapped call is not double-wrapped).
    test('wrapRunApp is idempotent when already wrapped', () {
      MainDartEditor.wrapRunApp(singleLinePath, 'SentryWidget');
      MainDartEditor.wrapRunApp(singleLinePath, 'SentryWidget');

      final content = File(singleLinePath).readAsStringSync();
      expect('SentryWidget('.allMatches(content).length, 1);
    });
  });
}
