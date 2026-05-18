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

/// Canonical replacement map used when rendering each stub. Mirrors the full
/// map `MakePluginCommand._buildReplacements` constructs at runtime, including
/// the `artisanPath` and `magicPath` keys added in the generic/magic split.
Map<String, String> _sampleReplacements() {
  return const <String, String>{
    'name': 'magic_logger',
    'pascalName': 'MagicLogger',
    'commandPrefix': 'logger',
    'bootstrapCommand': 'logger:install',
    'artisanPath': '../fluttersdk_artisan',
    'magicPath': '../magic',
  };
}

/// The 7 stub file names that live under `generic/`. Pinned here so this test
/// stays the source of truth for "every generic stub must load and render".
/// `bin_artisan.dart` added in make-plugin-modes Wave 4 to make
/// `dart run <plugin>:artisan` invocations work out-of-box.
const List<String> _genericStubNames = <String>[
  'pubspec.yaml',
  'bin_artisan.dart',
  'cli.dart',
  'runtime.dart',
  'provider.dart',
  'provider_test.dart',
  'readme.md',
];

/// The 9 stub file names that live under `magic/`. The `cli.dart`,
/// `pubspec.yaml`, and `runtime.dart` entries are magic-specific overrides
/// (magic: dep, magic command exports, ServiceProvider re-export); they are
/// distinct files from their generic counterparts.
const List<String> _magicStubNames = <String>[
  'pubspec.yaml',
  'cli.dart',
  'runtime.dart',
  'install.yaml',
  'install_command.dart',
  'uninstall_command.dart',
  'install_command_test.dart',
  'config_stub.dart',
  'service_provider.dart',
];

/// The four known scaffold-time placeholder keys. Used to assert that no stub
/// contains a `{{ <known> }}` token after rendering (catches a stub that
/// mis-spells a key). Install-time tokens (`prompts.configPath`,
/// `configFilePath`) survive rendering by design and are excluded.
const Set<String> _knownScaffoldPlaceholders = <String>{
  'name',
  'pascalName',
  'commandPrefix',
  'bootstrapCommand',
  'artisanPath',
  'magicPath',
};

void main() {
  late String stubsDir;
  late String genericDir;
  late String magicDir;

  setUpAll(() {
    stubsDir = _resolveCheckedInStubsDir();
    genericDir = p.join(stubsDir, 'generic');
    magicDir = p.join(stubsDir, 'magic');
  });

  // ---------------------------------------------------------------------------
  // Load — file presence assertions.
  // ---------------------------------------------------------------------------

  group('make_plugin stub bundle — generic load', () {
    test('generic/ directory exists and is non-empty', () {
      expect(Directory(genericDir).existsSync(), isTrue);
    });

    test('every generic stub file loads without throwing', () {
      for (final name in _genericStubNames) {
        expect(
          () => StubLoader.load(name, searchPaths: <String>[genericDir]),
          returnsNormally,
          reason: '$name.stub failed to load from $genericDir',
        );
      }
    });

    test('generic/ contains exactly the 7 expected stubs — no extras, no gaps',
        () {
      final actualNames = Directory(genericDir)
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.stub'))
          .map((f) {
        final base = p.basename(f.path);
        return base.substring(0, base.length - '.stub'.length);
      }).toSet();

      expect(actualNames, equals(_genericStubNames.toSet()));
    });
  });

  group('make_plugin stub bundle — magic load', () {
    test('magic/ directory exists and is non-empty', () {
      expect(Directory(magicDir).existsSync(), isTrue);
    });

    test('every magic stub file loads without throwing', () {
      for (final name in _magicStubNames) {
        expect(
          () => StubLoader.load(name, searchPaths: <String>[magicDir]),
          returnsNormally,
          reason: '$name.stub failed to load from $magicDir',
        );
      }
    });

    test('magic/ contains exactly the 9 expected stubs — no extras, no gaps',
        () {
      final actualNames = Directory(magicDir)
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.stub'))
          .map((f) {
        final base = p.basename(f.path);
        return base.substring(0, base.length - '.stub'.length);
      }).toSet();

      expect(actualNames, equals(_magicStubNames.toSet()));
    });
  });

  group('make_plugin stub bundle — combined layout', () {
    test('total distinct stub file count is 16 (7 generic + 9 magic)', () {
      // generic/ + magic/ each contribute their full roster. cli.dart,
      // pubspec.yaml, and runtime.dart appear in both subdirs as distinct,
      // mode-specific files.
      final genericCount = Directory(genericDir)
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.stub'))
          .length;
      final magicCount = Directory(magicDir)
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.stub'))
          .length;

      expect(genericCount, 7, reason: 'generic/ stub count mismatch');
      expect(magicCount, 9, reason: 'magic/ stub count mismatch');
      expect(genericCount + magicCount, 16);
    });
  });

  // ---------------------------------------------------------------------------
  // Render — placeholder and format assertions.
  // ---------------------------------------------------------------------------

  group('make_plugin stub bundle — generic render', () {
    test('every generic stub has zero known scaffold placeholders after render',
        () {
      for (final name in _genericStubNames) {
        final raw = StubLoader.load(name, searchPaths: <String>[genericDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        for (final key in _knownScaffoldPlaceholders) {
          expect(
            rendered.contains('{{ $key }}'),
            isFalse,
            reason:
                'generic/$name.stub still contains {{ $key }} after rendering',
          );
        }
      }
    });

    test('generic pubspec.yaml parses as valid YAML after rendering', () {
      final raw =
          StubLoader.load('pubspec.yaml', searchPaths: <String>[genericDir]);
      final rendered = StubLoader.replace(raw, _sampleReplacements());

      expect(
        () => loadYaml(rendered),
        returnsNormally,
        reason: 'generic/pubspec.yaml.stub did not round-trip into valid YAML',
      );
    });

    test('every generic Dart stub passes a smoke check after rendering', () {
      const dartStubs = <String>[
        'cli.dart',
        'runtime.dart',
        'provider.dart',
        'provider_test.dart',
      ];

      final declarationAnchors = <RegExp>[
        RegExp(r'^class\s+\w+', multiLine: true),
        RegExp(r'^void\s+main\b', multiLine: true),
        RegExp(r'^library;?', multiLine: true),
        RegExp(r'^import\s+', multiLine: true),
        RegExp(r'^export\s+', multiLine: true),
      ];

      for (final name in dartStubs) {
        final raw = StubLoader.load(name, searchPaths: <String>[genericDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        final hasAnchor =
            declarationAnchors.any((anchor) => anchor.hasMatch(rendered));
        expect(
          hasAnchor,
          isTrue,
          reason:
              'generic/$name.stub rendered without a top-level Dart construct',
        );
      }
    });
  });

  group('make_plugin stub bundle — magic render', () {
    test('every magic stub has zero known scaffold placeholders after render',
        () {
      for (final name in _magicStubNames) {
        final raw = StubLoader.load(name, searchPaths: <String>[magicDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        for (final key in _knownScaffoldPlaceholders) {
          expect(
            rendered.contains('{{ $key }}'),
            isFalse,
            reason:
                'magic/$name.stub still contains {{ $key }} after rendering',
          );
        }
      }
    });

    test('magic pubspec.yaml and install.yaml parse as valid YAML after render',
        () {
      const yamlStubs = <String>['pubspec.yaml', 'install.yaml'];
      for (final name in yamlStubs) {
        final raw = StubLoader.load(name, searchPaths: <String>[magicDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        expect(
          () => loadYaml(rendered),
          returnsNormally,
          reason: 'magic/$name.stub did not round-trip into valid YAML',
        );
      }
    });

    test('every magic Dart stub passes a smoke check after rendering', () {
      const dartStubs = <String>[
        'cli.dart',
        'runtime.dart',
        'install_command.dart',
        'uninstall_command.dart',
        'install_command_test.dart',
        'config_stub.dart',
        'service_provider.dart',
      ];

      final declarationAnchors = <RegExp>[
        RegExp(r'^class\s+\w+', multiLine: true),
        RegExp(r'^void\s+main\b', multiLine: true),
        RegExp(r'^library;?', multiLine: true),
        RegExp(r'^import\s+', multiLine: true),
        RegExp(r'^export\s+', multiLine: true),
      ];

      for (final name in dartStubs) {
        final raw = StubLoader.load(name, searchPaths: <String>[magicDir]);
        final rendered = StubLoader.replace(raw, _sampleReplacements());

        final hasAnchor =
            declarationAnchors.any((anchor) => anchor.hasMatch(rendered));
        expect(
          hasAnchor,
          isTrue,
          reason:
              'magic/$name.stub rendered without a top-level Dart construct',
        );
      }
    });

    test(
        'install.yaml.stub preserves install-time tokens after scaffold render',
        () {
      // The manifest renderer (ManifestInstaller) resolves
      // `{{ prompts.configPath }}` at install time. The scaffolder MUST NOT
      // touch that token — its replacement map only knows the six scaffold
      // keys, so any `{{ <unknown> }}` survives by design.
      // `configFilePath` is a YAML key (not a placeholder), so it appears as
      // plain text in the rendered output.
      final raw =
          StubLoader.load('install.yaml', searchPaths: <String>[magicDir]);
      final rendered = StubLoader.replace(raw, _sampleReplacements());

      expect(rendered, contains('{{ prompts.configPath }}'));
      expect(rendered, contains('configFilePath'));
    });

    test('install.yaml.stub publish key renders without double .stub suffix',
        () {
      // Change B regression: the publish map key previously rendered as
      // `install/magic_logger_config.dart.stub` because the scaffold was
      // appending `.stub` to the template token. The fix in install.yaml.stub
      // removed the erroneous suffix so only `install/magic_logger_config.dart`
      // reaches the installer at runtime.
      final raw =
          StubLoader.load('install.yaml', searchPaths: <String>[magicDir]);
      final rendered = StubLoader.replace(raw, _sampleReplacements());
      final yaml = loadYaml(rendered) as YamlMap;
      final publishKeys =
          (yaml['publish'] as YamlMap).keys.cast<String>().toList();

      expect(
        publishKeys.any((k) => k.endsWith('.stub.stub')),
        isFalse,
        reason: 'publish keys must not carry a double .stub suffix',
      );
      expect(
        publishKeys,
        contains('install/magic_logger_config.dart'),
        reason: 'expected publish key without any .stub suffix',
      );
    });

    test(
        'install_command.dart.stub stubName arg references stubName without .stub suffix',
        () {
      // Change B regression: the publishConfig call previously passed
      // `stubName: 'install/magic_logger_config.dart.stub'`, which caused the
      // installer to look for a file that did not exist. The fix removed the
      // trailing `.stub` from the template literal.
      final raw = StubLoader.load(
        'install_command.dart',
        searchPaths: <String>[magicDir],
      );
      final rendered = StubLoader.replace(raw, _sampleReplacements());

      expect(
        rendered,
        contains("stubName: 'install/magic_logger_config.dart'"),
        reason: 'stubName must not carry a .stub suffix in the rendered source',
      );
      expect(
        rendered,
        isNot(contains("stubName: 'install/magic_logger_config.dart.stub'")),
        reason: 'double .stub suffix must not appear in the rendered source',
      );
    });

    test(
        'magic pubspec.yaml contains both artisanPath and magicPath after render',
        () {
      final raw =
          StubLoader.load('pubspec.yaml', searchPaths: <String>[magicDir]);
      final rendered = StubLoader.replace(raw, _sampleReplacements());

      // Both path: entries must be resolved.
      expect(rendered, isNot(contains('{{ artisanPath }}')));
      expect(rendered, isNot(contains('{{ magicPath }}')));
      expect(rendered, contains('../fluttersdk_artisan'));
      expect(rendered, contains('../magic'));
    });

    test(
        'magic runtime.dart.stub re-exports the ServiceProvider for ManifestInstaller resolution',
        () {
      // Change C: magic/runtime.dart.stub must export the generated
      // ServiceProvider so that `package:magic_logger/magic_logger.dart`
      // surfaces `MagicLoggerServiceProvider` for `ManifestInstaller` to
      // resolve via `installer.injectProvider(magic.provider!)`.
      // If the export line were absent (or still using the generic template),
      // the installer would fail to locate the symbol at runtime.
      final raw =
          StubLoader.load('runtime.dart', searchPaths: <String>[magicDir]);
      final rendered = StubLoader.replace(raw, _sampleReplacements());

      expect(
        rendered,
        contains("export 'src/magic_logger_service_provider.dart';"),
        reason: 'magic/runtime.dart.stub must re-export the ServiceProvider so '
            'ManifestInstaller can resolve it via the package barrel',
      );
    });
  });
}
