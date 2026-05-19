import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../console/string_helper.dart';
import '../helpers/file_helper.dart';
import '../installer/virtual_fs.dart';
import '../stubs/stub_loader.dart';
import 'helpers/artisan_path_resolver.dart';
import 'helpers/flutter_create_runner.dart';
import 'helpers/workspace_enroller.dart';

/// `artisan make:plugin <name>`, scaffolds a new `fluttersdk_artisan` plugin
/// skeleton under `packages/<name>/` (or a `--target` / `--path` override).
///
/// ## Pipeline
///
/// The handler runs in eight phases:
///
/// 1. Validate the snake_case [name] argument.
/// 2. Resolve the target directory (`--path` > `--target` > default
///    `<projectRoot>/packages/<name>/`).
/// 3. Spawn `flutter create --template=package` via [FlutterCreateRunner] to
///    lay down the baseline Dart package (pubspec, LICENSE, CHANGELOG,
///    `.gitignore`, `.metadata`, `lib/<name>.dart`, `test/<name>_test.dart`,
///    README, analysis_options).
/// 4. Compute the dynamic `artisanPath` (and `magicPath` in magic mode) and
///    render the generic scaffold stubs from `assets/stubs/make_plugin/generic/`,
///    overwriting `flutter create`'s pubspec.yaml, `lib/<name>.dart`,
///    `test/<name>_test.dart`, and `README.md` with our versions.
/// 5. When [isMagic] is true: render the magic-add-on stubs from
///    `assets/stubs/make_plugin/magic/` (install.yaml, install_command,
///    uninstall_command, config_stub, install_command_test) AND replace the
///    generic pubspec with the magic-flavored one that includes the magic
///    dependency.
/// 6. Detect a parent Flutter app via [WorkspaceEnroller]; when found, enroll
///    the plugin into the parent's pub workspace (adds
///    `resolution: workspace` to the plugin pubspec and a `workspace:` list
///    entry to the parent pubspec).
/// 7. Print the success banner + next-steps hint, including whether the
///    parent app's pubspec.yaml was modified.
///
/// ## Replacement variables
///
/// Every stub uses these placeholders, derived once from the [name] argument
/// and the resolved paths:
///
/// - `name`, the snake_case package name (e.g. `magic_logger`).
/// - `pascalName`, the PascalCase class root (e.g. `MagicLogger`).
/// - `commandPrefix`, the package name with the `magic_` / `fluttersdk_`
///   convention prefix stripped (e.g. `magic_logger` → `logger`). Drives the
///   default `<commandPrefix>:install` / `<commandPrefix>:uninstall` names.
/// - `bootstrapCommand`, the value of the `--bootstrap-command` option, or
///   `<commandPrefix>:install` when the option is absent.
/// - `artisanPath`, the dynamically computed relative path from the target
///   directory to the `fluttersdk_artisan` package root. Replaces the old
///   hardcoded `path: ../../` that broke for non-standard target depths.
/// - `magicPath`, the dynamically computed relative path from the target to
///   the `magic` package root. Only set in magic mode; absent in generic
///   mode so the generic pubspec stub never references magic.
///
/// ## Test injection
///
/// Three seams support deterministic tests:
///
/// - [resolveArtisanRoot] / [resolveMagicRoot] / [resolveStubDir] —
///   override in test subclasses to pin the package roots without touching
///   `Isolate.resolvePackageUri`.
/// - [FlutterCreateRunner] — pass a stub via the constructor to skip the
///   real subprocess spawn.
/// - [WorkspaceEnroller] — pass an in-memory variant via the constructor
///   to assert workspace enrollment without touching real pubspec files.
class MakePluginCommand extends ArtisanCommand {
  /// Public default constructor. Optional injection seams default to real
  /// implementations.
  ///
  /// @param flutterCreateRunner  Subprocess runner for `flutter create`.
  ///                             Defaults to a real [FlutterCreateRunner]
  ///                             that spawns the binary via `$PATH`.
  /// @param workspaceEnroller    Workspace enrollment helper. Defaults to a
  ///                             real [WorkspaceEnroller] backed by [RealFs].
  MakePluginCommand({
    FlutterCreateRunner? flutterCreateRunner,
    WorkspaceEnroller? workspaceEnroller,
  })  : _flutterCreateRunner = flutterCreateRunner ?? FlutterCreateRunner(),
        _workspaceEnroller =
            workspaceEnroller ?? WorkspaceEnroller(const RealFs());

  final FlutterCreateRunner _flutterCreateRunner;
  final WorkspaceEnroller _workspaceEnroller;

  /// Pre-compiled snake_case validator: must start with a lowercase letter and
  /// contain only `[a-z0-9_]` afterwards. Mirrors Dart's pubspec `name:`
  /// validation rule, which is the most restrictive of all consumers.
  static final RegExp _validNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

  /// Generic scaffold mapping: stub asset name → target path template under
  /// the resolved plugin root. Every plugin (generic OR magic mode) receives
  /// these six files; in magic mode the pubspec entry is replaced by the
  /// magic-flavored variant from the `magic/` stub subdirectory.
  static const List<({String stub, String target})> _genericScaffoldPlan = [
    (stub: 'pubspec.yaml', target: 'pubspec.yaml'),
    (stub: 'bin_artisan.dart', target: 'bin/{{ name }}.dart'),
    (stub: 'cli.dart', target: 'lib/cli.dart'),
    (stub: 'runtime.dart', target: 'lib/{{ name }}.dart'),
    (
      stub: 'provider.dart',
      target: 'lib/src/{{ name }}_artisan_provider.dart',
    ),
    (
      stub: 'provider_test.dart',
      target: 'test/{{ name }}_artisan_provider_test.dart',
    ),
    (stub: 'readme.md', target: 'README.md'),
  ];

  /// Magic-mode-only add-on stubs: install command DSL, manifest, config
  /// template, the install command's test scaffold, and the Magic
  /// ServiceProvider that install.yaml's `magic.provider:` field points to.
  /// Rendered from `assets/stubs/make_plugin/magic/` on top of the generic
  /// scaffold. The magic mode also overrides generic/runtime.dart (via
  /// `stubOverrides` in handle()) so the runtime barrel re-exports the
  /// ServiceProvider for ManifestInstaller's `InjectImport` op to resolve.
  static const List<({String stub, String target})> _magicScaffoldPlan = [
    (
      stub: 'install_command.dart',
      target: 'lib/src/commands/install_command.dart',
    ),
    (
      stub: 'uninstall_command.dart',
      target: 'lib/src/commands/uninstall_command.dart',
    ),
    (stub: 'install.yaml', target: 'install.yaml'),
    (
      stub: 'config_stub.dart',
      target: 'assets/stubs/install/{{ name }}_config.dart.stub',
    ),
    (
      stub: 'install_command_test.dart',
      target: 'test/cli/install_command_test.dart',
    ),
    (
      stub: 'service_provider.dart',
      target: 'lib/src/{{ name }}_service_provider.dart',
    ),
  ];

  @override
  String get signature => 'make:plugin '
      '{name : Plugin package name in snake_case} '
      '{--target= : Target directory (default: packages/<name>)} '
      '{--path= : Target directory (alias for --target, takes precedence when both set)} '
      '{--magic : Scaffold a magic-aware plugin (install.yaml + magic deps + magic-style install_command)} '
      '{--bootstrap-command= : Override bootstrap command name '
      '(default: <commandPrefix>:install)}';

  @override
  String get description =>
      'Scaffold a new fluttersdk_artisan plugin skeleton.';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Resolves the absolute path of the `fluttersdk_artisan` package root.
  /// Used by [ArtisanPathResolver] to compute the dynamic `artisanPath`
  /// placeholder and by [resolveStubDir] to locate the stub bundle.
  ///
  /// Production walks `Isolate.resolvePackageUri('package:fluttersdk_artisan/artisan.dart')`
  /// up two directories (`<root>/lib/artisan.dart` → `<root>`). Tests
  /// override to pin a deterministic path.
  ///
  /// @return Absolute path to the `fluttersdk_artisan` package root.
  /// @throws StateError when the package URI cannot be resolved.
  @visibleForTesting
  Future<String> resolveArtisanRoot() async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:fluttersdk_artisan/artisan.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') {
      throw StateError(
        'make:plugin could not resolve the fluttersdk_artisan package URI. '
        'Run from a project with `fluttersdk_artisan` listed in pubspec.yaml.',
      );
    }
    // resolved = <pkg_root>/lib/artisan.dart → walk up two for <pkg_root>.
    return p.dirname(p.dirname(resolved.toFilePath()));
  }

  /// Resolves the absolute path of the `magic` package root.
  ///
  /// Only invoked in magic mode (gated behind [isMagic]). Production walks
  /// `Isolate.resolvePackageUri('package:magic/magic.dart')` up two
  /// directories. Throws when the magic package is not resolvable so the
  /// operator gets a clear, actionable error instead of a silent fallback
  /// to a wrong path.
  ///
  /// @return Absolute path to the `magic` package root.
  /// @throws StateError when magic is not installed in the parent app.
  @visibleForTesting
  Future<String> resolveMagicRoot() async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:magic/magic.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') {
      throw StateError(
        'make:plugin --magic could not resolve the magic package URI. '
        'Run `flutter pub add magic` in the parent app first.',
      );
    }
    return p.dirname(p.dirname(resolved.toFilePath()));
  }

  /// Resolves the directory holding the `make_plugin/` stub bundle. Tests
  /// can override either this method directly or [resolveArtisanRoot] to
  /// pin the bundle location.
  ///
  /// @return Absolute path to the `make_plugin` stub bundle directory.
  @visibleForTesting
  Future<String> resolveStubDir() async {
    return p.join(await resolveArtisanRoot(), 'assets', 'stubs', 'make_plugin');
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Validate the positional name argument up-front so the rest of the
    //    handler can assume a snake_case identifier.
    final name = ctx.input.argument('name') ?? '';
    if (name.isEmpty) {
      ctx.output.error('Missing required argument: name.');
      return 1;
    }
    if (!_validNamePattern.hasMatch(name)) {
      ctx.output.error(
        'Invalid plugin name "$name": must be snake_case '
        '(lowercase letter followed by [a-z0-9_]).',
      );
      return 1;
    }

    // 2. Resolve the target plugin root: --path > --target > default.
    final targetRoot = _resolveTargetRoot(ctx, name: name);
    final magicMode = isMagic(ctx);

    // 3. Resolve the artisan package root once; reused for stub dir + path
    //    computation. Resolve magic root only in magic mode so generic-mode
    //    invocations never depend on magic being installed.
    final String artisanRoot;
    final String stubDir;
    try {
      artisanRoot = await resolveArtisanRoot();
      stubDir = await resolveStubDir();
    } on StateError catch (e) {
      ctx.output.error(e.message);
      return 1;
    }
    if (!Directory(stubDir).existsSync()) {
      ctx.output.error('Stub directory not found: $stubDir');
      return 1;
    }
    final String? magicRoot;
    if (magicMode) {
      try {
        magicRoot = await resolveMagicRoot();
      } on StateError catch (e) {
        ctx.output.error(e.message);
        return 1;
      }
    } else {
      magicRoot = null;
    }

    // 4. Build the replacement map. artisanPath is always present; magicPath
    //    is set only in magic mode (the generic pubspec stub does not
    //    reference it).
    final artisanPath = ArtisanPathResolver.computeRelative(
      artisanRoot: artisanRoot,
      targetDir: targetRoot,
    );
    final magicPath = magicRoot == null
        ? null
        : ArtisanPathResolver.computeRelative(
            artisanRoot: magicRoot,
            targetDir: targetRoot,
          );
    final replacements = _buildReplacements(
      ctx,
      name: name,
      artisanPath: artisanPath,
      magicPath: magicPath,
    );

    // 5. Spawn `flutter create --template=package` to lay down the baseline
    //    Dart package files. Our stub rendering (step 6+) overwrites the
    //    handful we care about; everything else (LICENSE, CHANGELOG,
    //    .gitignore, .metadata, analysis_options.yaml) stays untouched.
    final int flutterExit;
    try {
      flutterExit = await _flutterCreateRunner.create(
        packageName: name,
        targetPath: targetRoot,
        org: 'com.example',
      );
    } on FormatException catch (e) {
      ctx.output.error(e.message);
      return 1;
    }
    if (flutterExit != 0) {
      ctx.output.error(
        'flutter create exited with code $flutterExit; aborting scaffold.',
      );
      return 1;
    }

    // 5b. Delete flutter create's default `test/<name>_test.dart`. It references
    //     a `Calculator()` function that lives in flutter create's default
    //     `lib/<name>.dart` (which our runtime.dart stub overwrites). Leaving
    //     it behind produces a compile error on the first `flutter analyze`.
    //     Our provider_test.dart stub renders to a different path
    //     (test/<name>_artisan_provider_test.dart) so there is no conflict.
    final defaultTestFile =
        File(p.join(targetRoot, 'test', '${name}_test.dart'));
    if (defaultTestFile.existsSync()) defaultTestFile.deleteSync();

    // 6. Render the generic scaffold over `flutter create`'s defaults. In
    //    magic mode the pubspec stub is sourced from `magic/` (with the
    //    magic dep); the cli.dart stub is also sourced from `magic/` to
    //    export install_command and uninstall_command. Every other generic
    //    stub is sourced from `generic/`.
    _renderPlan(
      plan: _genericScaffoldPlan,
      stubSubdir: 'generic',
      stubBundleDir: stubDir,
      replacements: replacements,
      targetRoot: targetRoot,
      ctx: ctx,
      // In magic mode, override pubspec.yaml (magic dep), cli.dart (exports
      // install/uninstall commands), and runtime.dart (exports the
      // ServiceProvider) to the magic/ subdir.
      stubOverrides: magicMode
          ? const <String, String>{
              'pubspec.yaml': 'magic',
              'cli.dart': 'magic',
              'runtime.dart': 'magic',
              'provider.dart': 'magic',
            }
          : const <String, String>{},
    );

    // 7. In magic mode, render the magic add-on stubs (install command,
    //    manifest, config template, install command test).
    if (magicMode) {
      _renderPlan(
        plan: _magicScaffoldPlan,
        stubSubdir: 'magic',
        stubBundleDir: stubDir,
        replacements: replacements,
        targetRoot: targetRoot,
        ctx: ctx,
      );
    }

    // 8. Detect a parent Flutter app and enroll the plugin into its pub
    //    workspace when found. Sibling-app targets (no parent) skip
    //    enrollment so the plugin remains usable standalone.
    final parentPubspec = _workspaceEnroller.detectParentFlutterApp(targetRoot);
    final pluginPubspec = p.join(targetRoot, 'pubspec.yaml');
    final workspaceEnrolled = parentPubspec != null;
    if (parentPubspec != null) {
      final pluginRelativeToParent = p.relative(
        targetRoot,
        from: p.dirname(parentPubspec),
      );
      await _workspaceEnroller.enrollWorkspace(
        parentPubspecPath: parentPubspec,
        pluginRelativePath: pluginRelativeToParent,
        pluginPubspecPath: pluginPubspec,
      );
      ctx.output.info(
        'Enrolled plugin into parent workspace: $parentPubspec '
        '(added `workspace: [$pluginRelativeToParent]` + '
        '`resolution: workspace`).',
      );
    }

    // 9. Print the success banner and the operator-facing next-steps hint.
    ctx.output.success('Scaffolded plugin "$name" at $targetRoot');
    ctx.output.info('Plugin scaffold complete. Next steps:');
    ctx.output.writeln('  cd $targetRoot && dart pub get && dart test');
    if (workspaceEnrolled) {
      ctx.output.writeln(
        '  Parent app pubspec.yaml was updated for pub workspace enrollment.',
      );
    } else {
      ctx.output.writeln(
        '  No parent Flutter app detected; plugin will run standalone.',
      );
    }
    return 0;
  }

  /// Renders [plan] entries by loading each stub from
  /// `<stubBundleDir>/<stubSubdir>/<stub>.stub` (unless overridden by
  /// [stubOverrides], which maps a stub name to a different subdir name).
  ///
  /// Writes every rendered file under [targetRoot] using the relative
  /// target path from each plan entry (with `{{ name }}` interpolated).
  /// Overwrites any file that `flutter create` may have written at the same
  /// path (this is the revision phase).
  void _renderPlan({
    required List<({String stub, String target})> plan,
    required String stubSubdir,
    required String stubBundleDir,
    required Map<String, String> replacements,
    required String targetRoot,
    required ArtisanContext ctx,
    Map<String, String> stubOverrides = const <String, String>{},
  }) {
    for (final entry in plan) {
      final effectiveSubdir = stubOverrides[entry.stub] ?? stubSubdir;
      final searchDir = p.join(stubBundleDir, effectiveSubdir);
      final stubContent = StubLoader.load(
        entry.stub,
        searchPaths: <String>[searchDir],
      );
      final rendered = StubLoader.replace(stubContent, replacements);
      final relativeTarget = StubLoader.replace(entry.target, replacements);
      final absoluteTarget = p.join(targetRoot, relativeTarget);
      FileHelper.writeFile(absoluteTarget, rendered);
      ctx.output.writeln('Created: $absoluteTarget');
    }
  }

  /// Builds the replacement map shared by every stub render pass.
  ///
  /// @param ctx          The active [ArtisanContext] (read for
  ///                     `--bootstrap-command`).
  /// @param name         The validated snake_case plugin name.
  /// @param artisanPath  Relative path from target to fluttersdk_artisan root.
  /// @param magicPath    Relative path from target to magic root (magic mode
  ///                     only); omitted from the map when null so generic-mode
  ///                     pubspec stubs never reference it.
  /// @return A map suitable for [StubLoader.replace].
  Map<String, String> _buildReplacements(
    ArtisanContext ctx, {
    required String name,
    required String artisanPath,
    String? magicPath,
  }) {
    final pascalName = _pascalCase(name);
    final commandPrefix = _stripConventionPrefix(name);
    final bootstrapOverride = ctx.input.option('bootstrap-command') as String?;
    final bootstrapCommand =
        (bootstrapOverride != null && bootstrapOverride.isNotEmpty)
            ? bootstrapOverride
            : '$commandPrefix:install';

    return <String, String>{
      'name': name,
      'pascalName': pascalName,
      'commandPrefix': commandPrefix,
      'bootstrapCommand': bootstrapCommand,
      'artisanPath': artisanPath,
      if (magicPath != null) 'magicPath': magicPath,
    };
  }

  /// Resolves the target directory the scaffold writes into.
  ///
  /// `--path` wins over `--target` (alias precedence); both override the
  /// conventional `<projectRoot>/packages/<name>` default. `FileHelper`
  /// failing to find a project root surfaces as the underlying exception,
  /// not a swallowed null.
  String _resolveTargetRoot(ArtisanContext ctx, {required String name}) {
    final override = resolvedPath(ctx);
    if (override != null && override.isNotEmpty) return override;
    final projectRoot = FileHelper.findProjectRoot();
    return p.join(projectRoot, 'packages', name);
  }

  /// Returns `true` when magic-aware scaffolding should be applied.
  ///
  /// Two triggers activate magic mode; either is sufficient:
  ///
  /// 1. **Explicit flag**: the operator passed `--magic` on the command line.
  /// 2. **Auto-detect**: the running registry contains `magic:install`, which
  ///    means the command was invoked through `MagicArtisanProvider`; the
  ///    operator is already in a magic project and expects magic defaults.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return `true` when either trigger is active.
  bool isMagic(ArtisanContext ctx) {
    final flagSet = ctx.input.option('magic') == true;
    final autoDetected = ctx.registry?.find('magic:install') != null;
    return flagSet || autoDetected;
  }

  /// Resolves the target directory from the operator-supplied flags.
  ///
  /// `--path` takes precedence over `--target` when both are set, so callers
  /// can use the shorter alias without the longer flag interfering. Returns
  /// `null` when neither flag is present, leaving the caller free to fall back
  /// to the `packages/<name>` convention.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return The resolved path string, or `null` when neither flag is set.
  String? resolvedPath(ArtisanContext ctx) {
    return ctx.input.option('path') as String? ??
        ctx.input.option('target') as String?;
  }

  /// snake_case → PascalCase. `magic_logger` → `MagicLogger`.
  static String _pascalCase(String snake) {
    return snake
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(StringHelper.toPascalCase)
        .join();
  }

  /// Strips the `magic_` / `fluttersdk_` convention prefix from a snake_case
  /// package name. Falls back to the unchanged input when neither prefix
  /// applies so `foo_bar` → `foo_bar` (no surprise mutilation for plugins
  /// outside the fluttersdk org).
  static String _stripConventionPrefix(String snake) {
    for (final prefix in const ['magic_', 'fluttersdk_']) {
      if (snake.startsWith(prefix) && snake.length > prefix.length) {
        return snake.substring(prefix.length);
      }
    }
    return snake;
  }
}
