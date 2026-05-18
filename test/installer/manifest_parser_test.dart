import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

const _minimalYaml = '''
plugin_name: example_plugin

publish:
  install/example_config.dart.stub: lib/config/example.dart

magic:
  provider: ExampleServiceProvider
''';

const _fullYaml = '''
plugin_name: example_plugin

dependencies:
  pubspec:
    intl: ^0.20.0
    crypto: ^3.0.0
  dev_pubspec:
    mocktail: ^1.0.0
  pubspec_assets:
    - assets/example/
    - assets/lang/en.json

publish:
  install/example_config.dart.stub: lib/config/example.dart
  install/example_routes.dart.stub: lib/routes/example.dart

json_merge:
  assets/lang/en.json:
    source: install/lang/en.json
    additive: true

magic:
  provider: ExampleServiceProvider
  config_factory: exampleConfig
  routes: registerExampleRoutes

native:
  android:
    permissions:
      - android.permission.INTERNET
    meta_data:
      io.flutter.embedded_views_preview: "true"
    gradle:
      plugins:
        - id: com.example.gradle.plugin
          version: "1.0.0"
      dependencies:
        - scope: implementation
          notation: "com.example:lib:1.0.0"
  ios:
    info_plist:
      NSExampleUsageDescription: "Reason shown in iOS permission dialog"
      UIBackgroundModes: ["fetch"]
    entitlements:
      com.apple.security.keychain: true
    podfile:
      platform_version: "13.0"
      pods:
        - "ExamplePod"
  macos:
    info_plist:
      NSExampleUsageDescription: "Reason shown in macOS permission dialog"
    entitlements:
      com.apple.security.network.client: true
    podfile:
      platform_version: "11.0"
      pods:
        - "ExamplePod"
  web:
    head_scripts:
      - '<script src="example.js"></script>'
    meta_tags:
      - {name: "description", content: "Example plugin metadata"}

env:
  EXAMPLE_KEY:
    default: example_value
    comment: "Example plugin runtime config"

prompts:
  - {key: configPath, type: string, default: "~/.example.conf", question: "Config file path?"}
  - {key: mode, type: choice, options: [dev, staging, prod], default: dev, question: "Deployment mode?"}
  - {key: enableFeature, type: bool, default: false, question: "Enable optional feature?"}

placeholders:
  configFilePath: "{{ prompts.configPath }}"
  runtimeMode: "{{ prompts.mode }}"

post_install:
  run:
    - cmd: dart
      args: [format, lib/config/example.dart]
  ask_to_run:
    - prompt: "Run pub get now?"
      cmd: flutter
      args: [pub, get]
  message: |
    example_plugin installed.

bootstrap_command: example:install
''';

void main() {
  group('ManifestParser — parseString minimal manifest', () {
    test('parses plugin_name + publish + magic.provider', () {
      final manifest = ManifestParser.parseString(_minimalYaml);

      expect(manifest.pluginName, 'example_plugin');
      expect(manifest.publish, hasLength(1));
      expect(
        manifest.publish['install/example_config.dart.stub'],
        'lib/config/example.dart',
      );
      expect(manifest.magic.provider, 'ExampleServiceProvider');
    });

    test('defaults every missing section to empty / null', () {
      final manifest = ManifestParser.parseString(_minimalYaml);

      expect(manifest.pubspec.deps, isEmpty);
      expect(manifest.pubspec.devDeps, isEmpty);
      expect(manifest.pubspec.assets, isEmpty);
      expect(manifest.jsonMerge, isEmpty);
      expect(manifest.magic.configFactory, isNull);
      expect(manifest.magic.routes, isNull);
      expect(manifest.native.android, isNull);
      expect(manifest.native.ios, isNull);
      expect(manifest.native.macos, isNull);
      expect(manifest.native.web, isNull);
      expect(manifest.env, isEmpty);
      expect(manifest.prompts, isEmpty);
      expect(manifest.placeholders, isEmpty);
      expect(manifest.postInstall.run, isEmpty);
      expect(manifest.postInstall.askToRun, isEmpty);
      expect(manifest.postInstall.message, isNull);
      expect(manifest.bootstrapCommand, isNull);
    });
  });

  group('ManifestParser — parseString full manifest', () {
    late InstallManifest manifest;

    setUp(() {
      manifest = ManifestParser.parseString(_fullYaml);
    });

    test('parses pubspec dependencies + dev + assets', () {
      expect(manifest.pubspec.deps, {
        'intl': '^0.20.0',
        'crypto': '^3.0.0',
      });
      expect(manifest.pubspec.devDeps, {
        'mocktail': '^1.0.0',
      });
      expect(manifest.pubspec.assets, [
        'assets/example/',
        'assets/lang/en.json',
      ]);
    });

    test('parses publish map preserving insertion order', () {
      expect(manifest.publish, {
        'install/example_config.dart.stub': 'lib/config/example.dart',
        'install/example_routes.dart.stub': 'lib/routes/example.dart',
      });
    });

    test('parses json_merge with additive default', () {
      final spec = manifest.jsonMerge['assets/lang/en.json'];

      expect(spec, isNotNull);
      expect(spec!.source, 'install/lang/en.json');
      expect(spec.additive, isTrue);
    });

    test('parses magic block with all three slots populated', () {
      expect(manifest.magic.provider, 'ExampleServiceProvider');
      expect(manifest.magic.configFactory, 'exampleConfig');
      expect(manifest.magic.routes, 'registerExampleRoutes');
    });

    test('parses native.android permissions + meta + gradle', () {
      final android = manifest.native.android!;

      expect(android.permissions, ['android.permission.INTERNET']);
      expect(android.metaData, {
        'io.flutter.embedded_views_preview': 'true',
      });
      expect(android.gradle, isNotNull);
      expect(android.gradle!.plugins, hasLength(1));
      expect(android.gradle!.plugins.single.id, 'com.example.gradle.plugin');
      expect(android.gradle!.plugins.single.version, '1.0.0');
      expect(android.gradle!.deps, hasLength(1));
      expect(android.gradle!.deps.single.scope, 'implementation');
      expect(android.gradle!.deps.single.notation, 'com.example:lib:1.0.0');
    });

    test('parses native.ios + macos info_plist / entitlements / podfile', () {
      final ios = manifest.native.ios!;

      expect(ios.infoPlist['NSExampleUsageDescription'],
          'Reason shown in iOS permission dialog');
      expect(ios.infoPlist['UIBackgroundModes'], isA<List<dynamic>>());
      expect(ios.entitlements['com.apple.security.keychain'], true);
      expect(ios.podfile, isNotNull);
      expect(ios.podfile!.platformVersion, '13.0');
      expect(ios.podfile!.pods, ['ExamplePod']);

      final macos = manifest.native.macos!;
      expect(macos.entitlements['com.apple.security.network.client'], true);
      expect(macos.podfile!.platformVersion, '11.0');
    });

    test('parses native.web head_scripts + meta_tags', () {
      final web = manifest.native.web!;

      expect(web.headScripts, ['<script src="example.js"></script>']);
      expect(web.metaTags, hasLength(1));
      expect(web.metaTags.single, {
        'name': 'description',
        'content': 'Example plugin metadata',
      });
    });

    test('parses env vars with default + comment', () {
      final spec = manifest.env['EXAMPLE_KEY'];

      expect(spec, isNotNull);
      expect(spec!.defaultValue, 'example_value');
      expect(spec.comment, 'Example plugin runtime config');
    });

    test('parses prompts (string / choice / bool)', () {
      expect(manifest.prompts, hasLength(3));

      final first = manifest.prompts[0];
      expect(first.key, 'configPath');
      expect(first.type, 'string');
      expect(first.defaultValue, '~/.example.conf');

      final choice = manifest.prompts[1];
      expect(choice.type, 'choice');
      expect(choice.options, ['dev', 'staging', 'prod']);
      expect(choice.defaultValue, 'dev');

      final boolPrompt = manifest.prompts[2];
      expect(boolPrompt.type, 'bool');
      expect(boolPrompt.defaultValue, 'false');
    });

    test('parses placeholders as raw template strings', () {
      expect(manifest.placeholders, {
        'configFilePath': '{{ prompts.configPath }}',
        'runtimeMode': '{{ prompts.mode }}',
      });
    });

    test('parses post_install run + ask_to_run + message', () {
      expect(manifest.postInstall.run, hasLength(1));
      expect(manifest.postInstall.run.single.cmd, 'dart');
      expect(manifest.postInstall.run.single.args,
          ['format', 'lib/config/example.dart']);

      expect(manifest.postInstall.askToRun, hasLength(1));
      expect(manifest.postInstall.askToRun.single.prompt, 'Run pub get now?');
      expect(manifest.postInstall.askToRun.single.cmd, 'flutter');
      expect(manifest.postInstall.askToRun.single.args, ['pub', 'get']);

      expect(
          manifest.postInstall.message, contains('example_plugin installed'));
    });

    test('parses bootstrap_command', () {
      expect(manifest.bootstrapCommand, 'example:install');
    });
  });

  group('ManifestParser — validation', () {
    test('throws when plugin_name is missing', () {
      const yaml = '''
publish:
  install/x.stub: lib/x.dart
''';
      expect(
        () => ManifestParser.parseString(yaml),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.message,
            'message',
            contains('plugin_name'),
          ),
        ),
      );
    });

    test('throws when plugin_name fails the regex', () {
      const yaml = 'plugin_name: BadName\n';
      expect(
        () => ManifestParser.parseString(yaml),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.message,
            'message',
            contains('plugin_name'),
          ),
        ),
      );
    });

    test('throws when prompt keys collide', () {
      const yaml = '''
plugin_name: example_plugin
prompts:
  - {key: path, type: string, question: "First?"}
  - {key: path, type: string, question: "Second?"}
''';
      expect(
        () => ManifestParser.parseString(yaml),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.message,
            'message',
            contains('Duplicate prompt key'),
          ),
        ),
      );
    });

    test('throws when a placeholder references an unknown prompt key', () {
      const yaml = '''
plugin_name: example_plugin
prompts:
  - {key: configPath, type: string, question: "Where?"}
placeholders:
  configFilePath: "{{ prompts.unknownKey }}"
''';
      expect(
        () => ManifestParser.parseString(yaml),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.message,
            'message',
            contains('unknownKey'),
          ),
        ),
      );
    });

    test('throws when magic.provider violates the PascalCase regex', () {
      const yaml = '''
plugin_name: example_plugin
magic:
  provider: lowercaseProvider
''';
      expect(
        () => ManifestParser.parseString(yaml),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.message,
            'message',
            contains('provider'),
          ),
        ),
      );
    });

    test('accepts placeholder with whitespace variants in {{ prompts.X }}', () {
      const yaml = '''
plugin_name: example_plugin
prompts:
  - {key: path, type: string, question: "Where?"}
placeholders:
  a: "{{prompts.path}}"
  b: "{{ prompts.path }}"
  c: "literal"
''';
      final manifest = ManifestParser.parseString(yaml);

      expect(manifest.placeholders, {
        'a': '{{prompts.path}}',
        'b': '{{ prompts.path }}',
        'c': 'literal',
      });
    });
  });

  group('ManifestParser — error wrapping', () {
    test('invalid YAML throws FormatException wrapping the parser error', () {
      const broken = 'plugin_name: [unterminated';

      expect(
        () => ManifestParser.parseString(broken),
        throwsA(isA<FormatException>()),
      );
    });

    test('top-level scalar (not a map) throws ManifestValidationException', () {
      const yaml = '"just a string"\n';

      expect(
        () => ManifestParser.parseString(yaml),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.message,
            'message',
            contains('map'),
          ),
        ),
      );
    });
  });

  group('ManifestParser — sample fixtures parse', () {
    test('doc/samples/install.minimal.yaml parses without throwing', () {
      final manifest =
          ManifestParser.parseFile('doc/samples/install.minimal.yaml');

      expect(manifest.pluginName, 'example_plugin');
      expect(manifest.publish, hasLength(1));
      expect(manifest.magic.provider, 'ExampleServiceProvider');
    });

    test('doc/samples/install.full.yaml parses every populated section', () {
      final manifest =
          ManifestParser.parseFile('doc/samples/install.full.yaml');

      expect(manifest.pluginName, 'example_plugin');
      expect(manifest.pubspec.deps, isNotEmpty);
      expect(manifest.publish, isNotEmpty);
      expect(manifest.jsonMerge, isNotEmpty);
      expect(manifest.magic.provider, isNotNull);
      expect(manifest.native.android, isNotNull);
      expect(manifest.native.ios, isNotNull);
      expect(manifest.native.macos, isNotNull);
      expect(manifest.native.web, isNotNull);
      expect(manifest.env, isNotEmpty);
      expect(manifest.prompts, isNotEmpty);
      expect(manifest.placeholders, isNotEmpty);
      expect(manifest.postInstall.run, isNotEmpty);
      expect(manifest.postInstall.askToRun, isNotEmpty);
      expect(manifest.bootstrapCommand, 'example:install');
    });
  });
}
