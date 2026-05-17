/// Pure-Dart CLI sub-barrel. Consumer's `bin/artisan.dart` imports this
/// and calls `registry.registerProvider(MagicLoggerArtisanProvider())`.
///
/// Runtime (Flutter-side) API lives in `package:magic_logger/magic_logger.dart`.
library;

export 'src/commands/install_command.dart';
export 'src/commands/level_command.dart';
export 'src/commands/tail_command.dart';
export 'src/commands/uninstall_command.dart';
export 'src/magic_logger_artisan_provider.dart';
