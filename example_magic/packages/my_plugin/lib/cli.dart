/// CLI barrel for my_plugin.
///
/// Consumers import via `package:my_plugin/cli.dart` and the
/// `plugin:install my_plugin` command resolves the provider symbol from this
/// barrel. Magic-mode plugins export the provider, install command, and
/// uninstall command. Runtime-only classes belong in
/// `package:my_plugin/my_plugin.dart`.
library;

export 'src/my_plugin_artisan_provider.dart';
export 'src/commands/install_command.dart';
export 'src/commands/uninstall_command.dart';
