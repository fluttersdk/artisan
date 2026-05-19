/// CLI barrel for awesome_plugin.
///
/// Consumers import via `package:awesome_plugin/cli.dart` and the
/// `plugin:install awesome_plugin` command resolves the provider symbol from this
/// barrel. Keep the exports limited to CLI-relevant symbols (provider +
/// runtime). Runtime-only classes belong in `package:awesome_plugin/awesome_plugin.dart`.
library;

export 'src/awesome_plugin_artisan_provider.dart';
