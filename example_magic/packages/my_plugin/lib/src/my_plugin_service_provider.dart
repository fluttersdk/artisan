import 'package:magic/magic.dart';

/// Magic ServiceProvider for my_plugin.
///
/// Auto-registered into the host app's `config/app.dart` providers list when
/// the consumer runs `dart run <host>:artisan plugin:install my_plugin` (the
/// install.yaml manifest's `magic.provider:` field drives the injection).
///
/// Two-phase lifecycle:
/// - `register()` binds services into the IoC container; runs before any
///   other provider's `boot()` so order of registration does not matter.
/// - `boot()` runs after every provider has registered; resolve cross-plugin
///   dependencies here.
class MyPluginServiceProvider extends ServiceProvider {
  MyPluginServiceProvider(super.app);

  @override
  void register() {
    // TODO: bind your services here.
    // Example: app.singleton('my_plugin', () => MyPluginService());
  }

  @override
  Future<void> boot() async {
    // TODO: configure services after all providers are registered.
  }
}
