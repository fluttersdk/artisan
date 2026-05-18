/// Runtime API for my_plugin (magic mode).
///
/// Plugin authors expose their public runtime surface here. Consumers import
/// via `package:my_plugin/my_plugin.dart` to gain access to the runtime
/// classes (controllers, services, models, the Magic ServiceProvider). The
/// CLI surface lives in `package:my_plugin/cli.dart` and is invoked through
/// `artisan` only.
library;

export 'src/my_plugin_service_provider.dart';
// TODO: export your runtime classes (controllers, services, models).
