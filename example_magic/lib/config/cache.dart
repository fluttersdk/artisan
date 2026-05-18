import 'package:magic/magic.dart';

/// Cache Configuration.
///
/// - `driver`: `FileStore()` for persistent disk caching.
/// - `ttl`: default time-to-live in seconds.
Map<String, dynamic> get cacheConfig => {
  'cache': {
    'driver': FileStore(),
    'ttl': 3600,
  },
};
