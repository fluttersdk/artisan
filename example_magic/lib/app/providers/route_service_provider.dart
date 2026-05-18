import 'package:magic/magic.dart';

import '../kernel.dart';
import '../../routes/app.dart';

/// Route Service Provider.
///
/// Registers the HTTP kernel and application routes.
class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  void register() {
    // Register middleware kernel — runs synchronously during bootstrap.
    registerKernel();
  }

  @override
  Future<void> boot() async {
    // Register application route definitions.
    registerAppRoutes();
  }
}
