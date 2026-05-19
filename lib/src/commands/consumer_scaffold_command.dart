import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../helpers/config_editor.dart';
import '../helpers/file_helper.dart';
import '../stubs/stub_loader.dart';

/// `consumer:scaffold` — write the canonical native Flutter consumer
/// wrapper (`bin/artisan.dart` + `lib/app/_plugins.g.dart` + initial
/// `lib/app/commands/_index.g.dart`) into the current project so
/// `plugin:install`, `plugins:refresh`, `make:command`, and the dev-loop
/// commands all integrate without manual bin edits.
///
/// Idempotent: skips files that already exist; pass `--force` to
/// overwrite.
///
/// Magic-installed consumers already get an equivalent scaffold from
/// `magic:install`; this command is the Magic-less alternative for native
/// Flutter projects that consume artisan directly via
/// `fluttersdk_artisan: path:` without taking a Magic dependency.
class ConsumerScaffoldCommand extends ArtisanCommand {
  @override
  String get signature => 'consumer:scaffold '
      '{--force : Overwrite files even when they already exist}';

  @override
  String get description =>
      'Scaffold the canonical native Flutter consumer wrapper '
      '(bin/artisan.dart + lib/app/_plugins.g.dart + lib/app/commands/_index.g.dart).';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final force = ctx.input.option('force') as bool? ?? false;
    final root = FileHelper.findProjectRoot();
    return scaffoldInto(root: root, force: force, ctx: ctx);
  }

  /// Testable entry point. Writes the 3 canonical files into [root] +
  /// ensures `fluttersdk_artisan` is declared as a direct dependency in
  /// `<root>/pubspec.yaml` (the codegen barrels import from it, so a
  /// transitive resolution trips `depend_on_referenced_packages`).
  ///
  /// Idempotent across all four steps:
  /// - Each of the 3 file writes skips when the target already exists
  ///   unless [force] is true.
  /// - The pubspec dep injection is a no-op when `fluttersdk_artisan` is
  ///   already listed under `dependencies:` (via `ConfigEditor`).
  @visibleForTesting
  static Future<int> scaffoldInto({
    required String root,
    required bool force,
    required ArtisanContext ctx,
  }) async {
    final consumerName = _readConsumerName(root);
    if (consumerName == null) {
      ctx.output.error(
        'Could not read `name:` from $root/pubspec.yaml. '
        'Run `consumer:scaffold` from a Dart/Flutter project root.',
      );
      return 1;
    }

    var wrote = 0;
    var skipped = 0;

    // 1. bin/artisan.dart
    final binPath = p.join(root, 'bin', 'artisan.dart');
    if (_shouldWrite(binPath, force)) {
      final raw = StubLoader.load('consumer_artisan_bin.dart');
      final rendered = StubLoader.replace(raw, {'name': consumerName});
      FileHelper.writeFile(binPath, rendered);
      ctx.output.success('Created: $binPath');
      wrote++;
    } else {
      ctx.output.info('Skipped (exists): $binPath');
      skipped++;
    }

    // 2. lib/app/_plugins.g.dart
    final pluginsGPath = p.join(root, 'lib', 'app', '_plugins.g.dart');
    if (_shouldWrite(pluginsGPath, force)) {
      final raw = StubLoader.load('consumer_plugins_g.dart');
      FileHelper.writeFile(pluginsGPath, raw);
      ctx.output.success('Created: $pluginsGPath');
      wrote++;
    } else {
      ctx.output.info('Skipped (exists): $pluginsGPath');
      skipped++;
    }

    // 3. lib/app/commands/_index.g.dart (initial empty list)
    final indexPath = p.join(root, 'lib', 'app', 'commands', '_index.g.dart');
    if (_shouldWrite(indexPath, force)) {
      final raw = StubLoader.load('consumer_commands_index_initial.dart');
      FileHelper.writeFile(indexPath, raw);
      ctx.output.success('Created: $indexPath');
      wrote++;
    } else {
      ctx.output.info('Skipped (exists): $indexPath');
      skipped++;
    }

    // 4. pubspec dep: the codegen barrels at (2) + (3) import from
    //    `package:fluttersdk_artisan/artisan.dart`; without a direct dep
    //    in the consumer's pubspec.yaml the analyzer flags every barrel
    //    with `depend_on_referenced_packages`. Two routing modes:
    //    a. monorepo / path-dep workflow: read .dart_tool/package_config.json,
    //       find the artisan rootUri, inject as a path dep so the consumer
    //       pubspec resolves the same artisan checkout that already powers
    //       the in-flight `dart run fluttersdk_artisan` invocation. Pinning
    //       a SemVer here would force pub to fetch from pub.dev, which is
    //       a different (often unpublished) artisan in dev.
    //    b. pub.dev workflow (no package_config or artisan not yet
    //       resolved): inject `fluttersdk_artisan: any` so pub solves it
    //       transitively against whatever the parent plugin pins.
    //    ConfigEditor is idempotent in both branches.
    final pubspecPath = p.join(root, 'pubspec.yaml');
    final relativeArtisan = _resolveArtisanRelativePath(root);
    if (relativeArtisan != null) {
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'fluttersdk_artisan',
        path: relativeArtisan,
      );
    } else {
      ConfigEditor.addDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'fluttersdk_artisan',
        version: 'any',
      );
    }

    ctx.output.info(
      'Consumer scaffold complete ($wrote written, $skipped skipped). '
      'Next: add plugins via `plugin:install <name>` or write a command '
      'with `make:command <Name>`.',
    );
    return 0;
  }

  /// Returns true when [path] does not exist OR [force] is set.
  static bool _shouldWrite(String path, bool force) {
    if (force) return true;
    return !File(path).existsSync();
  }

  /// Extracts the package name from `<root>/pubspec.yaml`. Returns null
  /// when the file is missing or has no `name:` line.
  static String? _readConsumerName(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final match = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(
      pubspec.readAsStringSync(),
    );
    return match?.group(1);
  }

  /// Resolves the on-disk path to `fluttersdk_artisan` relative to the
  /// consumer's pubspec.yaml location. Reads
  /// `<consumerRoot>/.dart_tool/package_config.json`, locates the
  /// `fluttersdk_artisan` entry, and rebases its `rootUri` (relative to
  /// `.dart_tool/`) onto [consumerRoot]. Returns null when the file is
  /// missing, malformed, or when artisan resolves to a pub-cache location
  /// (which means the consumer is on a published-pub.dev workflow and the
  /// caller should use a SemVer constraint instead of a path dep).
  static String? _resolveArtisanRelativePath(String consumerRoot) {
    final configFile = File(
      p.join(consumerRoot, '.dart_tool', 'package_config.json'),
    );
    if (!configFile.existsSync()) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(configFile.readAsStringSync());
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final packages = decoded['packages'];
    if (packages is! List) return null;

    for (final entry in packages) {
      if (entry is! Map) continue;
      if (entry['name'] != 'fluttersdk_artisan') continue;
      final rootUri = entry['rootUri'];
      if (rootUri is! String) return null;
      // pub-cache resolutions start with `file://` absolute paths to the
      // hosted-cache layout; we only want path-dep workflows here.
      if (rootUri.startsWith('file://')) return null;
      if (p.isAbsolute(rootUri)) return null;
      // rootUri is relative to .dart_tool/ inside the consumer; rebase to
      // be relative to the consumer's pubspec.yaml location instead.
      final absolute = p.normalize(
        p.join(consumerRoot, '.dart_tool', rootUri),
      );
      final relativeToConsumer = p.relative(absolute, from: consumerRoot);
      return relativeToConsumer;
    }
    return null;
  }
}
