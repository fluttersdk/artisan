import 'package:fluttersdk_artisan/src/stubs/install_stubs.dart';
import 'package:test/test.dart';

void main() {
  // InstallStubs delegates to StubLoader.load, which resolves the
  // fluttersdk_artisan package root via .dart_tool/package_config.json.
  // Tests run from the package root so the loader finds assets/stubs/install.
  group('InstallStubs (env-only branches)', () {
    test('envContent includes appName replacement', () {
      final content = InstallStubs.envContent(appName: 'TestApp');

      expect(content, contains('TestApp'));
    });

    test('envContent appends REVERB_* block by default', () {
      final content = InstallStubs.envContent(appName: 'TestApp');

      expect(content, contains('REVERB_HOST=localhost'));
      expect(content, contains('BROADCAST_CONNECTION=null'));
    });

    test('envContent withoutBroadcasting omits REVERB block', () {
      final content = InstallStubs.envContent(
        appName: 'TestApp',
        withoutBroadcasting: true,
      );

      expect(content, isNot(contains('REVERB_HOST')));
      expect(content, isNot(contains('BROADCAST_CONNECTION')));
    });

    test('envExampleContent default appends empty REVERB_* keys', () {
      final content = InstallStubs.envExampleContent();

      expect(content, contains('REVERB_HOST='));
    });

    test('envExampleContent withoutBroadcasting omits REVERB block', () {
      final content = InstallStubs.envExampleContent(withoutBroadcasting: true);

      expect(content, isNot(contains('REVERB_HOST')));
    });

    test('widgetTestContent is non-empty and references MagicApplication', () {
      final content = InstallStubs.widgetTestContent();

      expect(content, contains('MagicApplication'));
      expect(content, contains('testWidgets'));
    });
  });

  group('InstallStubs (stub-backed loaders)', () {
    test('mainDartContent renders appName + imports + factories', () {
      final content = InstallStubs.mainDartContent(
        appName: 'Acme',
        configImports: <String>["import 'config/app.dart';"],
        configFactories: <String>['() => appConfig'],
      );

      expect(content, isNotEmpty);
      expect(content, contains('Acme'));
    });

    test('appConfigContent embeds the provider list', () {
      final content = InstallStubs.appConfigContent(
        providerImports: <String>[],
        providerEntries: <String>['(app) => CacheProvider(app),'],
      );

      expect(content, isNotEmpty);
      expect(content, contains('CacheProvider(app)'));
    });

    test('appConfigContent supports authProviderEntries', () {
      final content = InstallStubs.appConfigContent(
        providerImports: <String>[
          "import '../app/providers/cache_service_provider.dart';"
        ],
        providerEntries: <String>['(app) => CacheServiceProvider(app),'],
        authProviderEntries: <String>['(app) => AuthServiceProvider(app),'],
      );

      expect(content, contains('CacheServiceProvider(app)'));
      expect(content, contains('AuthServiceProvider(app)'));
    });

    test('authConfigContent returns the bare auth config stub', () {
      expect(InstallStubs.authConfigContent(), isNotEmpty);
    });

    test('databaseConfigContent returns the bare database stub', () {
      expect(InstallStubs.databaseConfigContent(), isNotEmpty);
    });

    test('networkConfigContent returns the bare network stub', () {
      expect(InstallStubs.networkConfigContent(), isNotEmpty);
    });

    test('viewConfigContent returns the view stub', () {
      expect(InstallStubs.viewConfigContent(), isNotEmpty);
    });

    test('cacheConfigContent returns the cache stub', () {
      expect(InstallStubs.cacheConfigContent(), isNotEmpty);
    });

    test('loggingConfigContent returns the logging stub', () {
      expect(InstallStubs.loggingConfigContent(), isNotEmpty);
    });

    test('broadcastingConfigContent returns the broadcasting stub', () {
      expect(InstallStubs.broadcastingConfigContent(), isNotEmpty);
    });

    test('routingConfigContent returns the routing stub', () {
      expect(InstallStubs.routingConfigContent(), isNotEmpty);
    });

    test('routeServiceProviderContent returns the route provider stub', () {
      expect(InstallStubs.routeServiceProviderContent(), isNotEmpty);
    });

    test('appServiceProviderContent returns the app provider stub', () {
      expect(InstallStubs.appServiceProviderContent(), isNotEmpty);
    });

    test('kernelDartContent returns the kernel stub', () {
      expect(InstallStubs.kernelDartContent(), isNotEmpty);
    });

    test('routesAppContent returns the routes stub', () {
      expect(InstallStubs.routesAppContent(appName: 'Acme'), isNotEmpty);
    });

    test('welcomeViewContent embeds the app name', () {
      final content = InstallStubs.welcomeViewContent(appName: 'Acme');

      expect(content, isNotEmpty);
      expect(content, contains('Acme'));
    });
  });
}
