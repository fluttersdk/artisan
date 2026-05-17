/// Install command stub templates for Magic CLI.
///
/// All methods return valid Dart code strings ready to be written to files.
/// Unlike model_stubs.dart (which uses const String), these methods accept
/// parameters to generate dynamic content based on active feature flags.
library;

import 'stub_loader.dart';

/// Install command stub templates.
///
/// All methods are static and return valid Dart source code strings.
class InstallStubs {
  /// Prevent instantiation — this is a pure static utility class.
  const InstallStubs._();

  // ---------------------------------------------------------------------------
  // main.dart
  // ---------------------------------------------------------------------------

  /// Generates the `lib/main.dart` bootstrap file.
  ///
  /// Produces a full main.dart with `WidgetsFlutterBinding.ensureInitialized()`,
  /// `Magic.init()` with dynamic config factories, and `MagicApplication`.
  ///
  /// [appName] — the human-readable application name (e.g. `My App`).
  /// [configImports] — list of import statements (one per config file).
  /// [configFactories] — list of factory lambda strings (e.g. `() => appConfig`).
  static String mainDartContent({
    required String appName,
    required List<String> configImports,
    required List<String> configFactories,
  }) {
    final imports = configImports.join('\n');
    final factories = configFactories.map((f) => '      $f,').join('\n');

    return StubLoader.replace(StubLoader.load('install/main'), {
      'configImports': imports,
      'configFactories': factories,
      'appName': appName,
    });
  }

  // ---------------------------------------------------------------------------
  // Config files
  // ---------------------------------------------------------------------------

  /// Generates `lib/config/app.dart` with a dynamic providers list.
  ///
  /// [providerImports] — additional provider import statements beyond the
  ///   always-present `RouteServiceProvider` and `AppServiceProvider`.
  /// [providerEntries] — infrastructure `(app) => Provider(app),` strings.
  ///   These boot BEFORE AppServiceProvider and AuthServiceProvider.
  /// [authProviderEntries] — auth-related providers that must boot AFTER
  ///   AppServiceProvider (which registers `setUserFactory`).
  static String appConfigContent({
    required List<String> providerImports,
    required List<String> providerEntries,
    List<String> authProviderEntries = const [],
  }) {
    final allImports = [
      "import 'package:magic/magic.dart';",
      "import '../app/providers/app_service_provider.dart';",
      "import '../app/providers/route_service_provider.dart';",
      ...providerImports,
    ].join('\n');

    // Boot order matters:
    // 1. RouteServiceProvider — routes
    // 2. Infrastructure providers — cache, database, network, vault, etc.
    // 3. AppServiceProvider — registers userFactory via setUserFactory()
    // 4. AuthServiceProvider — calls Auth.restore() (needs userFactory)
    final allProviders = [
      '      (app) => RouteServiceProvider(app),',
      ...providerEntries.map((e) => '      $e'),
      '      (app) => AppServiceProvider(app),',
      ...authProviderEntries.map((e) => '      $e'),
    ].join('\n');

    return StubLoader.replace(StubLoader.load('install/app_config'), {
      'allImports': allImports,
      'allProviders': allProviders,
    });
  }

  /// Generates `lib/config/auth.dart` matching the Uptizm production pattern.
  ///
  /// Uses `final Map` (not a getter) — this is the one config exception.
  static String authConfigContent() {
    return StubLoader.load('install/auth_config');
  }

  /// Generates `lib/config/database.dart` with SQLite as the default driver.
  static String databaseConfigContent() {
    return StubLoader.load('install/database_config');
  }

  /// Generates `lib/config/network.dart` with a single API driver.
  static String networkConfigContent() {
    return StubLoader.load('install/network_config');
  }

  /// Generates `lib/config/view.dart` with Wind UI dialog/confirm classes.
  static String viewConfigContent() {
    return StubLoader.load('install/view_config');
  }

  /// Generates `lib/config/cache.dart` with `FileStore()` driver and default TTL.
  ///
  /// Uses `FileStore()` instance as the driver value, matching the framework's
  /// own `lib/config/cache.dart` default. Requires `package:magic/magic.dart`.
  static String cacheConfigContent() {
    return StubLoader.load('install/cache_config');
  }

  /// Generates `lib/config/logging.dart` with stack -> console channel setup.
  static String loggingConfigContent() {
    return StubLoader.load('install/logging_config');
  }

  /// Generates `lib/config/broadcasting.dart` with Reverb and null connections.
  static String broadcastingConfigContent() {
    return StubLoader.load('install/broadcasting_config');
  }

  /// Generates `lib/config/routing.dart` with URL strategy config.
  ///
  /// Default `url_strategy: null` preserves hash-based URLs.
  /// Set to `'path'` for clean web URLs (`/dashboard` instead of `/#/dashboard`).
  static String routingConfigContent() {
    return StubLoader.load('install/routing_config');
  }

  // ---------------------------------------------------------------------------
  // Service Providers
  // ---------------------------------------------------------------------------

  /// Generates `lib/app/providers/route_service_provider.dart`.
  ///
  /// Calls `registerKernel()` in `register()` and `registerAppRoutes()` in
  /// `boot()`, matching the Uptizm production pattern.
  static String routeServiceProviderContent() {
    return StubLoader.load('install/route_service_provider');
  }

  /// Generates `lib/app/providers/app_service_provider.dart`.
  ///
  /// Ships with empty `register()` and `boot()` methods and a comment
  /// reminding the developer to call `Auth.manager.setUserFactory()`.
  static String appServiceProviderContent() {
    return StubLoader.load('install/app_service_provider');
  }

  // ---------------------------------------------------------------------------
  // Kernel
  // ---------------------------------------------------------------------------

  /// Generates `lib/app/kernel.dart` — the HTTP middleware registry.
  ///
  /// Produces an empty `registerKernel()` function with commented-out examples
  /// showing the Global and Route middleware registration patterns.
  static String kernelDartContent() {
    return StubLoader.load('install/kernel');
  }

  // ---------------------------------------------------------------------------
  // Routes
  // ---------------------------------------------------------------------------

  /// Generates `lib/routes/app.dart` with a single welcome route.
  ///
  /// [appName] — used only for documentation context; not embedded in code.
  static String routesAppContent({required String appName}) {
    // Note: The original template didn't actually use appName in the body,
    // so this is just loading the static stub.
    return StubLoader.load('install/routes_app');
  }

  // ---------------------------------------------------------------------------
  // Views
  // ---------------------------------------------------------------------------

  /// Generates `lib/resources/views/welcome_view.dart`.
  ///
  /// A full Wind UI welcome page showing the app name, framework branding,
  /// and three quick-link cards (Docs, GitHub, CLI Commands).
  ///
  /// [appName] — the human-readable application name shown in the hero section.
  static String welcomeViewContent({required String appName}) {
    return StubLoader.replace(StubLoader.load('install/welcome_view'), {
      'appName': appName,
    });
  }

  // ---------------------------------------------------------------------------
  // Environment files
  // ---------------------------------------------------------------------------

  /// Generates a `.env` template file with sensible defaults.
  ///
  /// [appName] — written as the default value for `APP_NAME`.
  /// [withoutBroadcasting] — when `true`, omits the `BROADCAST_CONNECTION`
  ///   and `REVERB_*` environment variables.
  static String envContent({
    required String appName,
    bool withoutBroadcasting = false,
  }) {
    var content = StubLoader.replace(StubLoader.load('install/env'), {
      'appName': appName,
    });

    if (!withoutBroadcasting) {
      content += '\nBROADCAST_CONNECTION=null\n'
          'REVERB_HOST=localhost\n'
          'REVERB_PORT=8080\n'
          'REVERB_SCHEME=ws\n'
          'REVERB_APP_KEY=\n';
    }

    return content;
  }

  /// Generates a `.env.example` template file with empty values.
  ///
  /// Safe to commit — contains keys but no secrets.
  /// [withoutBroadcasting] — when `true`, omits the `BROADCAST_CONNECTION`
  ///   and `REVERB_*` environment variable keys.
  static String envExampleContent({bool withoutBroadcasting = false}) {
    var content = StubLoader.load('install/env_example');

    if (!withoutBroadcasting) {
      content += '\nBROADCAST_CONNECTION=\n'
          'REVERB_HOST=\n'
          'REVERB_PORT=\n'
          'REVERB_SCHEME=\n'
          'REVERB_APP_KEY=\n';
    }

    return content;
  }

  /// Generates a Magic-compatible smoke test for `test/widget_test.dart`.
  ///
  /// The test intentionally validates only that the generated root widget can
  /// be mounted without throwing, ensuring a stable default after install.
  static String widgetTestContent() {
    return '''import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

void main() {
  testWidgets('Magic app boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MagicApplication(
        title: 'Test App',
      ),
    );

    expect(find.byType(MagicApplication), findsOneWidget);
  });
}
  ''';
  }
}
