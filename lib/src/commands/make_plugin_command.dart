import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../console/string_helper.dart';
import '../helpers/file_helper.dart';
import '../stubs/stub_loader.dart';

/// `artisan make:plugin <name>`, scaffolds a new `fluttersdk_artisan` plugin
/// skeleton under `packages/<name>/` (or a `--target` override).
///
/// Generates the 11-file Plugin Authoring Guide layout in one shot: pubspec,
/// CLI barrel, runtime barrel, [ArtisanServiceProvider], install + uninstall
/// commands wired through the [PluginInstaller] DSL, the declarative
/// `install.yaml` manifest, a sample config stub the install command
/// publishes, two seed test files, and a README. Mirrors Laravel's
/// `make:package` generator: every file ships with TODOs only where authoring
/// is unavoidable, so the freshly scaffolded plugin compiles and `dart test`
/// passes without manual edits.
///
/// ## Replacement variables
///
/// Every stub uses four placeholders, derived once from the [name] argument:
///
/// - `name`, the snake_case package name (e.g. `magic_logger`).
/// - `pascalName`, the PascalCase class root (e.g. `MagicLogger`).
/// - `commandPrefix`, the package name with the `magic_` / `fluttersdk_`
///   convention prefix stripped (e.g. `magic_logger` → `logger`). Drives the
///   default `<commandPrefix>:install` / `<commandPrefix>:uninstall` names.
/// - `bootstrapCommand`, the value of the `--bootstrap-command` option, or
///   `<commandPrefix>:install` when the option is absent. Written to the
///   manifest's `bootstrap_command:` key so `plugin:install` can chain into
///   the plugin's own setup flow.
///
/// ## Test injection
///
/// [resolveStubDir] is the seam for `_TestableMakePluginCommand` subclasses:
/// production reads the stub bundle out of the resolved
/// `fluttersdk_artisan` package via [Isolate.resolvePackageUri]; tests pin it
/// to the checked-in `assets/stubs/make_plugin/` directory so the suite does
/// not require a pub-resolved `package_config.json`.
class MakePluginCommand extends ArtisanCommand {
  /// Public default constructor. Test fixtures subclass + override
  /// [resolveStubDir] for deterministic stub directory injection.
  MakePluginCommand();

  /// Pre-compiled snake_case validator: must start with a lowercase letter and
  /// contain only `[a-z0-9_]` afterwards. Mirrors Dart's pubspec `name:`
  /// validation rule, which is the most restrictive of all consumers.
  static final RegExp _validNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

  /// 11-file scaffold mapping: stub asset name → target path template under
  /// the resolved plugin root. The `{{ name }}` segments in the target paths
  /// are interpolated AFTER stub rendering so file names follow the same
  /// snake_case convention as the package itself.
  static const List<({String stub, String target})> _scaffoldPlan = [
    (stub: 'pubspec.yaml', target: 'pubspec.yaml'),
    (stub: 'cli.dart', target: 'lib/cli.dart'),
    (stub: 'runtime.dart', target: 'lib/{{ name }}.dart'),
    (
      stub: 'provider.dart',
      target: 'lib/src/{{ name }}_artisan_provider.dart',
    ),
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
      stub: 'provider_test.dart',
      target: 'test/{{ name }}_artisan_provider_test.dart',
    ),
    (
      stub: 'install_command_test.dart',
      target: 'test/cli/install_command_test.dart',
    ),
    (stub: 'readme.md', target: 'README.md'),
  ];

  @override
  String get signature => 'make:plugin '
      '{name : Plugin package name in snake_case} '
      '{--target= : Target directory (default: packages/<name>)} '
      '{--bootstrap-command= : Override bootstrap command name '
      '(default: <commandPrefix>:install)}';

  @override
  String get description =>
      'Scaffold a new fluttersdk_artisan plugin skeleton.';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Resolves the directory holding the `make_plugin/` stub bundle. Production
  /// uses [Isolate.resolvePackageUri] to find the
  /// `fluttersdk_artisan/assets/stubs/make_plugin/` directory; tests override
  /// to pin a deterministic path.
  ///
  /// @return Absolute path to the `make_plugin` stub bundle directory.
  /// @throws StateError when the package URI cannot be resolved (e.g. the
  ///         test runner has no `package_config.json` for `fluttersdk_artisan`).
  @visibleForTesting
  Future<String> resolveStubDir() async {
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
    final pkgRoot = p.dirname(p.dirname(resolved.toFilePath()));
    return p.join(pkgRoot, 'assets', 'stubs', 'make_plugin');
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

    // 2. Compute the replacement variables once, share across all 11 stubs.
    final replacements = _buildReplacements(ctx, name: name);

    // 3. Resolve the target plugin root: --target overrides the conventional
    //    <projectRoot>/packages/<name> default.
    final targetRoot = _resolveTargetRoot(ctx, name: name);

    // 4. Resolve the stub bundle directory (test seam).
    final stubDir = await resolveStubDir();
    if (!Directory(stubDir).existsSync()) {
      ctx.output.error('Stub directory not found: $stubDir');
      return 1;
    }

    // 5. Render + write each stub in declaration order. Bail on the first
    //    failure so partial scaffolds are easy to clean up by deleting the
    //    target directory.
    for (final entry in _scaffoldPlan) {
      final stubContent = StubLoader.load(
        entry.stub,
        searchPaths: <String>[stubDir],
      );
      final rendered = StubLoader.replace(stubContent, replacements);
      final relativeTarget = StubLoader.replace(entry.target, replacements);
      final absoluteTarget = p.join(targetRoot, relativeTarget);
      FileHelper.writeFile(absoluteTarget, rendered);
      ctx.output.writeln('Created: $absoluteTarget');
    }

    // 6. Print the next-steps hint so the operator can verify the scaffold.
    ctx.output.success('Scaffolded plugin "$name" at $targetRoot');
    ctx.output.info('Next steps:');
    ctx.output.writeln('  cd $targetRoot && dart pub get && dart test');
    return 0;
  }

  /// Builds the four-key replacement map shared by every stub render pass.
  ///
  /// @param ctx   The active [ArtisanContext] (read for `--bootstrap-command`).
  /// @param name  The validated snake_case plugin name.
  /// @return A map suitable for [StubLoader.replace].
  Map<String, String> _buildReplacements(
    ArtisanContext ctx, {
    required String name,
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
    };
  }

  /// Resolves the target directory the scaffold writes into.
  ///
  /// `--target` wins when set; otherwise the conventional
  /// `<projectRoot>/packages/<name>` directory is used. `FileHelper`
  /// failing to find a project root surfaces as the underlying exception,
  /// not a swallowed null.
  String _resolveTargetRoot(ArtisanContext ctx, {required String name}) {
    final override = ctx.input.option('target') as String?;
    if (override != null && override.isNotEmpty) return override;
    final projectRoot = FileHelper.findProjectRoot();
    return p.join(projectRoot, 'packages', name);
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
