import 'package:args/args.dart';

import 'artisan_context.dart';
import 'command_boot.dart';
import 'command_signature.dart';

/// Base class for every artisan command (Laravel + Symfony Console parity).
///
/// Two ways to declare what the command exposes:
///
/// **Signature DSL (recommended, Laravel-style)** — one string captures the
/// dispatch name, every positional argument, every flag, every option:
///
/// ```dart
/// class SyncMonitorsCommand extends ArtisanCommand {
///   @override
///   String get signature =>
///       'sync:monitors {team} {--force : Skip confirmation} {--limit=50}';
///
///   @override
///   String get description => "Reconcile a team's monitors with the API.";
///
///   @override
///   CommandBoot get boot => CommandBoot.none;
///
///   @override
///   Future<int> handle(ArtisanContext ctx) async {
///     final team = ctx.input.argument('team');               // by name
///     final force = ctx.input.option('force') as bool;
///     final limit = int.parse(ctx.input.option('limit') as String);
///     // ...
///   }
/// }
/// ```
///
/// **Explicit (low-level, Symfony Console parity)** — override `name` +
/// `configure(parser)` directly. Still supported for fine-grained
/// `ArgParser` control (mandatory options, aliases, custom validators).
///
/// `signature` and the explicit form do not mix in the same command —
/// pick one. Both forms support the same handler contract: return the
/// process exit code (0 = success, non-zero = failure). Throwing from
/// `handle` is reserved for unexpected failures; expected errors (missing
/// args, file conflicts, unreachable VM) should write to
/// `ctx.output.error(...)` and return non-zero.
abstract class ArtisanCommand {
  /// Optional Laravel-style signature DSL. When set, [name] derives from
  /// it and [configure] auto-registers the declared options/flags.
  ///
  /// See [CommandSignature] for the full grammar.
  String? get signature => null;

  /// Lazy-parsed [signature]. Cached for the lifetime of the instance.
  CommandSignature? get parsedSignature {
    final sig = signature;
    if (sig == null) return null;
    return _parsedSignature ??= CommandSignature.parse(sig);
  }

  CommandSignature? _parsedSignature;

  /// Dispatch key. Colons (`:`) act as namespace prefixes for `artisan list`
  /// grouping (e.g. `dusk:snap` groups under `dusk`).
  ///
  /// Default: derived from [signature]. Throws if neither is set.
  String get name {
    final parsed = parsedSignature;
    if (parsed != null) return parsed.name;
    throw StateError(
      '$runtimeType: override `signature` or `name`. '
      'Recommended: `String get signature => "$_recommendedName";`',
    );
  }

  /// One-line description (rendered in `artisan list` next to [name]).
  String get description;

  /// What boot context the dispatcher must establish before calling [handle].
  /// See [CommandBoot] for the V1 taxonomy (none, connected).
  CommandBoot get boot;

  /// Auto-applies [signature] to the parser when set. Override to register
  /// extra ArgParser features (mandatory options, aliases, custom value
  /// validators). When you override, call `super.configure(parser)` first
  /// if you also use the signature DSL.
  void configure(ArgParser parser) {
    parsedSignature?.applyTo(parser);
  }

  /// Execute the command. Returns the process exit code.
  Future<int> handle(ArtisanContext ctx);

  String get _recommendedName {
    final raw = runtimeType.toString();
    final withoutSuffix =
        raw.endsWith('Command') ? raw.substring(0, raw.length - 7) : raw;
    final kebab = withoutSuffix
        .replaceAllMapped(
            RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
        .toLowerCase();
    return kebab.isEmpty ? 'unnamed' : kebab;
  }
}
