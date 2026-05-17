/// Runtime barrel — Flutter / consumer-side API.
///
/// Tiny demo logger that writes JSON-line records to a configurable file.
/// Consumers call `MagicLogger.debug(...)`, `.info(...)`, `.warn(...)`,
/// `.error(...)` from anywhere in their app; the artisan `logger:tail`
/// command tails the file from the CLI side.
library;

export 'src/runtime/magic_logger.dart';
