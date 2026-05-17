import 'package:magic/magic.dart';

/// Network Configuration.
///
/// This config file is OPTIONAL. Only create it if you want to use the
/// Magic Network (Http) system. Don't forget to add `NetworkServiceProvider`
/// to your `app.providers` list.
Map<String, dynamic> get networkConfig => {
  'network': {
    'default': 'api',
    'drivers': {
      'api': {
        'base_url': env('API_URL', 'http://localhost:8000/api/v1'),
        'timeout': 10000,
        'headers': {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      },
    },
  },
};
