import 'package:magic/magic.dart';
import '../app/providers/app_service_provider.dart';
import '../app/providers/route_service_provider.dart';
import 'package:my_plugin/my_plugin.dart';

/// Application Configuration.
Map<String, dynamic> get appConfig => {
  'app': {
    'name': env('APP_NAME', 'My App'),
    'env': env('APP_ENV', 'production'),
    'debug': env('APP_DEBUG', false),
    'key': env('APP_KEY'),
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => CacheServiceProvider(app),
      (app) => DatabaseServiceProvider(app),
      (app) => LaunchServiceProvider(app),
      (app) => LocalizationServiceProvider(app),
      (app) => NetworkServiceProvider(app),
      (app) => VaultServiceProvider(app),
      (app) => BroadcastServiceProvider(app),
      (app) => AppServiceProvider(app),
      (app) => AuthServiceProvider(app),
      (app) => MyPluginServiceProvider(app),
    ],
  },
};
