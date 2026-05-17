import 'package:args/args.dart';

import 'command_signature.dart';

/// Abstract input layer for [ArtisanCommand] (Laravel-style).
///
/// Three concrete subclasses cover argv-driven, programmatic-map, and
/// programmatic-string invocations. [argument] accepts either an integer
/// index (positional lookup) OR a String name (resolved against the
/// command's signature). [option] returns the value of a flag / option
/// declared in the signature.
abstract class ArtisanInput {
  /// Get a named option / flag value (returns null if absent).
  dynamic option(String name);

  /// Get a positional argument by 0-based index OR by name.
  ///
  /// Passing a String resolves the index from the command signature's
  /// argument declaration order. Passing an int does the literal index
  /// lookup. Returns null when out of range / name unknown.
  String? argument(Object indexOrName);

  /// Check whether the option was provided explicitly (vs defaulted).
  bool hasOption(String name);

  /// Argument verbosity level parsed from `-v`, `-vv`, `-vvv`, `-vvvv`.
  ///
  /// 0 = quiet, 1 = normal (default), 2 = verbose, 3 = very verbose, 4 = debug.
  int get verbosity;
}

/// Parses [List<String>] argv typical of CLI invocation.
class ArgvInput implements ArtisanInput {
  ArgvInput(this._results, {CommandSignature? signature})
      : _signature = signature {
    _verbosity = _detectVerbosity(_results.arguments);
  }

  factory ArgvInput.parse(
    ArgParser parser,
    List<String> args, {
    CommandSignature? signature,
  }) {
    return ArgvInput(parser.parse(args), signature: signature);
  }

  final ArgResults _results;
  final CommandSignature? _signature;
  late final int _verbosity;

  @override
  dynamic option(String name) {
    if (!_results.options.contains(name)) return null;
    return _results[name];
  }

  @override
  String? argument(Object indexOrName) {
    final int index;
    if (indexOrName is int) {
      index = indexOrName;
    } else if (indexOrName is String) {
      final resolved = _resolveArgIndex(indexOrName);
      if (resolved == null) return null;
      index = resolved;
    } else {
      return null;
    }
    if (index < _results.rest.length) {
      return _results.rest[index];
    }
    return _signature?.arguments.elementAtOrNull(index)?.defaultValue;
  }

  @override
  bool hasOption(String name) => _results.wasParsed(name);

  @override
  int get verbosity => _verbosity;

  int? _resolveArgIndex(String name) {
    final sig = _signature;
    if (sig == null) return null;
    for (var i = 0; i < sig.arguments.length; i++) {
      if (sig.arguments[i].name == name) return i;
    }
    return null;
  }

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
  MapInput(
    this._options, {
    List<String>? positional,
    int verbosity = 1,
    CommandSignature? signature,
  })  : _positional = positional ?? const [],
        _verbosity = verbosity,
        _signature = signature;

  final Map<String, dynamic> _options;
  final List<String> _positional;
  final int _verbosity;
  final CommandSignature? _signature;

  @override
  dynamic option(String name) => _options[name];

  @override
  String? argument(Object indexOrName) {
    final int index;
    if (indexOrName is int) {
      index = indexOrName;
    } else if (indexOrName is String) {
      // Direct map-keyed positional lookup wins over signature resolution
      // when tests pass args via the options map (Symfony test pattern).
      if (_options.containsKey(indexOrName)) {
        return _options[indexOrName]?.toString();
      }
      final resolved = _resolveArgIndex(indexOrName);
      if (resolved == null) return null;
      index = resolved;
    } else {
      return null;
    }
    if (index < _positional.length) return _positional[index];
    return _signature?.arguments.elementAtOrNull(index)?.defaultValue;
  }

  @override
  bool hasOption(String name) => _options.containsKey(name);

  @override
  int get verbosity => _verbosity;

  int? _resolveArgIndex(String name) {
    final sig = _signature;
    if (sig == null) return null;
    for (var i = 0; i < sig.arguments.length; i++) {
      if (sig.arguments[i].name == name) return i;
    }
    return null;
  }
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) =>
      (index >= 0 && index < length) ? this[index] : null;
}
