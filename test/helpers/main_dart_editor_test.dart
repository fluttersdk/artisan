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

    // 10. injectBeforeAnchor happy path: snippet appears before the anchor line.
    test('injectBeforeAnchor inserts snippet before the anchor line', () {
      const source = 'void main() async {\n'
          '  await Magic.init();\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: 'await Magic.init()',
        snippet: '  SomeSetup.call();\n',
      );

      final initIndex = result.indexOf('await Magic.init()');
      final snippetIndex = result.indexOf('SomeSetup.call()');
      expect(snippetIndex, isNonNegative);
      expect(snippetIndex, lessThan(initIndex));
    });

    // 11. injectBeforeAnchor idempotence: second call returns source unchanged.
    test('injectBeforeAnchor does not re-insert when snippet already present',
        () {
      const source = 'void main() async {\n'
          '  SomeSetup.call();\n'
          '  await Magic.init();\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: 'await Magic.init()',
        snippet: '  SomeSetup.call();\n',
      );

      expect(result, equals(source));
      expect('SomeSetup.call()'.allMatches(result).length, 1);
    });

    // 12. injectBeforeAnchor anchor-not-found: returns source unchanged.
    test('injectBeforeAnchor returns source unchanged when anchor is not found',
        () {
      const source = 'void main() async {\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: 'await Magic.init()',
        snippet: '  SomeSetup.call();\n',
      );

      expect(result, equals(source));
    });

    // 13. injectBeforeAnchor multi-line snippet: all lines appear before anchor.
    test('injectBeforeAnchor inserts a multi-line snippet before anchor', () {
      const source = 'void main() async {\n'
          '  await Magic.init();\n'
          '  runApp(MyApp());\n'
          '}\n';
      const snippet =
          '  // phase A\n  PhaseA.init();\n  // phase B\n  PhaseB.init();\n';

      final result = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: 'await Magic.init()',
        snippet: snippet,
      );

      final initIndex = result.indexOf('await Magic.init()');
      expect(result.indexOf('PhaseA.init()'), lessThan(initIndex));
      expect(result.indexOf('PhaseB.init()'), lessThan(initIndex));
    });

    // 14. injectBeforeAnchor with indent parameter: snippet is indented.
    test('injectBeforeAnchor applies indent prefix to every snippet line', () {
      const source = 'void main() async {\n'
          '  await Magic.init();\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: 'await Magic.init()',
        snippet: 'SomeSetup.call();\n',
        indent: '  ',
      );

      expect(result, contains('  SomeSetup.call();'));
      final initIndex = result.indexOf('await Magic.init()');
      final snippetIndex = result.indexOf('  SomeSetup.call();');
      expect(snippetIndex, lessThan(initIndex));
    });

    // 15. wrapRunApp with custom appCall wraps the named entry point.
    test('wrapRunApp wraps a custom entry point when appCall is specified', () {
      const fixture = '''
import 'package:flutter/material.dart';

void main() {
  runWidget(MyApp());
}
''';
      final customPath = p.join(tempDir.path, 'main_custom_entry.dart');
      File(customPath).writeAsStringSync(fixture);

      MainDartEditor.wrapRunApp(customPath, 'SentryWidget',
          appCall: 'runWidget');

      final content = File(customPath).readAsStringSync();
      expect(content, contains('runWidget(SentryWidget(MyApp()))'));
      // The standard runApp is not touched.
      expect(content, isNot(contains('runApp(')));
    });

    // 16. wrapRunApp with custom appCall is idempotent.
    test('wrapRunApp with custom appCall is idempotent when already wrapped',
        () {
      const fixture = '''
import 'package:flutter/material.dart';

void main() {
  runWidget(MyApp());
}
''';
      final customPath = p.join(tempDir.path, 'main_custom_entry_idem.dart');
      File(customPath).writeAsStringSync(fixture);

      MainDartEditor.wrapRunApp(customPath, 'SentryWidget',
          appCall: 'runWidget');
      MainDartEditor.wrapRunApp(customPath, 'SentryWidget',
          appCall: 'runWidget');

      final content = File(customPath).readAsStringSync();
      expect('SentryWidget('.allMatches(content).length, 1);
    });

    // 17. wrapRunApp with custom appCall throws StateError when entry not found.
    test('wrapRunApp with custom appCall throws when entry point is absent',
        () {
      expect(
        () => MainDartEditor.wrapRunApp(singleLinePath, 'SentryWidget',
            appCall: 'runWidget'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('runWidget('),
          ),
        ),
      );
    });

    // 18. injectAfterAnchor happy path: snippet appears after the closing `)`
    //     of the anchored call.
    test('injectAfterAnchor inserts snippet after the anchored call', () {
      const source = 'void main() async {\n'
          '  await Magic.init();\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectAfterAnchor(
        source: source,
        anchor: 'Magic.init',
        snippet: '  MagicDuskIntegration.install();\n',
      );

      final initIndex = result.indexOf('await Magic.init();');
      final snippetIndex = result.indexOf('MagicDuskIntegration.install();');
      final runAppIndex = result.indexOf('runApp(MyApp());');
      expect(initIndex, greaterThan(-1));
      expect(snippetIndex, greaterThan(initIndex));
      expect(snippetIndex, lessThan(runAppIndex));
    });

    // 19. injectAfterAnchor idempotence: re-inserting the same snippet is a no-op.
    test('injectAfterAnchor is idempotent when snippet is already present', () {
      const source = 'void main() async {\n'
          '  await Magic.init();\n'
          '  MagicDuskIntegration.install();\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectAfterAnchor(
        source: source,
        anchor: 'Magic.init',
        snippet: '  MagicDuskIntegration.install();\n',
      );

      expect(result, equals(source));
    });

    // 20. injectAfterAnchor returns source unchanged when the anchor is absent.
    test('injectAfterAnchor returns source unchanged when anchor not found',
        () {
      const source = 'void main() {\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectAfterAnchor(
        source: source,
        anchor: 'Magic.init',
        snippet: '  Something.call();\n',
      );

      expect(result, equals(source));
    });

    // 21. injectAfterAnchor handles multi-line calls with nested parens via
    //     the depth counter (configFactories list spans multiple lines).
    test('injectAfterAnchor handles multi-line anchored calls', () {
      const source = 'void main() async {\n'
          '  await Magic.init(\n'
          '    configFactories: [\n'
          '      () => appConfig,\n'
          '    ],\n'
          '  );\n'
          '  runApp(MyApp());\n'
          '}\n';

      final result = MainDartEditor.injectAfterAnchor(
        source: source,
        anchor: 'Magic.init',
        snippet: '  MagicDuskIntegration.install();\n',
      );

      // The snippet must land between the `);` that closes Magic.init and
      // the runApp line, not inside the configFactories list.
      final closeInitIndex = result.indexOf('  );\n');
      final snippetIndex = result.indexOf('MagicDuskIntegration.install();');
      final runAppIndex = result.indexOf('runApp(MyApp());');
      expect(snippetIndex, greaterThan(closeInitIndex));
      expect(snippetIndex, lessThan(runAppIndex));
    });
  });
}
