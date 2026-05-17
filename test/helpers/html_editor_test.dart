import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('HtmlEditor', () {
    late Directory tempDir;
    late String htmlPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_html_');
      htmlPath = p.join(tempDir.path, 'index.html');
      File(htmlPath).writeAsStringSync(
        '<!DOCTYPE html>\n<html>\n<head>\n<title>X</title>\n</head>\n<body></body>\n</html>\n',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('read returns the file contents', () {
      expect(HtmlEditor.read(htmlPath), contains('<title>X</title>'));
    });

    test('read throws when the file is missing', () {
      expect(
        () => HtmlEditor.read(p.join(tempDir.path, 'absent.html')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('hasContent matches case-insensitively', () {
      expect(HtmlEditor.hasContent(htmlPath, 'TITLE'), isTrue);
      expect(HtmlEditor.hasContent(htmlPath, 'not-present'), isFalse);
    });

    test('hasContent returns false when file missing', () {
      expect(HtmlEditor.hasContent('/no/such/file.html', 'anything'), isFalse);
    });

    test('injectBeforeClose inserts content right before the anchor', () {
      HtmlEditor.injectBeforeClose(
        htmlPath,
        '</head>',
        '<script src="x.js"></script>',
      );

      final content = File(htmlPath).readAsStringSync();
      final scriptIdx = content.indexOf('<script src="x.js"></script>');
      final closeHead = content.indexOf('</head>');
      expect(scriptIdx, greaterThan(0));
      expect(scriptIdx, lessThan(closeHead));
    });

    test('injectBeforeClose throws when anchor missing', () {
      expect(
        () => HtmlEditor.injectBeforeClose(htmlPath, '</footer>', '<p>x</p>'),
        throwsA(isA<StateError>()),
      );
    });

    test('addMetaTag injects the tag and is idempotent', () {
      HtmlEditor.addMetaTag(htmlPath, <String, String>{
        'name': 'description',
        'content': 'My Flutter App',
      });

      var content = File(htmlPath).readAsStringSync();
      expect(content, contains('name="description"'));
      expect(content, contains('content="My Flutter App"'));

      HtmlEditor.addMetaTag(htmlPath, <String, String>{
        'name': 'description',
        'content': 'My Flutter App',
      });

      content = File(htmlPath).readAsStringSync();
      final occurrences = 'name="description"'.allMatches(content).length;
      expect(occurrences, 1);
    });

    test('addMetaTag throws when </head> missing', () {
      final brokenPath = p.join(tempDir.path, 'broken.html');
      File(brokenPath).writeAsStringSync('<html><body></body></html>');

      expect(
        () => HtmlEditor.addMetaTag(
          brokenPath,
          <String, String>{'name': 'x', 'content': 'y'},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
