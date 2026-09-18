import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Test-only driver fakes, the same shape `plugin_installer_inject_test.dart`
// uses. They are not exported from `lib/`.
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

/// `injectProvider`'s regex against the two shapes a real `lib/config/app.dart`
/// is written in, plus the silent-failure behaviour that made a mismatch
/// invisible.
///
/// Both shapes exist in the wild: `uptizm` writes `(app) =>` and `watchools`
/// writes `(MagicApp app) =>`. The type annotation is optional in Dart, so
/// neither is wrong, and a pattern that admits only one of them meant every
/// plugin install against the other injected nothing while reporting Success.
void main() {
  /// The providers list in the shape a plugin installer has to append to.
  String appConfig(String parameter) {
    return '''
const Map<String, dynamic> appConfig = <String, dynamic>{
  'app': <String, dynamic>{
    'providers': [
      ($parameter) => RouteServiceProvider(app),
      ($parameter) => AppServiceProvider(app),
    ],
  },
};
''';
  }

  /// The pattern `PluginInstaller.injectProvider` enqueues, read off the op it
  /// builds rather than copied, so this test cannot drift from the source.
  RegExp providerPattern(Directory root) {
    final installer = PluginInstaller(
      InstallContext.test(
        fs: const RealFs(),
        prompt: _SilentPromptDriver(),
        stubs: _SilentStubDriver(),
        projectRoot: root.path,
      ),
      pluginName: 'demo',
    ).injectProvider('DemoServiceProvider');

    return (installer.pendingOps[1] as InjectAfterPattern).pattern as RegExp;
  }

  /// The `injectConfigFactory` op, read off the installer for the same reason.
  InjectAfterPattern configFactoryOp(Directory root) {
    final installer = PluginInstaller(
      InstallContext.test(
        fs: const RealFs(),
        prompt: _SilentPromptDriver(),
        stubs: _SilentStubDriver(),
        projectRoot: root.path,
      ),
      pluginName: 'demo',
    ).injectConfigFactory('demoConfig');

    return installer.pendingOps[1] as InjectAfterPattern;
  }

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('artisan_inject_shapes_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('injectProvider matches both parameter spellings', () {
    test('the bare form, as uptizm writes it', () {
      final pattern = providerPattern(tempDir);

      expect(pattern.hasMatch(appConfig('app')), isTrue);
    });

    test('the typed form, as watchools writes it', () {
      final pattern = providerPattern(tempDir);

      expect(pattern.hasMatch(appConfig('MagicApp app')), isTrue);
    });

    test('still ENDS at the last entry before the closing bracket', () {
      // The lookahead is what keeps the append at the end of the list rather
      // than after the first entry. Widening the parameter must not lose it.
      //
      // The assertion is on where the match ENDS, not on what it spans: the
      // pattern now starts at `'providers': [` to keep the scan inside the
      // list, so its text necessarily carries every earlier entry. `match.end`
      // is the byte `insertCodeAfterPattern` writes at, which is the thing
      // that has to stay pinned to the last entry.
      final pattern = providerPattern(tempDir);
      final content = appConfig('MagicApp app');
      final match = pattern.firstMatch(content)!;

      expect(
        content.substring(0, match.end),
        endsWith('(MagicApp app) => AppServiceProvider(app),'),
      );
      expect(content.substring(match.end).trim(), startsWith(']'));
    });
  });

  group('the match is anchored to the list it is meant to append to', () {
    /// A `lib/main.dart` carrying a zero-argument-closure list ABOVE
    /// `configFactories`. Nothing stops a host from writing one, and
    /// `() => \w+,` before a `]` describes its last entry exactly as well.
    String mainDart({required bool factoriesPopulated}) {
      final String factories =
          factoriesPopulated ? '\n      () => appConfig,\n    ' : '';
      return '''
final List<Widget Function()> screens = [
  () => homeScreen,
];

void main() async {
  await Magic.init(
    configFactories: [$factories],
  );
}
''';
    }

    test('an earlier list does not take the configFactories injection', () {
      // The defect this anchor exists for: firstMatch scans by position, so
      // the primary used to land on `() => homeScreen,` and the factory was
      // appended to `screens`.
      final filePath = p.join(tempDir.path, 'main.dart');
      File(filePath).writeAsStringSync(mainDart(factoriesPopulated: true));
      final op = configFactoryOp(tempDir);

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: op.pattern,
        fallbackPattern: op.fallbackPattern,
        code: op.code,
      );

      expect(applied, isTrue);

      final written = File(filePath).readAsStringSync();
      expect(
        written.indexOf('demoConfig'),
        greaterThan(written.indexOf('appConfig')),
        reason: 'the factory belongs after the last configFactories entry',
      );
      expect(
        written.indexOf('demoConfig'),
        greaterThan(written.indexOf('homeScreen')),
        reason: 'and not inside the screens list above it',
      );
    });

    test('an empty configFactories is a non-match, so the fallback runs', () {
      // The same defect with a second face. The primary matched the earlier
      // list's last entry, so the fallback that exists for the empty case
      // never got to run and the factory went into `screens`.
      final filePath = p.join(tempDir.path, 'main.dart');
      File(filePath).writeAsStringSync(mainDart(factoriesPopulated: false));
      final op = configFactoryOp(tempDir);

      expect(
        (op.pattern as RegExp).hasMatch(File(filePath).readAsStringSync()),
        isFalse,
        reason: 'the gap excludes `]`, so the scan cannot leave the list',
      );

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: op.pattern,
        fallbackPattern: op.fallbackPattern,
        code: op.code,
      );

      expect(applied, isTrue);

      final written = File(filePath).readAsStringSync();
      expect(written, contains('configFactories: [\n      () => demoConfig,'));
      expect(
        written.indexOf('demoConfig'),
        greaterThan(written.indexOf('homeScreen')),
      );
    });

    test('a trailing line comment on the last entry still appends', () {
      // This shape used to defeat the lookahead and fall through to the
      // fallback, which prepends: correct Dart, wrong position.
      final filePath = p.join(tempDir.path, 'app.dart');
      File(filePath).writeAsStringSync('''
const Map<String, dynamic> appConfig = <String, dynamic>{
  'app': <String, dynamic>{
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => AppServiceProvider(app), // core
    ],
  },
};
''');

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: providerPattern(tempDir),
        code: '\n      (app) => DemoServiceProvider(app),',
      );

      expect(applied, isTrue);

      final written = File(filePath).readAsStringSync();
      expect(
        written.indexOf('DemoServiceProvider'),
        greaterThan(written.indexOf('AppServiceProvider')),
      );
    });

    test('a double-quoted providers key still matches', () {
      // Anchoring on the key made its quoting load-bearing for one round.
      // `prefer_single_quotes` makes this uncommon rather than impossible, and
      // a host who writes it installed correctly before the anchor.
      final pattern = providerPattern(tempDir);

      expect(
        pattern.hasMatch(
            appConfig('app').replaceAll("'providers'", '"providers"')),
        isTrue,
      );
    });

    test('a comment on its own line above the bracket does not defeat it', () {
      // The shape a scaffold placeholder takes. It fell to the fallback and
      // prepended, which is correct Dart in the wrong position.
      final filePath = p.join(tempDir.path, 'app.dart');
      File(filePath).writeAsStringSync('''
const Map<String, dynamic> appConfig = <String, dynamic>{
  'app': <String, dynamic>{
    'providers': [
      (app) => AppServiceProvider(app),
      // add plugin providers here
    ],
  },
};
''');

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: providerPattern(tempDir),
        code: '\n      (app) => DemoServiceProvider(app),',
      );

      expect(applied, isTrue);

      final written = File(filePath).readAsStringSync();
      expect(
        written.indexOf('DemoServiceProvider'),
        greaterThan(written.indexOf('AppServiceProvider')),
        reason: 'the entry belongs after the last one, not at the bracket',
      );
    });

    test('but a real entry below is never skipped', () {
      // The lookahead consumes only whitespace-or-comment lines, so it cannot
      // walk past an entry to reach the bracket. Losing that would move every
      // append to the first entry.
      final pattern = providerPattern(tempDir);
      final content = appConfig('app');
      final match = pattern.firstMatch(content)!;

      expect(
        content.substring(0, match.end),
        endsWith('(app) => AppServiceProvider(app),'),
      );
    });

    test('injectProvider is anchored to the providers list as well', () {
      // Same class of defect, same anchor. `\\w+ServiceProvider(app),` was the
      // accidental guard here, not a deliberate one.
      final pattern = providerPattern(tempDir);
      const String twoLists = '''
const Map<String, dynamic> appConfig = <String, dynamic>{
  'app': <String, dynamic>{
    'deferred': [
      (app) => LateServiceProvider(app),
    ],
    'providers': [
      (app) => AppServiceProvider(app),
    ],
  },
};
''';

      final match = pattern.firstMatch(twoLists)!;

      expect(match.group(0), contains('AppServiceProvider'));
      expect(match.group(0), isNot(contains('LateServiceProvider')));
    });
  });

  group('a pattern that matches nothing is an install failure', () {
    test('insertCodeAfterPattern leaves a non-matching file untouched', () {
      // The helper's own contract. Before it answered a bool, this was
      // indistinguishable from a successful injection at every layer above.
      final filePath = p.join(tempDir.path, 'app.dart');
      final original = appConfig('MagicApp app');
      File(filePath).writeAsStringSync(original);

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: RegExp(r'\(app\)\s*=>\s*NoSuchProvider\(app\),'),
        code: '\n      (app) => DemoServiceProvider(app),',
      );

      expect(applied, isFalse);
      expect(File(filePath).readAsStringSync(), original);
    });

    test('and a matching one appends at the end of the list', () {
      final filePath = p.join(tempDir.path, 'app.dart');
      File(filePath).writeAsStringSync(appConfig('MagicApp app'));

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: providerPattern(tempDir),
        code: '\n      (app) => DemoServiceProvider(app),',
      );

      expect(applied, isTrue);

      final written = File(filePath).readAsStringSync();
      expect(
        written.indexOf('DemoServiceProvider'),
        greaterThan(written.indexOf('AppServiceProvider')),
      );
    });
  });
}
