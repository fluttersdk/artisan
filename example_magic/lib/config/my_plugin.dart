/// MyPlugin configuration template.
///
/// Rendered into `lib/config/my_plugin.dart` when the consumer runs
/// `artisan my_plugin:install`. The `~/.my_plugin.conf` token is
/// resolved by [ManifestInstaller] at install time from the prompt answer
/// declared in `install.yaml`.
class MyPluginConfig {
  static const String configFilePath = r'~/.my_plugin.conf';
}
