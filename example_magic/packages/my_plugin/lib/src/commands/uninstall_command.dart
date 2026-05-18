import 'package:fluttersdk_artisan/artisan.dart';

/// `my_plugin:uninstall`, reverses the my_plugin install pass.
///
/// Reads the same `install.yaml` manifest the install command consumed, then
/// asks [ManifestInstaller] to dispatch every previously applied operation in
/// reverse order against the recorded install file. Plugins that override
/// [InstallCommand.handle] with procedural logic SHOULD still keep the
/// declarative manifest in sync so this uninstall path stays accurate.
class UninstallCommand extends ArtisanInstallCommand {
  @override
  String get signature => 'my_plugin:uninstall $baseFlags';

  @override
  String get description => 'Uninstall my_plugin from the host project.';

  @override
  String pluginName(ArtisanContext ctx) => 'my_plugin';

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final installCtx = buildContext(ctx);
    final manifestPath = '${installCtx.projectRoot}/install.yaml';
    final manifest = ManifestParser.parseFile(manifestPath);
    final result =
        await ManifestInstaller(installCtx, manifest).uninstall(force: isForce(ctx));

    return switch (result) {
      Success() => 0,
      DryRun() => 0,
      Conflict() => 1,
      Error() => 2,
    };
  }
}
