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

    test('still anchors on the LAST entry before the closing bracket', () {
      // The lookahead is what keeps the append at the end of the list rather
      // than after the first entry. Widening the parameter must not lose it.
      final pattern = providerPattern(tempDir);
      final match = pattern.firstMatch(appConfig('MagicApp app'))!;

      expect(match.group(0), contains('AppServiceProvider'));
      expect(match.group(0), isNot(contains('RouteServiceProvider')));
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
