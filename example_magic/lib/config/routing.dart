/// Routing Configuration.
///
/// Controls URL strategy and other routing behavior.
/// Set `'url_strategy'` to `'path'` for clean web URLs (/dashboard instead of /#/dashboard).
/// See: https://magic.fluttersdk.com/docs/basics/routing#url-strategy
Map<String, dynamic> get routingConfig => {
  'routing': {
    'url_strategy': null, // 'path' for clean URLs on web, null for default hash strategy
  },
};
