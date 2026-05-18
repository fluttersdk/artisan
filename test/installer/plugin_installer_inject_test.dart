import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only driver fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

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

InstallContext _ctxFor(Directory tempDir) {
  return InstallContext.test(
    fs: const RealFs(),
    prompt: _SilentPromptDriver(),
    stubs: _SilentStubDriver(),
    projectRoot: tempDir.path,
  );
}

/// Magic-shaped lib/main.dart fixture mirroring Wave 1 MainDartEditor tests.
const _mainDartFixture = '''
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

/// lib/config/app.dart fixture mirroring Magic's providers list shape.
const _appConfigFixture = '''
import 'package:magic/magic.dart';

class AppConfig {
  static Map<String, dynamic> build() {
    return {
      'providers': [
        (app) => AppServiceProvider(app),
        (app) => RouteServiceProvider(app),
      ],
    };
  }
}
''';

/// route_service_provider.dart fixture for InjectRouteRegistration tests.
const _routeProviderFixture = '''
import 'package:magic/magic.dart';

class RouteServiceProvider extends ServiceProvider {
  @override
  Future<void> boot() async {
    registerAppRoutes();
  }
}
''';

void main() {
  group('PluginInstaller — inject chain methods (enqueue)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_inj_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectImport enqueues InjectImport', () {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').injectImport(
        targetFile: 'lib/x.dart',
        importStatement: "import 'package:y/y.dart';",
      );
      final op = installer.pendingOps.single as InjectImport;
      expect(op.targetFile, 'lib/x.dart');
      expect(op.importStatement, "import 'package:y/y.dart';");
    });

    test('injectBefore enqueues InjectBeforePattern', () {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').injectBefore(
        targetFile: 'lib/x.dart',
        pattern: 'MARK',
        code: 'B\n',
      );
      final op = installer.pendingOps.single as InjectBeforePattern;
      expect(op.targetFile, 'lib/x.dart');
      expect(op.pattern, 'MARK');
      expect(op.code, 'B\n');
    });

    test('injectAfter enqueues InjectAfterPattern', () {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').injectAfter(
        targetFile: 'lib/x.dart',
        pattern: 'MARK',
        code: '\nA',
      );
      final op = installer.pendingOps.single as InjectAfterPattern;
      expect(op.code, '\nA');
    });

    test('injectMainDartImport enqueues InjectMainDartImport', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectMainDartImport("import 'package:a/a.dart';");
      final op = installer.pendingOps.single as InjectMainDartImport;
      expect(op.importStatement, "import 'package:a/a.dart';");
    });

    test(
        'injectBeforeMagicInit / injectAfterMagicInit / wrapRunApp enqueue '
        'placements', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectBeforeMagicInit('A.boot();')
          .injectAfterMagicInit('A.warm();')
          .wrapRunApp('SentryWidget');

      expect(installer.pendingCount, 3);
      expect((installer.pendingOps[0] as InjectIntoMainDart).placement,
          MainDartPlacement.beforeInit);
      expect((installer.pendingOps[1] as InjectIntoMainDart).placement,
          MainDartPlacement.afterInit);
      expect((installer.pendingOps[2] as InjectIntoMainDart).placement,
          MainDartPlacement.wrapRunApp);
      expect(
          (installer.pendingOps[2] as InjectIntoMainDart).code, 'SentryWidget');
    });

    test('injectProvider enqueues composite InjectImport + InjectAfterPattern',
        () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectProvider('DemoServiceProvider');

      expect(installer.pendingCount, 2);
      final imp = installer.pendingOps[0] as InjectImport;
      final inj = installer.pendingOps[1] as InjectAfterPattern;
      expect(imp.targetFile, 'lib/config/app.dart');
      expect(imp.importStatement, "import 'package:demo/demo.dart';");
      expect(inj.targetFile, 'lib/config/app.dart');
      expect(inj.code, contains('DemoServiceProvider(app)'));
    });

    test('injectProvider honours custom package override', () {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').injectProvider(
        'CustomProvider',
        package: 'package:other/other.dart',
      );
      final imp = installer.pendingOps[0] as InjectImport;
      expect(imp.importStatement, "import 'package:other/other.dart';");
    });

    test('injectConfigFactory enqueues import + main.dart insertion', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectConfigFactory('demoConfig');

      expect(installer.pendingCount, 2);
      expect(installer.pendingOps[0], isA<InjectMainDartImport>());
      final inj = installer.pendingOps[1] as InjectAfterPattern;
      expect(inj.targetFile, 'lib/main.dart');
      expect(inj.code, contains('() => demoConfig,'));
    });

    test('injectRoute enqueues InjectRouteRegistration', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectRoute('registerDemoRoutes');
      final op = installer.pendingOps.single as InjectRouteRegistration;
      expect(op.functionName, 'registerDemoRoutes');
    });
  });

  group('PluginInstaller — inject dispatcher applies ops', () {
    late Directory tempDir;
    late String mainDartPath;
    late String appConfigPath;
    late String routeProviderPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_inj_disp_');
      mainDartPath = p.join(tempDir.path, 'lib', 'main.dart');
      appConfigPath = p.join(tempDir.path, 'lib', 'config', 'app.dart');
      routeProviderPath = p.join(tempDir.path, 'lib', 'app', 'providers',
          'route_service_provider.dart');

      File(mainDartPath).createSync(recursive: true);
      File(mainDartPath).writeAsStringSync(_mainDartFixture);
      File(appConfigPath).createSync(recursive: true);
      File(appConfigPath).writeAsStringSync(_appConfigFixture);
      File(routeProviderPath).createSync(recursive: true);
      File(routeProviderPath).writeAsStringSync(_routeProviderFixture);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectImport adds import to a generic Dart file', () async {
      final target = File(p.join(tempDir.path, 'lib', 'x.dart'));
      target.writeAsStringSync(
          "import 'package:meta/meta.dart';\n\nvoid main() {}\n");

      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').injectImport(
        targetFile: 'lib/x.dart',
        importStatement: "import 'package:y/y.dart';",
      );

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      expect(target.readAsStringSync(), contains("package:y/y.dart"));
    });

    test('injectBefore / injectAfter mutate at the anchor', () async {
      final target = File(p.join(tempDir.path, 'snippet.dart'));
      target.writeAsStringSync('A\nMARK\nC\n');

      final result = await PluginInstaller(
        _ctxFor(tempDir),
        pluginName: 'demo',
      )
          .injectBefore(
            targetFile: 'snippet.dart',
            pattern: 'MARK',
            code: 'B-before\n',
          )
          .injectAfter(
            targetFile: 'snippet.dart',
            pattern: 'MARK',
            code: '\nB-after',
          )
          .commit(force: true);

      expect(result, isA<Success>());
      final content = target.readAsStringSync();
      expect(content, contains('B-before'));
      expect(content, contains('B-after'));
    });

    test('injectMainDartImport adds import to lib/main.dart', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectMainDartImport("import 'package:demo/demo.dart';");

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      expect(File(mainDartPath).readAsStringSync(),
          contains("import 'package:demo/demo.dart';"));
    });

    test('injectBeforeMagicInit inserts before Magic.init', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectBeforeMagicInit('Demo.boot();');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final content = File(mainDartPath).readAsStringSync();
      final initIdx = content.indexOf('Magic.init');
      final demoIdx = content.indexOf('Demo.boot();');
      expect(demoIdx, greaterThan(0));
      expect(demoIdx, lessThan(initIdx));
    });

    test('injectAfterMagicInit inserts after the init block', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectAfterMagicInit('Demo.warm();');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final content = File(mainDartPath).readAsStringSync();
      expect(content, contains('Demo.warm();'));
    });

    test('wrapRunApp wraps runApp argument', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .wrapRunApp('SentryWidget');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      expect(File(mainDartPath).readAsStringSync(),
          contains('runApp(SentryWidget(MyApp()))'));
    });

    test('injectProvider adds import + provider closure entry', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectProvider('DemoServiceProvider');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final content = File(appConfigPath).readAsStringSync();
      expect(content, contains("import 'package:demo/demo.dart';"));
      expect(content, contains('(app) => DemoServiceProvider(app),'));
    });

    test('injectConfigFactory adds import + factories list entry', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectConfigFactory('demoConfig');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final content = File(mainDartPath).readAsStringSync();
      expect(content, contains("import 'package:demo/demo.dart';"));
      expect(content, contains('() => demoConfig,'));
    });

    test('injectRoute inserts a call into RouteServiceProvider.boot()',
        () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectRoute('registerDemoRoutes');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final content = File(routeProviderPath).readAsStringSync();
      expect(content, contains('registerDemoRoutes();'));
      expect(content, contains('registerAppRoutes();'));
    });

    test('inject chain returns this across all methods', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo');
      final chained = installer
          .injectImport(targetFile: 'a', importStatement: "import 'x';")
          .injectBefore(targetFile: 'a', pattern: 'M', code: 'b')
          .injectAfter(targetFile: 'a', pattern: 'M', code: 'b')
          .injectMainDartImport("import 'x';")
          .injectBeforeMagicInit('x')
          .injectAfterMagicInit('x')
          .wrapRunApp('Wrap')
          .injectProvider('P')
          .injectConfigFactory('F')
          .injectRoute('r');
      expect(chained, same(installer));
    });
  });

  group('PluginInstaller — end-of-list inject (Change E pattern + indent)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_inj_end_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// lib/config/app.dart fixture with 3 existing provider entries, mirroring
    /// the real magic:install scaffold shape. All three names end in
    /// `ServiceProvider` to satisfy the production regex
    /// `\w+ServiceProvider\(app\),(?=\s*\n\s*\])`. The closing `]` sits on its
    /// own line with 6-space indent so the lookahead fires on the last entry.
    const appConfigFixtureMultiProvider = '''
import 'package:magic/magic.dart';

class AppConfig {
  static Map<String, dynamic> build() {
    return {
      'providers': [
        (app) => AppServiceProvider(app),
        (app) => RouteServiceProvider(app),
        (app) => LoggingServiceProvider(app),
      ],
    };
  }
}
''';

    /// lib/main.dart fixture with 2 existing configFactories entries.
    /// The closing `]` is on its own line so the lookahead `(?=\s*\n\s*\])` fires.
    const mainDartFixtureMultiFactory = '''
import 'package:magic/magic.dart';
import 'config/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(
    configFactories: [
      () => fooConfig,
      () => barConfig,
    ],
  );
  runApp(MyApp());
}
''';

    test(
        'injectProvider appends to the END of the providers list (not the top)',
        () async {
      // Seed the multi-provider fixture to disk.
      final appConfigPath = p.join(tempDir.path, 'lib', 'config', 'app.dart');
      File(appConfigPath).createSync(recursive: true);
      File(appConfigPath).writeAsStringSync(appConfigFixtureMultiProvider);

      final result =
          await PluginInstaller(_ctxFor(tempDir), pluginName: 'mytest')
              .injectProvider('MyTestProvider')
              .commit(force: true);

      expect(result, isA<Success>());
      final content = File(appConfigPath).readAsStringSync();
      // The new entry must land AFTER the last existing provider, not before it.
      final newIdx = content.indexOf('MyTestProvider');
      final lastExistingIdx = content.indexOf('LoggingServiceProvider');
      expect(newIdx, greaterThan(lastExistingIdx));
    });

    test(
        'injectProvider uses 6-space indent matching the surrounding list style',
        () async {
      final appConfigPath = p.join(tempDir.path, 'lib', 'config', 'app.dart');
      File(appConfigPath).createSync(recursive: true);
      File(appConfigPath).writeAsStringSync(appConfigFixtureMultiProvider);

      final result =
          await PluginInstaller(_ctxFor(tempDir), pluginName: 'mytest')
              .injectProvider('MyTestProvider')
              .commit(force: true);

      expect(result, isA<Success>());
      final content = File(appConfigPath).readAsStringSync();
      // The injected line must start with exactly 6 spaces (matching list peers).
      expect(
        content,
        matches(
          RegExp(r'^      \(app\) => MyTestProvider\(app\),$', multiLine: true),
        ),
      );
    });

    test('injectConfigFactory appends to the END of the configFactories list',
        () async {
      // Seed the multi-factory main.dart fixture to disk.
      final mainDartPath = p.join(tempDir.path, 'lib', 'main.dart');
      File(mainDartPath).createSync(recursive: true);
      File(mainDartPath).writeAsStringSync(mainDartFixtureMultiFactory);

      final result =
          await PluginInstaller(_ctxFor(tempDir), pluginName: 'mytest')
              .injectConfigFactory('myConfig')
              .commit(force: true);

      expect(result, isA<Success>());
      final content = File(mainDartPath).readAsStringSync();
      // The new entry must land AFTER the last existing factory, not before it.
      final newIdx = content.indexOf('myConfig');
      final lastExistingIdx = content.indexOf('barConfig');
      expect(newIdx, greaterThan(lastExistingIdx));
    });

    test('injectConfigFactory uses 6-space indent', () async {
      final mainDartPath = p.join(tempDir.path, 'lib', 'main.dart');
      File(mainDartPath).createSync(recursive: true);
      File(mainDartPath).writeAsStringSync(mainDartFixtureMultiFactory);

      final result =
          await PluginInstaller(_ctxFor(tempDir), pluginName: 'mytest')
              .injectConfigFactory('myConfig')
              .commit(force: true);

      expect(result, isA<Success>());
      final content = File(mainDartPath).readAsStringSync();
      // The injected line must start with exactly 6 spaces (matching list peers).
      expect(
        content,
        matches(RegExp(r'^      \(\) => myConfig,$', multiLine: true)),
      );
    });
  });
}
