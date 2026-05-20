/// Lifecycle boot mode an [ArtisanCommand] needs from the dispatcher.
///
/// V1 has TWO values (none, connected). `headless` is deliberately deferred
/// to V1.x because a Magic-bound boot in CLI context would force a Flutter
/// dependency into the pure-Dart `fluttersdk_artisan` package AND create a
/// circular dep `magic → artisan → magic`. All current V1 make:* commands
/// are file-system-only (use [FileHelper.findProjectRoot] to locate the
/// host's `pubspec.yaml`; never query `Magic.Config`); they fit `none`
/// cleanly. Headless mode lands when `magic` ships a `MagicArtisanRunner`
/// that the consumer's `bin/dispatcher.dart` wrapper can compose for
/// migrate / db:seed style commands needing a Magic boot.
enum CommandBoot {
  /// Pure CLI. No Magic boot, no Flutter binding, no VM Service connection.
  ///
  /// Examples: `make:*`, `list`, `help`, `make:command`, `start`, `stop`,
  /// `status`, `logs`, `restart`, `doctor`, `starter:install`,
  /// `notifications:install`, `deeplink:install`, `social:install`,
  /// `mcp:install`. File-system / process-management / scaffold work only.
  none,

  /// Reads `~/.artisan/state.json` to dial the VM Service WebSocket of a
  /// running Flutter app + dispatches via `ext.*` extension calls or the
  /// `evaluate` RPC.
  ///
  /// Examples: `dusk:*`, `telescope:*`, `tinker`. Fails fast with a clear
  /// message when no `state.json` is present (operator must run
  /// `artisan start --device=<target>` first).
  connected,
}
