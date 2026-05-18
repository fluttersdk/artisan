import 'package:fluttersdk_artisan/artisan.dart';

/// `my_plugin:install`, installs my_plugin into the host project.
///
/// Uses the [PluginInstaller] fluent DSL. For most plugins the declarative
/// `install.yaml` manifest is sufficient and `plugin:install my_plugin`
/// routes through [ManifestInstaller] without ever invoking this command; this
/// procedural override is the escape hatch for plugins that need conditional
/// logic the YAML schema cannot express (env-specific branches, runtime
/// platform detection, dynamic prompts).
class InstallCommand extends ArtisanInstallCommand {
  @override
  String get signature => 'my_plugin:install $baseFlags';

  @override
  String get description => 'Install my_plugin into the host project.';

  @override
  String pluginName(ArtisanContext ctx) => 'my_plugin';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final installer = PluginInstaller(
      buildContext(ctx),
      pluginName: pluginName(ctx),
    ).publishConfig(
      stubName: 'install/my_plugin_config.dart',
      targetPath:
          '${buildContext(ctx).projectRoot}/lib/config/my_plugin.dart',
    );

    final result = await installer.commit(
      dryRun: isDryRun(ctx),
      force: isForce(ctx),
    );

    return switch (result) {
      Success() => 0,
      DryRun() => 0,
      Conflict() => 1,
      Error() => 2,
    };
  }
}
