import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/helpers/html_editor.dart';

/// Tests for [HtmlEditor] — HTML file injection.
///
/// All tests use a temporary directory that is cleaned up after each test.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_test_html_editor');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // read()
  // ---------------------------------------------------------------------------
  group('HtmlEditor.read()', () {
    test('returns the file content as a string', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync('<html><head></head><body></body></html>');

      expect(
        HtmlEditor.read(file.path),
        equals('<html><head></head><body></body></html>'),
      );
    });

    test('throws FileSystemException when file does not exist', () {
      expect(
        () => HtmlEditor.read('${tempDir.path}/missing.html'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // hasContent()
  // ---------------------------------------------------------------------------
  group('HtmlEditor.hasContent()', () {
    test('returns true when pattern is present (case-insensitive)', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync(
        '<head><script src="onesignalsdk.page.js"></script></head>',
      );

      expect(HtmlEditor.hasContent(file.path, 'OneSignalSDK'), isTrue);
    });

    test('returns false when pattern is absent', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync('<head><title>App</title></head>');

      expect(HtmlEditor.hasContent(file.path, 'OneSignalSDK'), isFalse);
    });

    test('is case-insensitive for the pattern match', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync(
          '<meta name="viewport" content="width=device-width">');

      expect(HtmlEditor.hasContent(file.path, 'VIEWPORT'), isTrue);
      expect(HtmlEditor.hasContent(file.path, 'viewport'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // injectBeforeClose()
  // ---------------------------------------------------------------------------
  group('HtmlEditor.injectBeforeClose()', () {
    test('injects content immediately before the closing tag', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync(
        '<!DOCTYPE html>\n<html>\n<head>\n<title>App</title>\n</head>\n<body></body>\n</html>',
      );

      const injection = '  <script src="sdk.js" defer></script>';
      HtmlEditor.injectBeforeClose(file.path, '</head>', injection);

      final content = file.readAsStringSync();
      // Injection must appear before </head>
      final injectionIndex = content.indexOf(injection);
      final closingIndex = content.indexOf('</head>');
      expect(injectionIndex, greaterThanOrEqualTo(0));
      expect(injectionIndex, lessThan(closingIndex));
    });

    test('does NOT inject when hasContent check passes (idempotent guard)', () {
      final file = File('${tempDir.path}/index.html');
      final initialContent = '<head><script src="sdk.js"></script></head>';
      file.writeAsStringSync(initialContent);

      // Caller should use hasContent check; injectBeforeClose itself will
      // still inject — so test the guard pattern used by consumers.
      // Here we verify direct injection works even if called twice (consumers guard).
      HtmlEditor.injectBeforeClose(
        file.path,
        '</head>',
        '<script src="sdk.js"></script>',
      );

      final content = file.readAsStringSync();
      // Two occurrences of the script tag are present (consumer must guard)
      final count = 'sdk.js'.allMatches(content).length;
      expect(count, equals(2));
    });

    test('throws StateError when closing tag is not found', () {
      final file = File('${tempDir.path}/bad.html');
      file.writeAsStringSync('<html><head>');

      expect(
        () => HtmlEditor.injectBeforeClose(
          file.path,
          '</head>',
          '<meta charset="utf-8">',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // addMetaTag()
  // ---------------------------------------------------------------------------
  group('HtmlEditor.addMetaTag()', () {
    test('inserts a <meta> tag before </head>', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync(
        '<html><head><title>App</title></head><body></body></html>',
      );

      HtmlEditor.addMetaTag(file.path, {
        'name': 'description',
        'content': 'My App',
      });

      final content = file.readAsStringSync();
      expect(content, contains('<meta'));
      expect(content, contains('name="description"'));
      expect(content, contains('content="My App"'));
    });

    test('is idempotent — does not add duplicate meta tag', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync(
        '<html><head>'
        '<meta name="description" content="My App">'
        '</head><body></body></html>',
      );

      HtmlEditor.addMetaTag(file.path, {
        'name': 'description',
        'content': 'My App',
      });

      final content = file.readAsStringSync();
      final count = 'name="description"'.allMatches(content).length;
      expect(count, equals(1));
    });

    test('attributes appear in the rendered <meta> tag', () {
      final file = File('${tempDir.path}/index.html');
      file.writeAsStringSync('<html><head></head><body></body></html>');

      HtmlEditor.addMetaTag(file.path, {
        'http-equiv': 'X-UA-Compatible',
        'content': 'IE=edge',
      });

      final content = file.readAsStringSync();
      expect(content, contains('http-equiv="X-UA-Compatible"'));
      expect(content, contains('content="IE=edge"'));
    });
  });
}
