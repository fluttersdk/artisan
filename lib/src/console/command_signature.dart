import 'package:args/args.dart';

/// Laravel-style command signature DSL parser.
///
/// A signature compresses the command name + every positional argument +
/// every option/flag into a single string declared on the command class.
/// The dispatcher parses it once at registration time, applies the
/// declarations to the underlying [ArgParser], and exposes the argument
/// names so [ArtisanInput.argument] can look up by name (not just index).
///
/// ## Grammar
///
/// ```
/// signature  := name (whitespace token)*
/// name       := lowercase-kebab-case-with-optional:colon-namespace
/// token      := '{' (argument | option) '}'
/// argument   := name [modifier] [' : ' description]
/// option     := '--' name [value-spec] [' : ' description]
/// modifier   := '?'           // optional
///             | '*'           // variadic
///             | '?*'          // optional variadic
///             | '=' default   // positional with default
/// value-spec := '='           // required value, no default
///             | '=' default   // option with default
/// ```
///
/// ## Examples
///
/// ```dart
/// 'sync-monitors'
/// 'sync:monitors {team}'
/// 'sync:monitors {team?}'
/// 'sync:monitors {team=acme}'
/// 'sync:monitors {team*}'
/// 'sync:monitors {--force}'
/// 'sync:monitors {--limit=10}'
/// 'sync:monitors {team : Team slug} {--force : Skip prompts}'
/// ```
class CommandSignature {
  CommandSignature({
    required this.name,
    required this.arguments,
    required this.options,
  });

  /// Dispatch name (e.g. `sync-monitors`, `mail:send-digest`).
  final String name;

  /// Positional argument specs in declaration order.
  final List<ArgumentSpec> arguments;

  /// Option / flag specs in declaration order.
  final List<OptionSpec> options;

  /// Parse a signature string. Throws [FormatException] when the syntax
  /// does not match the grammar above.
  factory CommandSignature.parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Signature must not be empty.');
    }

    // 1. Split name from the rest. Name is everything up to the first
    //    whitespace or `{`.
    final firstBraceOrSpace = RegExp(r'[\s{]').firstMatch(trimmed);
    final name = firstBraceOrSpace == null
        ? trimmed
        : trimmed.substring(0, firstBraceOrSpace.start);

    if (!_namePattern.hasMatch(name)) {
      throw FormatException(
        'Invalid command name "$name": must match $_namePatternSource '
        '(lowercase snake_case or kebab-case, optional colon-separated namespaces).',
      );
    }

    final tail = firstBraceOrSpace == null
        ? ''
        : trimmed.substring(firstBraceOrSpace.start);

    // 2. Extract every `{...}` token block.
    final arguments = <ArgumentSpec>[];
    final options = <OptionSpec>[];
    for (final match in _tokenPattern.allMatches(tail)) {
      final body = match.group(1)!.trim();
      if (body.startsWith('--')) {
        options.add(_parseOption(body.substring(2)));
      } else {
        arguments.add(_parseArgument(body));
      }
    }

    return CommandSignature(
      name: name,
      arguments: List<ArgumentSpec>.unmodifiable(arguments),
      options: List<OptionSpec>.unmodifiable(options),
    );
  }

  /// Apply this signature to [parser] so the underlying args package
  /// recognises the declared options/flags. Positional arguments stay in
  /// the parser's `rest` and are mapped to names via [ArgumentSpec].
  void applyTo(ArgParser parser) {
    for (final opt in options) {
      if (opt.isFlag) {
        parser.addFlag(
          opt.name,
          help: opt.description,
          negatable: false,
        );
      } else {
        parser.addOption(
          opt.name,
          help: opt.description,
          defaultsTo: opt.defaultValue,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static ArgumentSpec _parseArgument(String body) {
    final descriptionSplit = _splitDescription(body);
    var head = descriptionSplit.$1;
    final description = descriptionSplit.$2;

    bool isOptional = false;
    bool isVariadic = false;
    String? defaultValue;

    // Optional default value via `name=value`.
    final eqIndex = head.indexOf('=');
    if (eqIndex >= 0) {
      defaultValue = head.substring(eqIndex + 1);
      head = head.substring(0, eqIndex);
      isOptional = true;
    }

    // Variadic + optional flags trail the name.
    if (head.endsWith('?*')) {
      isOptional = true;
      isVariadic = true;
      head = head.substring(0, head.length - 2);
    } else if (head.endsWith('*')) {
      isVariadic = true;
      head = head.substring(0, head.length - 1);
    } else if (head.endsWith('?')) {
      isOptional = true;
      head = head.substring(0, head.length - 1);
    }

    final name = head.trim();
    if (!_argNamePattern.hasMatch(name)) {
      throw FormatException(
        'Invalid argument name "$name": must be lowercase letters / digits / hyphens / underscores.',
      );
    }

    return ArgumentSpec(
      name: name,
      isOptional: isOptional,
      isVariadic: isVariadic,
      defaultValue: defaultValue,
      description: description,
    );
  }

  static OptionSpec _parseOption(String body) {
    final descriptionSplit = _splitDescription(body);
    var head = descriptionSplit.$1;
    final description = descriptionSplit.$2;

    // `=` indicates value-bearing option; absence indicates boolean flag.
    final eqIndex = head.indexOf('=');
    final bool isFlag = eqIndex < 0;
    String name;
    String? defaultValue;
    if (isFlag) {
      name = head.trim();
    } else {
      name = head.substring(0, eqIndex).trim();
      final after = head.substring(eqIndex + 1).trim();
      defaultValue = after.isEmpty ? null : after;
    }

    if (!_argNamePattern.hasMatch(name)) {
      throw FormatException(
        'Invalid option name "$name": must be lowercase letters / digits / hyphens / underscores.',
      );
    }

    return OptionSpec(
      name: name,
      isFlag: isFlag,
      defaultValue: defaultValue,
      description: description,
    );
  }

  /// Splits a token body into (head, description) on the first ' : '
  /// separator. Description is null when absent.
  static (String head, String? description) _splitDescription(String body) {
    final descriptionMatch = _descriptionSplit.firstMatch(body);
    if (descriptionMatch == null) return (body, null);
    return (
      body.substring(0, descriptionMatch.start),
      body.substring(descriptionMatch.end).trim(),
    );
  }

  static const String _namePatternSource = r'^[a-z0-9_]+([:-][a-z0-9_]+)*$';
  static final RegExp _namePattern = RegExp(_namePatternSource);
  static final RegExp _argNamePattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');
  static final RegExp _tokenPattern = RegExp(r'\{([^}]+)\}');
  static final RegExp _descriptionSplit = RegExp(r'\s+:\s+');
}

/// Positional argument specification parsed out of a signature.
class ArgumentSpec {
  const ArgumentSpec({
    required this.name,
    this.isOptional = false,
    this.isVariadic = false,
    this.defaultValue,
    this.description,
  });

  final String name;
  final bool isOptional;
  final bool isVariadic;
  final String? defaultValue;
  final String? description;

  @override
  String toString() =>
      'ArgumentSpec($name, optional=$isOptional, variadic=$isVariadic, default=$defaultValue)';
}

/// Option / flag specification parsed out of a signature.
class OptionSpec {
  const OptionSpec({
    required this.name,
    this.isFlag = false,
    this.defaultValue,
    this.description,
  });

  final String name;

  /// `true` when the option is a boolean switch with no value (e.g. `--force`).
  final bool isFlag;
  final String? defaultValue;
  final String? description;

  @override
  String toString() => 'OptionSpec($name, flag=$isFlag, default=$defaultValue)';
}
