import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StubLoader.replace', () {
    test('substitutes a single placeholder', () {
      final out = StubLoader.replace('Hello {{ name }}', {'name': 'World'});
      expect(out, 'Hello World');
    });

    test('substitutes multiple placeholders', () {
      final out = StubLoader.replace(
        'class {{ className }} extends {{ baseClass }} {}',
        {'className': 'Monitor', 'baseClass': 'Model'},
      );
      expect(out, 'class Monitor extends Model {}');
    });

    test('substitutes the same placeholder appearing multiple times', () {
      final out = StubLoader.replace(
        '{{ x }} and {{ x }} and {{ x }}',
        {'x': 'value'},
      );
      expect(out, 'value and value and value');
    });

    test('leaves unknown placeholders untouched', () {
      final out = StubLoader.replace(
        '{{ known }} {{ unknown }}',
        {'known': 'X'},
      );
      expect(out, 'X {{ unknown }}');
    });

    test('returns the input verbatim when no replacements supplied', () {
      const input = 'no placeholders here';
      expect(StubLoader.replace(input, const {}), input);
    });
  });

  group('StubLoader.load', () {
    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_stub_test_');
      File('${tempDir.path}/widget.stub')
          .writeAsStringSync('Widget body for {{ className }}.');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('reads a stub file via custom searchPaths', () {
      final content = StubLoader.load('widget', searchPaths: [tempDir.path]);
      expect(content, 'Widget body for {{ className }}.');
    });

    test('throws FileSystemException when stub missing', () {
      expect(
        () => StubLoader.load('nope', searchPaths: [tempDir.path]),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('walks searchPaths in order, returning the first hit', () {
      final secondDir = Directory.systemTemp.createTempSync('artisan_second_');
      addTearDown(() => secondDir.deleteSync(recursive: true));
      File('${secondDir.path}/widget.stub')
          .writeAsStringSync('SECOND wins (should not be returned)');

      // tempDir listed FIRST → its stub wins.
      final content = StubLoader.load('widget',
          searchPaths: [tempDir.path, secondDir.path]);

      expect(content, contains('Widget body for'));
      expect(content, isNot(contains('SECOND wins')));
    });
  });

  group('StubLoader.make', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_make_test_');
      File('${tempDir.path}/greet.stub')
          .writeAsStringSync('Hello, {{ subject }}!');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('load + replace in one call', () {
      // make() uses the default search paths, so we test via load+replace
      // (the helper is a thin convenience over the two).
      final content = StubLoader.load('greet', searchPaths: [tempDir.path]);
      final out = StubLoader.replace(content, {'subject': 'World'});
      expect(out, 'Hello, World!');
    });
  });

  group('StubLoader default search paths (package_config resolver)', () {
    test('load via default paths resolves the consumer_artisan_bin stub', () {
      // No searchPaths arg → exercises _defaultSearchPaths +
      // _resolveFromPackageConfig. The package_config.json sitting at the
      // package root names fluttersdk_artisan, so the resolver returns a
      // valid stub dir.
      final content = StubLoader.load('consumer_artisan_bin.dart');

      expect(content, contains('{{ name }}'));
    });

    test('make composes load + replace via default search paths', () {
      // The loader treats the replacement map as literal substitution; this
      // mirrors how consumer:scaffold renders the bin/artisan.dart wrapper.
      final content = StubLoader.make('consumer_artisan_bin.dart',
          <String, String>{'name': 'my_app'});

      expect(content, contains('my_app'));
    });

    test(
      'load resolves after package name const extraction (regression test)',
      () {
        // Verify that extracting 'fluttersdk_artisan' hardcoded strings to
        // a const does not break stub resolution. This test exercises both
        // package_config.json parsing (line 157) and pubspec walking (line 107)
        // which reference the package name.
        final content = StubLoader.load('consumer_artisan_bin.dart');

        // If the const extraction broke either path, this would throw
        // FileSystemException. Confirming it returns valid content.
        expect(content, isNotEmpty);
        expect(content, contains('{{ name }}'));
      },
    );
  });
}
