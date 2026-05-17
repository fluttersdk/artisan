import 'package:args/args.dart';

import 'artisan_context.dart';
import 'command_boot.dart';

/// Base class for every artisan command (Symfony Console parity).
///
/// Subclasses declare:
/// - [name]: the dispatch key, e.g. `start`, `dusk:snap`, `make:controller`.
/// - [description]: short description shown in `artisan list` + `artisan help`.
/// - [boot]: lifecycle the dispatcher must establish before [handle] runs.
/// - [configure]: optional flag/option declarations on the [ArgParser].
/// - [handle]: the actual work; receives a fully-prepared [ArtisanContext].
///
/// The handler returns the process exit code (0 = success, non-zero = failure).
/// Throwing from [handle] is reserved for unexpected failures; expected errors
/// (missing args, file conflicts, unreachable VM) should write to
/// `ctx.output.error(...)` and return a non-zero exit code.
abstract class ArtisanCommand {
  /// Dispatch key. Colons (`:`) act as namespace prefixes for `artisan list`
  /// grouping (e.g. `dusk:snap` groups under `dusk`).
  String get name;

  /// One-line description (rendered in `artisan list` next to [name]).
  String get description;

  /// What boot context the dispatcher must establish before calling [handle].
  /// See [CommandBoot] for the V1 taxonomy (none, connected).
  CommandBoot get boot;

  /// Override to declare flags + options.
  void configure(ArgParser parser) {}

  /// Execute the command. Returns the process exit code.
  Future<int> handle(ArtisanContext ctx);
}
