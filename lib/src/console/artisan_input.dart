import 'package:args/args.dart';

/// Abstract input layer for [ArtisanCommand] (Symfony Console parity).
///
/// Three concrete subclasses cover argv-driven, programmatic-map, and
/// programmatic-string invocations.
abstract class ArtisanInput {
  /// Get a named option value (returns null if absent).
  dynamic option(String name);

  /// Get a positional argument by index (returns null if out of range).
  String? argument(int index);

  /// Check whether the option was provided explicitly (vs defaulted).
  bool hasOption(String name);

  /// Argument verbosity level parsed from `-v`, `-vv`, `-vvv`, `-vvvv`.
  ///
  /// 0 = quiet, 1 = normal (default), 2 = verbose, 3 = very verbose, 4 = debug.
  int get verbosity;
}

/// Parses [List<String>] argv typical of CLI invocation.
class ArgvInput implements ArtisanInput {
  ArgvInput(this._results) {
    _verbosity = _detectVerbosity(_results.arguments);
  }

  factory ArgvInput.parse(ArgParser parser, List<String> args) {
    return ArgvInput(parser.parse(args));
  }

  final ArgResults _results;
  late final int _verbosity;

  @override
  dynamic option(String name) {
    if (!_results.options.contains(name)) return null;
    return _results[name];
  }

  @override
  String? argument(int index) {
    if (index >= _results.rest.length) return null;
    return _results.rest[index];
  }

  @override
  bool hasOption(String name) => _results.wasParsed(name);

  @override
  int get verbosity => _verbosity;

  static int _detectVerbosity(Iterable<String> args) {
    for (final a in args) {
      if (a == '-vvvv' || a == '--debug') return 4;
      if (a == '-vvv') return 3;
      if (a == '-vv') return 2;
      if (a == '-v' || a == '--verbose') return 2;
      if (a == '-q' || a == '--quiet') return 0;
    }
    return 1;
  }
}

/// In-memory map input for programmatic invocation (tests, command-from-command).
class MapInput implements ArtisanInput {
  MapInput(this._options, {List<String>? positional, int verbosity = 1})
      : _positional = positional ?? const [],
        _verbosity = verbosity;

  final Map<String, dynamic> _options;
  final List<String> _positional;
  final int _verbosity;

  @override
  dynamic option(String name) => _options[name];

  @override
  String? argument(int index) =>
      index < _positional.length ? _positional[index] : null;

  @override
  bool hasOption(String name) => _options.containsKey(name);

  @override
  int get verbosity => _verbosity;
}
