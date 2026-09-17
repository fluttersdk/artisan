import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

class _SilentPromptDriver implements PromptDriver {
  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) =>
      defaultValue ?? '';

  @override
  bool confirm(String question, {bool defaultValue = false}) => defaultValue;

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) =>
      defaultValue ?? options.first;

  @override
  String secret(String question) => '';
}

class _SilentStubDriver implements StubDriver {
  @override
  String load(String name, {List<String>? searchPaths}) => '';

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) => '';
}

/// The transaction-level half of the pattern-injection change.
///
/// `config_editor_match_report_test.dart` covers the helper's return value and
/// `inject_provider_shapes_test.dart` covers the regex. Neither commits a
/// transaction, so neither reaches the preflight or the failure path, and
/// those are where the consequence lives: a miss discovered mid-stage leaves
/// helper writes on disk with no install record to reverse them.
void main() {
  Directory makeProject() {
    final tmp = Directory.systemTemp.createTempSync('artisan_preflight_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    return tmp;
  }

  InstallContext ctxFor(Directory root) {
    return InstallContext.test(
      fs: RealFs(),
      prompt: _SilentPromptDriver(),
      stubs: _SilentStubDriver(),
      clock: () => DateTime.utc(2025, 6, 1),
      projectRoot: root.path,
    );
  }

  /// A providers list in the shape `injectProvider` appends to.
  void writeAppConfig(Directory root, {required bool populated}) {
    final entries =
        populated ? "      (MagicApp app) => AppServiceProvider(app),\n" : '';
    File('${root.path}/lib/config/app.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "const Map<String, dynamic> appConfig = {\n"
        "  'app': {\n"
        "    'providers': [\n"
        '$entries'
        '    ],\n'
        '  },\n'
        '};\n',
      );
  }

  group('a pattern that cannot land refuses the commit', () {
    test('returns Error and writes no install record', () async {
      final root = makeProject();
      writeAppConfig(root, populated: true);

      final tx = InstallTransaction(ctxFor(root), pluginName: 'demo');
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(r'NoSuchAnchorAnywhere'),
        code: '\n      (app) => DemoServiceProvider(app),',
      ));

      final result = await tx.commit(force: true);

      expect(result, isA<Error>());
      expect((result as Error).error, contains('lib/config/app.dart'));
      expect(
        File('${root.path}/.artisan/installed/demo.json').existsSync(),
        isFalse,
      );
    });

    test('leaves no partial write behind, which is why it runs first',
        () async {
      // The reason the check is a preflight rather than an in-loop return.
      // `InjectImport` writes through `dart:io` during staging and sits
      // outside the `.tmp` rollback, so discovering the miss after it had run
      // would strand that import with no record to reverse it.
      final root = makeProject();
      writeAppConfig(root, populated: true);
      final before =
          File('${root.path}/lib/config/app.dart').readAsStringSync();

      final tx = InstallTransaction(ctxFor(root), pluginName: 'demo');
      tx.stage(const InjectImport(
        targetFile: 'lib/config/app.dart',
        importStatement: "import 'package:demo/demo.dart';",
      ));
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(r'NoSuchAnchorAnywhere'),
        code: '\n      (app) => DemoServiceProvider(app),',
      ));

      expect(await tx.commit(force: true), isA<Error>());
      expect(
        File('${root.path}/lib/config/app.dart').readAsStringSync(),
        before,
        reason: 'the import must not have landed',
      );
    });

    test('names every offending op, not only the first', () async {
      final root = makeProject();
      writeAppConfig(root, populated: true);

      final tx = InstallTransaction(ctxFor(root), pluginName: 'demo');
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(r'FirstMissingAnchor'),
        code: '// a',
      ));
      tx.stage(InjectBeforePattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(r'SecondMissingAnchor'),
        code: '// b',
      ));

      final result = await tx.commit(force: true) as Error;

      expect(result.error, contains('FirstMissingAnchor'));
      expect(result.error, contains('SecondMissingAnchor'));
    });

    test('a missing target file is named rather than thrown on', () async {
      final root = makeProject();

      final tx = InstallTransaction(ctxFor(root), pluginName: 'demo');
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(r'anything'),
        code: '// a',
      ));

      final result = await tx.commit(force: true) as Error;

      expect(result.error, contains('does not exist'));
    });
  });

  group('the fallback pattern keeps an empty list installable', () {
    test('an empty providers list takes the injection', () async {
      // Without the fallback this is the case that used to inject nothing and
      // report Success, and that would now fail the install outright. Neither
      // is right: a fresh `magic:install` scaffold has an empty list.
      final root = makeProject();
      writeAppConfig(root, populated: false);

      final tx = InstallTransaction(ctxFor(root), pluginName: 'demo');
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(
          r'\((?:\w+\s+)?app\)\s*=>\s*\w+ServiceProvider\(app\),(?=\s*\n\s*\])',
        ),
        fallbackPattern: RegExp(r"'providers'\s*:\s*\["),
        code: '\n      (app) => DemoServiceProvider(app),',
      ));

      expect(await tx.commit(force: true), isA<Success>());
      expect(
        File('${root.path}/lib/config/app.dart').readAsStringSync(),
        contains('DemoServiceProvider'),
      );
    });

    test('a populated list still appends at the end, not at the bracket',
        () async {
      // The fallback must not win where the primary matches, or every
      // injection would land at the top of the list.
      final root = makeProject();
      writeAppConfig(root, populated: true);

      final tx = InstallTransaction(ctxFor(root), pluginName: 'demo');
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(
          r'\((?:\w+\s+)?app\)\s*=>\s*\w+ServiceProvider\(app\),(?=\s*\n\s*\])',
        ),
        fallbackPattern: RegExp(r"'providers'\s*:\s*\["),
        code: '\n      (app) => DemoServiceProvider(app),',
      ));

      expect(await tx.commit(force: true), isA<Success>());

      final written =
          File('${root.path}/lib/config/app.dart').readAsStringSync();
      expect(
        written.indexOf('DemoServiceProvider'),
        greaterThan(written.indexOf('AppServiceProvider')),
      );
    });
  });

  test('a re-run over an already-injected file still commits', () async {
    // The preflight must treat an idempotent skip as resolvable, or
    // `plugin:install` would fail on a project it has already installed into.
    final root = makeProject();
    writeAppConfig(root, populated: true);

    Future<TransactionResult> install() {
      final tx = InstallTransaction(ctxFor(root), pluginName: 'demo');
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/config/app.dart',
        pattern: RegExp(
          r'\((?:\w+\s+)?app\)\s*=>\s*\w+ServiceProvider\(app\),(?=\s*\n\s*\])',
        ),
        fallbackPattern: RegExp(r"'providers'\s*:\s*\["),
        code: '\n      (app) => DemoServiceProvider(app),',
      ));

      return tx.commit(force: true);
    }

    expect(await install(), isA<Success>());
    expect(await install(), isA<Success>());

    final written = File('${root.path}/lib/config/app.dart').readAsStringSync();
    expect('DemoServiceProvider'.allMatches(written).length, 1);
  });
}
