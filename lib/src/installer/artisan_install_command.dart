import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import 'install_context.dart';

/// Base class for every install command in the PluginInstaller DSL ecosystem.
///
/// Centralises the standard install-command surface so concrete commands
/// (e.g. `plugin:install`, `plugin:uninstall`, `logger:install`, future
/// `<plugin>:install` commands authored by third parties) inherit a uniform
/// API without re-declaring the same four flags, the same boot mode, and the
/// same `InstallContext` plumbing on every subclass.
///
/// ## Inherited surface
///
/// - [signature] interpolation via [baseFlags]: every concrete subclass writes
///   `String get signature => 'my:install $baseFlags{...subclass tokens}';`.
///   The four standard flags (`--force`, `--dry-run`, `--non-interactive`,
///   `--no-bootstrap`) land on the parser automatically.
/// - [boot] is locked to [CommandBoot.none]: install commands run before the
///   Flutter app boots, so no VM Service connection is available.
/// - [buildContext] returns an [InstallContext.real] composed around the
///   [ArtisanContext] handed to [handle], wiring the production [VirtualFs] /
///   [PromptDriver] / [StubDriver] / clock.
/// - [isDryRun] / [isForce] / [isNonInteractive] / [isSkipBootstrap] read the
///   four standard flags from `ctx.input.option(...)`. They take an
///   [ArtisanContext] parameter because [ArtisanCommand] has no instance
///   field for input — options live on the per-invocation context the
///   dispatcher hands `handle()`.
/// - [pluginName] is abstract: each subclass must declare which plugin record
///   this command writes to. Static return for fixed-plugin commands; derive
///   from `ctx.input.argument('name')` for the dynamic `plugin:install` case.
///
/// ## Usage
///
/// ```dart
/// class LoggerInstallCommand extends ArtisanInstallCommand {
///   @override
///   String get signature => 'logger:install $baseFlags{--path= : Log path}';
///
///   @override
///   String get description => 'Install the logger plugin.';
///
///   @override
///   String pluginName(ArtisanContext ctx) => 'magic_logger';
///
///   @override
///   Future<int> handle(ArtisanContext ctx) async {
///     final installCtx = buildContext(ctx);
///     final installer = PluginInstaller(installCtx, pluginName: pluginName(ctx));
///     // ... chain ops ...
///     final result = await installer.commit(
///       dryRun: isDryRun(ctx),
///       force: isForce(ctx),
///     );
///     return result is Success ? 0 : 1;
///   }
/// }
/// ```
abstract class ArtisanInstallCommand extends ArtisanCommand {
  /// Standard install-command flag fragment interpolated into every concrete
  /// subclass's [signature].
  ///
  /// Subclasses build their signature as
  /// `'my:install $baseFlags{...subclass-specific tokens}'`. The four flags
  /// are surfaced through the [isDryRun] / [isForce] / [isNonInteractive] /
  /// [isSkipBootstrap] helper methods rather than parsed inline at every call
  /// site.
  ///
  /// @return The 4-flag signature fragment with a trailing space.
  String get baseFlags => '{--force : Bypass conflict detection} '
      '{--dry-run : Print staged ops without writing} '
      '{--non-interactive : Skip prompts, use defaults} '
      '{--no-bootstrap : Skip post-install hint message} ';

  /// Install commands run before the Flutter app boots: no VM Service, no
  /// connected isolate. The dispatcher constructs a [ArtisanContext.bare].
  @override
  CommandBoot get boot => CommandBoot.none;

  /// Constructs the production [InstallContext] wired around [ctx].
  ///
  /// Subclasses override only when they need a custom context (e.g. tests in
  /// the host package may override to inject an in-memory [VirtualFs]). The
  /// default wiring is the production stack ([RealFs] / [RealPromptDriver] /
  /// [RealStubDriver] / `DateTime.now`).
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return A fully wired [InstallContext] ready for [PluginInstaller].
  InstallContext buildContext(ArtisanContext ctx) => InstallContext.real(ctx);

  /// Returns `true` when the operator passed `--dry-run`.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return The boolean value of the `--dry-run` flag.
  bool isDryRun(ArtisanContext ctx) => ctx.input.option('dry-run') as bool;

  /// Returns `true` when the operator passed `--force`.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return The boolean value of the `--force` flag.
  bool isForce(ArtisanContext ctx) => ctx.input.option('force') as bool;

  /// Returns `true` when the operator passed `--non-interactive`.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return The boolean value of the `--non-interactive` flag.
  bool isNonInteractive(ArtisanContext ctx) =>
      ctx.input.option('non-interactive') as bool;

  /// Returns `true` when the operator passed `--no-bootstrap`.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return The boolean value of the `--no-bootstrap` flag.
  bool isSkipBootstrap(ArtisanContext ctx) =>
      ctx.input.option('no-bootstrap') as bool;

  /// Identifier of the plugin this install command targets.
  ///
  /// Threaded into [PluginInstaller] and through to the
  /// `.artisan/installed/<pluginName>.json` record path. Subclasses MUST
  /// override — the abstract contract prevents accidental cross-plugin
  /// record-file collisions when a copy-pasted command forgets to flip the
  /// name.
  ///
  /// @param ctx  The active [ArtisanContext] handed to [handle].
  /// @return The plugin pubspec package name.
  String pluginName(ArtisanContext ctx);
}
