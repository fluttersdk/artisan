/// Logging Configuration.
///
/// This config file is OPTIONAL. Only create it if you want to customize
/// the logging behaviour. The default channel is `stack` which logs to console.
Map<String, dynamic> get loggingConfig => {
  'logging': {
    'default': 'stack',
    'channels': {
      'stack': {
        'driver': 'stack',
        'channels': ['console'],
      },
      'console': {
        'driver': 'console',
        'level': 'debug',
      },
    },
  },
};
