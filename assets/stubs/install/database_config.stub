/// Database Configuration.
///
/// Uses SQLite by default. On mobile, files are stored in the app's documents
/// directory. On web, in-memory SQLite is used automatically.
Map<String, dynamic> get databaseConfig => {
  'database': {
    'default': 'sqlite',
    'connections': {
      'sqlite': {
        'driver': 'sqlite',
        'database': 'database.sqlite',
      },
    },
  },
};
