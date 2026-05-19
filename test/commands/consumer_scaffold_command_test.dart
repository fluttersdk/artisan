import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_artisan/src/commands/consumer_scaffold_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Seeds [root] with the minimum pubspec.yaml needed for the scaffold to
/// run: a `name:` line + a `dependencies:` block the dep-injection step
/// can target. Returns the path for inline assertions.
String _seedPubspec(String root, {required String name}) {
  final pubspec = '''
name: $name
description: A test project.

environment:
  sdk: ^3.4.0

dependencies:
  flutter:
    sdk: flutter
''';
  final path = p.join(root, 'pubspec.yaml');
  File(path).writeAsStringSync(pubspec);
  return path;
}

/// Builds a default [ArtisanContext] with a [BufferedOutput] suitable for
/// inspecting command output in assertions.
ArtisanContext _ctx() {
  return ArtisanContext.bare(
    MapInput(const <String, dynamic>{}),
    BufferedOutput(),
  );
}

void main() {
  group('ConsumerScaffoldCommand metadata', () {
    final cmd = ConsumerScaffoldCommand();

    test('name is consumer:scaffold', () {
      expect(cmd.name, 'consumer:scaffold');
    });

    test('boot is CommandBoot.none', () {
      expect(cmd.boot, CommandBoot.none);
    });

    test('description mentions the three canonical files', () {
      expect(cmd.description, contains('bin/artisan.dart'));
      expect(cmd.description, contains('_plugins.g.dart'));
      expect(cmd.description, contains('_index.g.dart'));
    });
  });

  group('ConsumerScaffoldCommand.scaffoldInto', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('consumer_scaffold_');
      _seedPubspec(tempRoot.path, name: 'example');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('writes the three canonical files into the consumer root', () async {
      final result = await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );
      expect(result, 0);

      expect(
        File(p.join(tempRoot.path, 'bin', 'artisan.dart')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(tempRoot.path, 'lib', 'app', '_plugins.g.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(tempRoot.path, 'lib', 'app', 'commands', '_index.g.dart'),
        ).existsSync(),
        isTrue,
      );
    });

    test('bin/artisan.dart uses package: imports (no relative lib path)',
        () async {
      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );

      final binContent = File(
        p.join(tempRoot.path, 'bin', 'artisan.dart'),
      ).readAsStringSync();

      // The relative-lib import is the lint violation we are fixing.
      expect(
        binContent.contains("'../lib/app/_plugins.g.dart'"),
        isFalse,
        reason: 'bin/artisan.dart must not use relative imports into lib/',
      );
      // Both consumer barrels are imported via package: form keyed by the
      // consumer name read from pubspec.yaml.
      expect(
        binContent.contains("'package:example/app/_plugins.g.dart'"),
        isTrue,
      );
      expect(
        binContent.contains("'package:example/app/commands/_index.g.dart'"),
        isTrue,
      );
    });

    test('adds fluttersdk_artisan to consumer pubspec dependencies', () async {
      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );

      final pubspecContent = File(
        p.join(tempRoot.path, 'pubspec.yaml'),
      ).readAsStringSync();

      // The dep must land under dependencies: so the codegen barrels can
      // import package:fluttersdk_artisan/artisan.dart without tripping
      // the depend_on_referenced_packages lint.
      expect(pubspecContent.contains('fluttersdk_artisan'), isTrue);
    });

    test('pubspec dep injection is idempotent across re-runs', () async {
      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );
      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );

      final pubspecContent = File(
        p.join(tempRoot.path, 'pubspec.yaml'),
      ).readAsStringSync();

      // RegExp counts confirm exactly one fluttersdk_artisan declaration
      // after two scaffold runs (replace-by-name, never duplicate).
      expect(
        RegExp(r'^\s*fluttersdk_artisan:', multiLine: true)
            .allMatches(pubspecContent)
            .length,
        1,
      );
    });

    test('returns 1 when pubspec.yaml has no name field', () async {
      // Overwrite the seeded pubspec with a name-less variant.
      File(p.join(tempRoot.path, 'pubspec.yaml')).writeAsStringSync(
        'description: Nameless project.\n',
      );

      final result = await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );
      expect(result, 1);
    });

    test('skip-when-exists honors idempotency on the three file writes',
        () async {
      // First run lands the three files.
      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );

      // Sentinel-stamp bin/artisan.dart so we can detect a re-write.
      final binPath = p.join(tempRoot.path, 'bin', 'artisan.dart');
      const sentinel = '// SENTINEL: do not overwrite\n';
      File(binPath).writeAsStringSync(
        sentinel + File(binPath).readAsStringSync(),
      );

      // Second run with force=false must preserve the sentinel.
      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );

      expect(File(binPath).readAsStringSync().startsWith(sentinel), isTrue);
    });

    test(
      'injects fluttersdk_artisan as path dep when package_config.json '
      'resolves it locally',
      () async {
        // Seed .dart_tool/package_config.json so the scaffolder's path
        // resolver finds fluttersdk_artisan at a known relative location
        // (mirrors what `flutter pub get` writes in a monorepo workflow).
        final configDir = Directory(p.join(tempRoot.path, '.dart_tool'));
        configDir.createSync(recursive: true);
        File(p.join(configDir.path, 'package_config.json')).writeAsStringSync(
          '''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "fluttersdk_artisan",
      "rootUri": "../../../fluttersdk_artisan",
      "packageUri": "lib/",
      "languageVersion": "3.4"
    }
  ]
}
''',
        );

        await ConsumerScaffoldCommand.scaffoldInto(
          root: tempRoot.path,
          force: false,
          ctx: _ctx(),
        );

        final pubspecContent = File(
          p.join(tempRoot.path, 'pubspec.yaml'),
        ).readAsStringSync();

        // Expect the path-dep form, NOT the version-constraint form,
        // because the path is resolvable. The rootUri `../../../fluttersdk_artisan`
        // is relative to `.dart_tool/`; rebased onto the consumer root it
        // becomes `../../fluttersdk_artisan`.
        expect(
          pubspecContent.contains('fluttersdk_artisan:'),
          isTrue,
        );
        expect(
          pubspecContent.contains('path: ../../fluttersdk_artisan'),
          isTrue,
          reason: 'expected path-dep form when package_config resolves locally',
        );
        // Guard the regression: the prior naive impl wrote `any`, which
        // forces a pub.dev lookup and fails in monorepo dev workflows.
        expect(
          RegExp(r'fluttersdk_artisan:\s*any', multiLine: true)
              .hasMatch(pubspecContent),
          isFalse,
        );
      },
    );

    test('force=true overwrites all three files', () async {
      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: false,
        ctx: _ctx(),
      );

      final binPath = p.join(tempRoot.path, 'bin', 'artisan.dart');
      const sentinel = '// SENTINEL: must be overwritten\n';
      File(binPath).writeAsStringSync(
        sentinel + File(binPath).readAsStringSync(),
      );

      await ConsumerScaffoldCommand.scaffoldInto(
        root: tempRoot.path,
        force: true,
        ctx: _ctx(),
      );

      expect(File(binPath).readAsStringSync().startsWith(sentinel), isFalse);
    });
  });
}
