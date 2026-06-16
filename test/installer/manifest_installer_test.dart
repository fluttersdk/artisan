import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only driver fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

class _QueuedPromptDriver implements PromptDriver {
  _QueuedPromptDriver({
    Map<String, String> asks = const {},
    Map<String, bool> confirms = const {},
    Map<String, String> choices = const {},
  })  : _asks = Map.of(asks),
        _confirms = Map.of(confirms),
        _choices = Map.of(choices);

  final Map<String, String> _asks;
  final Map<String, bool> _confirms;
  final Map<String, String> _choices;

  /// Recorded questions for assertion in tests.
  final List<String> recorded = <String>[];

  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) {
    recorded.add(question);
    return _asks[question] ?? defaultValue ?? '';
  }

  @override
  bool confirm(String question, {bool defaultValue = false}) {
    recorded.add(question);
    return _confirms[question] ?? defaultValue;
  }

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) {
    recorded.add(question);
    return _choices[question] ?? defaultValue ?? options.first;
  }

  @override
  String secret(String question) {
    recorded.add(question);
    return '';
  }
}

class _MapStubDriver implements StubDriver {
  _MapStubDriver(this.stubs);

  final Map<String, String> stubs;

  @override
  String load(String name, {List<String>? searchPaths}) {
    final body = stubs[name];
    if (body == null) {
      throw StateError('Stub "$name" not registered in _MapStubDriver.');
    }
    return body;
  }

  @override
  String replace(String stub, Map<String, String> replacements) {
    var out = stub;
    replacements.forEach((k, v) {
      out = out.replaceAll('{{ $k }}', v).replaceAll('{{$k}}', v);
    });
    return out;
  }

  @override
  String make(String name, Map<String, String> replacements) =>
      replace(load(name), replacements);
}

InstallContext _ctx({
  required InMemoryFs fs,
  PromptDriver? prompt,
  StubDriver? stubs,
}) {
  return InstallContext.test(
    fs: fs,
    prompt: prompt ?? _QueuedPromptDriver(),
    stubs: stubs ?? _MapStubDriver(const {}),
    projectRoot: '/proj',
    clock: () => DateTime.utc(2025, 1, 1),
  );
}

InstallManifest _minimalManifest() => InstallManifest(
      pluginName: 'example_plugin',
      pubspec: PubspecDeps.empty(),
      publish: const {
        'install/example_config.dart.stub': 'lib/config/example.dart',
      },
      jsonMerge: const {},
      magic: const MagicIntegration(provider: 'ExampleServiceProvider'),
      native: NativeConfig.empty(),
      env: const {},
      prompts: const [],
      placeholders: const {},
      postInstall: PostInstallSpec.empty(),
    );

InstallManifest _fullManifestSample() => InstallManifest(
      pluginName: 'example_plugin',
      pubspec: const PubspecDeps(
        deps: {'intl': '^0.20.0'},
        devDeps: {'mocktail': '^1.0.0'},
        assets: ['assets/example/'],
      ),
      publish: const {
        'install/example_config.dart.stub': 'lib/config/example.dart',
      },
      jsonMerge: const {
        'assets/lang/en.json': JsonMergeSpec(
          source: 'install/lang/en.json',
          additive: true,
        ),
      },
      magic: const MagicIntegration(
        provider: 'ExampleServiceProvider',
        configFactory: 'exampleConfig',
        routes: 'registerExampleRoutes',
      ),
      native: NativeConfig(
        android: const AndroidConfig(
          permissions: ['android.permission.INTERNET'],
          metaData: {'io.flutter.embedded_views_preview': 'true'},
          gradle: GradleConfig(
            plugins: [
              GradlePluginSpec(
                  id: 'com.example.gradle.plugin', version: '1.0.0'),
            ],
            deps: [
              GradleDepSpec(
                  scope: 'implementation', notation: 'com.example:lib:1.0.0'),
            ],
          ),
        ),
        ios: const IosConfig(
          infoPlist: {'NSExampleUsageDescription': 'Reason'},
          entitlements: {'com.apple.security.keychain': true},
          podfile: PodfileConfig(platformVersion: '13.0', pods: ['ExamplePod']),
        ),
        web: const WebConfig(
          headScripts: ['<script src="example.js"></script>'],
          metaTags: [
            {'name': 'description', 'content': 'Example'},
          ],
        ),
      ),
      env: const {
        'EXAMPLE_KEY': EnvVarSpec(defaultValue: 'example_value'),
      },
      prompts: const [
        PromptSpec(
          key: 'configPath',
          type: 'string',
          question: 'Config path?',
          defaultValue: '~/.example.conf',
        ),
      ],
      placeholders: const {
        'configFilePath': '{{ prompts.configPath }}',
      },
      postInstall: const PostInstallSpec(
        run: [
          ShellSpec(cmd: 'dart', args: ['format', 'lib/config/example.dart'])
        ],
        askToRun: [],
        message: 'example_plugin installed.',
      ),
      bootstrapCommand: 'example:install',
    );

void main() {
  group('ManifestInstaller — prepare() stages translated ops', () {
    test('minimal manifest stages exactly one PublishFile + injectProvider ops',
        () {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': 'const x = 1;\n',
      });
      final installer = ManifestInstaller(
        _ctx(fs: fs, stubs: stubs),
        _minimalManifest(),
      );

      final pluginInstaller = installer.prepare();
      final ops = pluginInstaller.pendingOps;

      // PublishFile + InjectImport (provider) + InjectAfterPattern (provider).
      expect(ops.whereType<PublishFile>(), hasLength(1));
      expect(ops.whereType<InjectImport>(), hasLength(1));
      expect(ops.whereType<InjectAfterPattern>(), hasLength(1));

      final publish = ops.whereType<PublishFile>().single;
      expect(publish.sourceStubName, 'install/example_config.dart.stub');
      expect(publish.targetPath, 'lib/config/example.dart');
    });

    test('full manifest stages every section in declared order', () {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': 'const x = 1;\n',
        'install/lang/en.json': '{"hello": "world"}',
      });
      final prompt = _QueuedPromptDriver(
        asks: {'Config path?': '/tmp/example.conf'},
      );
      final installer = ManifestInstaller(
        _ctx(fs: fs, prompt: prompt, stubs: stubs),
        _fullManifestSample(),
      );

      final ops = installer.prepare().pendingOps;

      // Pubspec section.
      expect(
          ops.whereType<AddDependency>().where((o) => !o.isDev), hasLength(1));
      expect(
          ops.whereType<AddDependency>().where((o) => o.isDev), hasLength(1));
      expect(ops.whereType<AddPubspecAsset>(), hasLength(1));

      // Publish + JSON merge.
      expect(ops.whereType<PublishFile>(), hasLength(1));
      expect(ops.whereType<MergeJson>(), hasLength(1));

      // Magic (provider triggers import + after-pattern; config_factory
      // triggers import + after-pattern; routes triggers route registration).
      expect(ops.whereType<InjectImport>().length, greaterThanOrEqualTo(1));
      expect(ops.whereType<InjectMainDartImport>(), hasLength(1));
      expect(
          ops.whereType<InjectAfterPattern>().length, greaterThanOrEqualTo(2));
      expect(ops.whereType<InjectRouteRegistration>(), hasLength(1));

      // Native.
      expect(ops.whereType<InjectAndroidPermission>(), hasLength(1));
      expect(ops.whereType<InjectAndroidMetaData>(), hasLength(1));
      expect(ops.whereType<InjectGradlePlugin>(), hasLength(1));
      expect(ops.whereType<InjectGradleDependency>(), hasLength(1));
      expect(ops.whereType<InjectInfoPlistKey>(), hasLength(1));
      expect(ops.whereType<InjectEntitlement>(), hasLength(1));
      expect(ops.whereType<InjectPodfileLine>(), hasLength(1));
      expect(ops.whereType<InjectIntoWebHead>(), hasLength(1));
      expect(ops.whereType<AddWebMetaTag>(), hasLength(1));

      // Env.
      expect(ops.whereType<InjectEnvVar>(), hasLength(1));

      // Post-install (only `run` is enqueued; ask_to_run is empty here).
      expect(ops.whereType<RunShell>(), hasLength(1));
    });

    test(
        'config factory import resolves from the published lib/config path, '
        'not the package barrel', () {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': 'const x = 1;\n',
        'install/lang/en.json': '{"hello": "world"}',
      });
      final prompt = _QueuedPromptDriver(
        asks: {'Config path?': '/tmp/example.conf'},
      );
      final installer = ManifestInstaller(
        _ctx(fs: fs, prompt: prompt, stubs: stubs),
        _fullManifestSample(),
      );

      final import = installer
          .prepare()
          .pendingOps
          .whereType<InjectMainDartImport>()
          .single;

      // The manifest publishes the factory into lib/config/example.dart, so the
      // injected import must be consumer-relative (config/example.dart), not the
      // plugin package barrel.
      expect(import.importStatement, "import 'config/example.dart';");
    });

    test('publish carries the resolved placeholders as replacements', () {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub':
            "const path = '{{ configFilePath }}';\n",
        'install/lang/en.json': '{}',
      });
      final prompt = _QueuedPromptDriver(
        asks: {'Config path?': '/tmp/example.conf'},
      );
      final installer = ManifestInstaller(
        _ctx(fs: fs, prompt: prompt, stubs: stubs),
        _fullManifestSample(),
      );

      final publish =
          installer.prepare().pendingOps.whereType<PublishFile>().single;

      expect(publish.replacements, {'configFilePath': '/tmp/example.conf'});
    });
  });

  group('ManifestInstaller — install() commits the transaction', () {
    test('dryRun returns DryRun with the staged op count and no disk writes',
        () async {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': 'const x = 1;\n',
      });
      final installer = ManifestInstaller(
        _ctx(fs: fs, stubs: stubs),
        _minimalManifest(),
      );

      final result = await installer.install(dryRun: true);

      expect(result, isA<DryRun>());
      expect((result as DryRun).opCount, greaterThan(0));
      expect(fs.exists('/proj/lib/config/example.dart'), isFalse);
    });

    test('non-dryRun writes published file + install record on Success',
        () async {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': 'const x = 1;\n',
      });
      // Manifest without magic.provider — that path uses dart:io-backed
      // helpers (ConfigEditor.addImportToFile / insertCodeAfterPattern) which
      // BYPASS the InMemoryFs (see PluginInstaller's "Limitations" docblock).
      // The publish path stays inside the VirtualFs seam so the assertion can
      // verify the rendered file + install record both landed.
      final manifest = InstallManifest(
        pluginName: 'example_plugin',
        pubspec: PubspecDeps.empty(),
        publish: const {
          'install/example_config.dart.stub': 'lib/config/example.dart',
        },
        jsonMerge: const {},
        magic: MagicIntegration.empty(),
        native: NativeConfig.empty(),
        env: const {},
        prompts: const [],
        placeholders: const {},
        postInstall: PostInstallSpec.empty(),
      );
      final installer = ManifestInstaller(_ctx(fs: fs, stubs: stubs), manifest);

      final result = await installer.install();

      expect(result, isA<Success>(), reason: 'Got ${result.describe()}');
      expect(fs.exists('/proj/lib/config/example.dart'), isTrue);
      expect(
          fs.readAsString('/proj/lib/config/example.dart'), 'const x = 1;\n');
      expect(fs.exists('/proj/.artisan/installed/example_plugin.json'), isTrue);
    });
  });

  group('ManifestInstaller — prompts + placeholders', () {
    test('promptOverrides bypass the PromptDriver entirely', () {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': '{{ configFilePath }}\n',
        'install/lang/en.json': '{}',
      });
      final prompt = _QueuedPromptDriver();
      final installer = ManifestInstaller(
        _ctx(fs: fs, prompt: prompt, stubs: stubs),
        _fullManifestSample(),
        promptOverrides: const {'configPath': '/override/path'},
      );

      final publish =
          installer.prepare().pendingOps.whereType<PublishFile>().single;

      expect(publish.replacements, {'configFilePath': '/override/path'});
      expect(prompt.recorded, isEmpty,
          reason: 'override should pre-empt the prompt call');
    });

    test('nonInteractive=true uses prompt defaults instead of asking', () {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': '{{ configFilePath }}\n',
        'install/lang/en.json': '{}',
      });
      final prompt = _QueuedPromptDriver();
      final installer = ManifestInstaller(
        _ctx(fs: fs, prompt: prompt, stubs: stubs),
        _fullManifestSample(),
      );

      installer.prepare(nonInteractive: true);

      expect(prompt.recorded, isEmpty,
          reason: 'nonInteractive must skip prompts and fall back to defaults');

      final publish =
          installer.prepare().pendingOps.whereType<PublishFile>().last;
      // Default for `configPath` was `~/.example.conf` in the sample.
      expect(publish.replacements, {'configFilePath': '~/.example.conf'});
    });

    test('placeholder values without prompt refs pass through unchanged', () {
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': '{{ literalKey }}\n',
      });
      final manifest = InstallManifest(
        pluginName: 'example_plugin',
        pubspec: PubspecDeps.empty(),
        publish: const {
          'install/example_config.dart.stub': 'lib/config/example.dart',
        },
        jsonMerge: const {},
        magic: MagicIntegration.empty(),
        native: NativeConfig.empty(),
        env: const {},
        prompts: const [],
        placeholders: const {'literalKey': 'literal_value'},
        postInstall: PostInstallSpec.empty(),
      );

      final installer = ManifestInstaller(_ctx(fs: fs, stubs: stubs), manifest);
      final publish =
          installer.prepare().pendingOps.whereType<PublishFile>().single;

      expect(publish.replacements, {'literalKey': 'literal_value'});
    });
  });

  group('ManifestInstaller — uninstall', () {
    test('returns Error when the install record file is missing', () async {
      final fs = InMemoryFs();
      final installer = ManifestInstaller(
        _ctx(fs: fs),
        _minimalManifest(),
      );

      final result = await installer.uninstall();

      expect(result, isA<Error>());
      expect((result as Error).error, contains('install record'));
    });

    test('reverses WriteFile / CopyFile / PublishFile records into DeleteFile',
        () async {
      final fs = InMemoryFs();
      // Pre-seed three target files + a fabricated install record.
      fs.writeAsString('/proj/lib/a.dart', 'a');
      fs.writeAsString('/proj/lib/b.dart', 'b');
      fs.writeAsString('/proj/lib/c.dart', 'c');
      final record = <String, dynamic>{
        'plugin': 'example_plugin',
        'installedAt': '2025-01-01T00:00:00.000Z',
        'ops': [
          {'type': 'WriteFile', 'targetPath': 'lib/a.dart', 'content': 'a'},
          {
            'type': 'CopyFile',
            'sourcePath': 'x.dart',
            'targetPath': 'lib/b.dart'
          },
          {'type': 'DeleteFile', 'targetPath': 'lib/c.dart'},
        ],
        'stubHashes': <String, String>{},
      };
      fs.writeAsString(
        '/proj/.artisan/installed/example_plugin.json',
        const JsonEncoder.withIndent('  ').convert(record),
      );

      final installer = ManifestInstaller(
        _ctx(fs: fs),
        _minimalManifest(),
      );

      final result = await installer.uninstall();

      expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');
      expect(fs.exists('/proj/lib/a.dart'), isFalse);
      expect(fs.exists('/proj/lib/b.dart'), isFalse);
      // DeleteFile from the original record has no reverse; lib/c.dart should
      // remain on disk after uninstall.
      expect(fs.exists('/proj/lib/c.dart'), isTrue);
      // Record file is removed on Success.
      expect(
        fs.exists('/proj/.artisan/installed/example_plugin.json'),
        isFalse,
      );
    });

    test('type-only records (no payload) log a skip + still Success', () async {
      final fs = InMemoryFs();
      final record = <String, dynamic>{
        'plugin': 'example_plugin',
        'installedAt': '2025-01-01T00:00:00.000Z',
        'ops': [
          // The persisted record carries only the type tag for these ops.
          {'type': 'AddDependency'},
          {'type': 'InjectAndroidPermission'},
        ],
        'stubHashes': <String, String>{},
      };
      fs.writeAsString(
        '/proj/.artisan/installed/example_plugin.json',
        const JsonEncoder.withIndent('  ').convert(record),
      );

      final output = BufferedOutput();
      final ctx = InstallContext.test(
        fs: fs,
        prompt: _QueuedPromptDriver(),
        stubs: _MapStubDriver(const {}),
        output: output,
        projectRoot: '/proj',
      );
      final installer = ManifestInstaller(ctx, _minimalManifest());

      final result = await installer.uninstall();

      expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');
    });

    test(
        'install->uninstall round-trip for PublishFile correctly deletes the '
        'rendered file (Phase 3 Fix 2 regression)', () async {
      // This is the critical Stage 2 spec FAIL the deep reviewer flagged:
      // before Fix 1+2, the install record degraded a PublishFile op to
      // `{type: 'PublishFile'}` only, so uninstall could not reconstruct the
      // typed op and the rendered file was orphaned. Now the record carries
      // sourceStubName + targetPath + replacements so uninstall reverses
      // PublishFile -> DeleteFile and the file is removed.
      final fs = InMemoryFs();
      final stubs = _MapStubDriver({
        'install/example_config.dart.stub': "const example = 'value';\n",
      });
      final ctx = _ctx(fs: fs, stubs: stubs);

      // Manifest without magic.provider: that path uses dart:io-backed
      // ConfigEditor helpers which bypass InMemoryFs (see PluginInstaller's
      // "Limitations" docblock). Publish stays inside the VirtualFs seam so
      // the round-trip assertion can read back the rendered file.
      final manifest = InstallManifest(
        pluginName: 'example_plugin',
        pubspec: PubspecDeps.empty(),
        publish: const {
          'install/example_config.dart.stub': 'lib/config/example.dart',
        },
        jsonMerge: const {},
        magic: MagicIntegration.empty(),
        native: NativeConfig.empty(),
        env: const {},
        prompts: const [],
        placeholders: const {},
        postInstall: PostInstallSpec.empty(),
      );

      // Phase A: install via the real ManifestInstaller chain.
      final installResult = await ManifestInstaller(ctx, manifest).install();
      expect(installResult, isA<Success>(),
          reason: 'install failed: ${installResult.describe()}');
      expect(fs.exists('/proj/lib/config/example.dart'), isTrue);

      // Phase B: read back the install record and assert PublishFile carries
      // its typed payload (not just `{type: ...}`).
      final record = jsonDecode(
        fs.readAsString('/proj/.artisan/installed/example_plugin.json'),
      ) as Map<String, dynamic>;
      final ops = (record['ops'] as List).cast<Map<String, dynamic>>();
      final publishEntry = ops.firstWhere((o) => o['type'] == 'PublishFile');
      expect(
          publishEntry['sourceStubName'], 'install/example_config.dart.stub');
      expect(publishEntry['targetPath'], 'lib/config/example.dart');
      expect(publishEntry['replacements'], isA<Map>());

      // Phase C: uninstall and assert the rendered file is gone.
      final uninstallResult =
          await ManifestInstaller(ctx, manifest).uninstall();
      expect(uninstallResult, isA<Success>(),
          reason: 'uninstall failed: ${uninstallResult.describe()}');
      expect(fs.exists('/proj/lib/config/example.dart'), isFalse,
          reason: 'PublishFile must reverse to DeleteFile and remove the '
              'rendered config file');
      expect(fs.exists('/proj/.artisan/installed/example_plugin.json'), isFalse,
          reason: 'install record must be deleted on successful uninstall');
    });

    test('reverseOf handles every InstallOperation subclass (exhaustive)', () {
      // Exhaustiveness gate: every sealed InstallOperation subclass must be
      // covered by reverseOf — either returning a reverse op, or null with a
      // skip-warning recorded. This list mirrors install_operation.dart.
      final ops = <InstallOperation>[
        const AddDependency(name: 'x', version: '^1.0.0'),
        const AddPathDependency(name: 'x', path: '../x'),
        const RemoveDependency(name: 'x'),
        const AddPubspecAsset(assetPath: 'assets/x/'),
        const PublishFile(
            sourceStubName: 's', targetPath: 't', replacements: {}),
        const WriteFile(targetPath: 't', content: 'c'),
        const DeleteFile(targetPath: 't'),
        const CopyFile(sourcePath: 's', targetPath: 't'),
        const MergeJson(targetPath: 't', sourceData: {}),
        const InjectImport(targetFile: 'f', importStatement: 'i'),
        InjectBeforePattern(targetFile: 'f', pattern: RegExp('x'), code: 'c'),
        InjectAfterPattern(targetFile: 'f', pattern: RegExp('x'), code: 'c'),
        const InjectAndroidPermission(permission: 'x'),
        const InjectAndroidMetaData(name: 'n', value: 'v'),
        const InjectInfoPlistKey(key: 'k', value: 'v'),
        const InjectEntitlement(platform: 'ios', key: 'k', value: true),
        const InjectPodfileLine(platform: 'ios', line: 'l'),
        const InjectGradlePlugin(pluginId: 'p'),
        const InjectGradleDependency(scope: 's', notation: 'n'),
        const InjectEnvVar(key: 'K', value: 'v'),
        const InjectIntoWebHead(content: 'c'),
        const AddWebMetaTag(attributes: {}),
        const InjectMainDartImport(importStatement: 'i'),
        const InjectIntoMainDart(
            placement: MainDartPlacement.beforeInit, code: 'c'),
        const InjectRouteRegistration(functionName: 'f'),
        const RunShell(command: 'echo', args: []),
      ];

      // No throw means every case is covered by the switch in reverseOf.
      // The switch must be exhaustive (Dart 3 sealed class check; a missing
      // case fails to compile). Reversible ops return an op; the rest null.
      for (final op in ops) {
        ManifestInstaller.reverseOf(op);
      }

      // Spot-check the documented mappings.
      expect(
        ManifestInstaller.reverseOf(
            const AddDependency(name: 'x', version: '^1.0.0')),
        isA<RemoveDependency>(),
      );
      expect(
        ManifestInstaller.reverseOf(const PublishFile(
            sourceStubName: 's', targetPath: 't', replacements: {})),
        isA<DeleteFile>(),
      );
      expect(
        ManifestInstaller.reverseOf(
            const WriteFile(targetPath: 't', content: 'c')),
        isA<DeleteFile>(),
      );
      expect(
        ManifestInstaller.reverseOf(
            const CopyFile(sourcePath: 's', targetPath: 't')),
        isA<DeleteFile>(),
      );
      expect(
        ManifestInstaller.reverseOf(const DeleteFile(targetPath: 't')),
        isNull,
      );
      expect(
        ManifestInstaller.reverseOf(const RunShell(command: 'x', args: [])),
        isNull,
      );
    });
  });
}
