import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Resolves the checked-in `assets/stubs/make_plugin/` directory by walking
/// up from the script location. Avoids depending on the consumer's
/// `package_config.json` so the test passes in fresh checkouts before
/// `pub get` has touched the package.
String _resolveCheckedInStubsDir() {
  var current = Directory(p.dirname(Platform.script.toFilePath()));
  for (var i = 0; i < 10; i++) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: fluttersdk_artisan')) {
      return p.join(current.path, 'assets', 'stubs', 'make_plugin');
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return p.join(Directory.current.path, 'assets', 'stubs', 'make_plugin');
}

/// Canonical replacement map used when rendering each stub. Mirrors the map
/// `MakePluginCommand._buildReplacements` constructs at runtime.
Map<String, String> _sampleReplacements() {
  return const <String, String>{
    'name': 'magic_logger',
    'pascalName': 'MagicLogger',
    'commandPrefix': 'logger',
    'bootstrapCommand': 'logger:install',
  };
}

/// The 11-file scaffold roster Step 31 renders. Pinned here so this test
/// stays the source of truth for "every stub must load and render".
const List<String> _stubNames = <String>[
  'pubspec.yaml',
  'cli.dart',
  'runtime.dart',
  'provider.dart',
  'install_command.dart',
  'uninstall_command.dart',
  'install.yaml',
  'config_stub.dart',
  'provider_test.dart',
  'install_command_test.dart',
  'readme.md',
];

/// The four placeholder keys the renderer recognises. Used to assert no
/// stub contains a `{{ <known> }}` after rendering (catches a stub that
/// mis-spells a key).
const Set<String> _knownPlaceholders = <String>{
  'name',
  'pascalName',
  'commandPrefix',
  'bootstrapCommand',
};

void main() {
  late String stubsDir;

  setUpAll(() {
    stubsDir = _resolveCheckedInStubsDir();
  });

  group('make_plugin stub bundle — load', () {
    test('every stub file loads without throwing', () {
      for (final name in _stubNames) {
        expect(
          () => StubLoader.load(name, searchPaths: <String>[stubsDir]),
          returnsNormally,
          reason: '$name.stub failed to load from $stubsDir',
        );
      }
    });

    test('the bundle directory contains exactly the 11 expected stubs', () {
      final dir = Directory(stubsDir);
      expect(dir.existsSync(), isTrue);

      // Compare by full file name minus the trailing `.stub` so we keep
      // `pubspec.yaml`-vs-`pubspec.yml` precision.
      final actualNames = dir
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.stub'))
          .map((f) {
        final base = p.basename(f.path);
        return base.substring(0, base.length - '.stub'.length);
      }).toSet();

      expect(actualNames, _stubNames.toSet());
    });
  });

  group('make_plugin stub bundle — render', () {
    test('every rendered file has zero known placeholders remaining', () {
      for (final name in _stubNames) {
        final raw = StubLoader.load(name, searchPaths: <String>[stubsDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        for (final key in _knownPlaceholders) {
          expect(
            rendered.contains('{{ $key }}'),
            isFalse,
            reason: '$name.stub still contains {{ $key }} after rendering',
          );
        }
      }
    });

    test('every YAML stub parses as valid YAML after rendering', () {
      const yamlStubs = <String>['pubspec.yaml', 'install.yaml'];
      for (final name in yamlStubs) {
        final raw = StubLoader.load(name, searchPaths: <String>[stubsDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        expect(
          () => loadYaml(rendered),
          returnsNormally,
          reason: '$name.stub did not round-trip into valid YAML',
        );
      }
    });

    test('every Dart stub passes a smoke check after rendering', () {
      // The package does NOT depend on `analyzer`, so we do a string-based
      // smoke check: rendered Dart must declare at least one top-level
      // construct (class / void main / library / export / import). This
      // catches the most common scaffolder bug (empty render due to stub
      // path typo) without pulling in the heavy analyzer dep.
      const dartStubs = <String>[
        'cli.dart',
        'runtime.dart',
        'provider.dart',
        'install_command.dart',
        'uninstall_command.dart',
        'config_stub.dart',
        'provider_test.dart',
        'install_command_test.dart',
      ];

      final declarationAnchors = <RegExp>[
        RegExp(r'^class\s+\w+', multiLine: true),
        RegExp(r'^void\s+main\b', multiLine: true),
        RegExp(r'^library;?', multiLine: true),
        RegExp(r'^import\s+', multiLine: true),
        RegExp(r'^export\s+', multiLine: true),
      ];

      for (final name in dartStubs) {
        final raw = StubLoader.load(name, searchPaths: <String>[stubsDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        final hasAnchor =
            declarationAnchors.any((anchor) => anchor.hasMatch(rendered));
        expect(
          hasAnchor,
          isTrue,
          reason: '$name.stub rendered without a top-level Dart construct',
        );
      }
    });

    test('install.yaml.stub preserves the manifest-resolved placeholder', () {
      // The manifest renderer (ManifestInstaller) resolves
      // `{{ prompts.configPath }}` at install time. The scaffolder MUST NOT
      // touch that token — its replacement map only knows the four scaffold
      // keys, so any `{{ <unknown> }}` survives by design.
      final raw =
          StubLoader.load('install.yaml', searchPaths: <String>[stubsDir]);
      final rendered = StubLoader.replace(raw, _sampleReplacements());

      expect(rendered, contains('{{ prompts.configPath }}'));
    });
  });
}
