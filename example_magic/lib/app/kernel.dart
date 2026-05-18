// Import Magic to access Kernel, middleware base classes, etc.:
// import 'package:magic/magic.dart';

/// The HTTP Kernel.
///
/// Register all middleware here, similar to Laravel's `app/Http/Kernel.php`.
///
/// ## Usage
///
/// This function is called automatically by `RouteServiceProvider.register()`.
/// You do not need to call it manually.
///
/// ## Global Middleware
///
/// Global middleware runs on EVERY route:
///
/// ```dart
/// Kernel.global([
///   () => LoggingMiddleware(),
/// ]);
/// ```
///
/// ## Route Middleware
///
/// Route middleware are named aliases you use in route definitions:
///
/// ```dart
/// Kernel.registerAll({
///   'auth': () => EnsureAuthenticated(),
///   'guest': () => RedirectIfAuthenticated(),
/// });
/// ```
void registerKernel() {
  // ---------------------------------------------------------------------------
  // Global Middleware
  // ---------------------------------------------------------------------------
  // Kernel.global([
  //   () => LoggingMiddleware(),
  // ]);

  // ---------------------------------------------------------------------------
  // Route Middleware
  // ---------------------------------------------------------------------------
  // Uncomment and add your middleware aliases below:
  // Kernel.registerAll({
  //   'auth': () => EnsureAuthenticated(),
  //   'guest': () => RedirectIfAuthenticated(),
  // });
}
