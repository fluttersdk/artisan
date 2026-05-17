import '../console/prompt.dart';

/// Contract for interactive user-prompt I/O in the PluginInstaller DSL.
///
/// Mirrors the four-method surface of the static [Prompt] class so that
/// [InstallContext] can hold an instance field and tests can inject a
/// [FakePromptDriver] without touching stdin.
///
/// ## Usage
///
/// ```dart
/// final driver = RealPromptDriver();
/// final name = driver.ask('Plugin name?', defaultValue: 'my_plugin');
/// if (driver.confirm('Publish stubs?')) { ... }
/// ```
abstract class PromptDriver {
  /// Ask a free-form question and return the user's trimmed answer.
  ///
  /// When the user presses ENTER without typing, [defaultValue] is returned.
  /// [validator], when supplied, is called on the parsed answer; a non-null
  /// return value re-asks the question with the error message above the prompt.
  ///
  /// @param question   The prompt text shown to the user.
  /// @param defaultValue  Optional default shown in brackets.
  /// @param validator  Optional function returning an error string or `null`.
  /// @return The user's answer, trimmed.
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  });

  /// Ask a yes/no question and return the boolean result.
  ///
  /// Accepts `y`/`yes`/`n`/`no` (case-insensitive) or ENTER for the default.
  ///
  /// @param question      The prompt text shown to the user.
  /// @param defaultValue  The answer used when the user presses ENTER.
  /// @return `true` for yes, `false` for no.
  bool confirm(String question, {bool defaultValue = false});

  /// Ask the user to pick one option from a closed list.
  ///
  /// Accepts the 1-based index OR the option string itself.
  ///
  /// @param question      The prompt text shown above the option list.
  /// @param options       Non-empty list of valid choices.
  /// @param defaultValue  The option returned when the user presses ENTER.
  /// @return The chosen option string.
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  });

  /// Ask a question while hiding typed characters (passwords, tokens).
  ///
  /// Falls back to plain [ask] when stdin is not a TTY.
  ///
  /// @param question  The prompt text shown to the user.
  /// @return The entered secret string.
  String secret(String question);
}

/// Production [PromptDriver] that delegates every call to the static [Prompt]
/// class.
///
/// Uses [Prompt.testOverride] so tests can inject answers without subclassing
/// this driver. For pure unit tests that need finer control, prefer a
/// `FakePromptDriver` (defined in the test file, not exported from `lib/`).
///
/// ## Usage
///
/// ```dart
/// final driver = RealPromptDriver();
/// final answer = driver.ask('Project name?');
/// ```
class RealPromptDriver implements PromptDriver {
  /// Creates a [RealPromptDriver].
  const RealPromptDriver();

  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) =>
      Prompt.ask(question, defaultValue: defaultValue, validator: validator);

  @override
  bool confirm(String question, {bool defaultValue = false}) =>
      Prompt.confirm(question, defaultValue: defaultValue);

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) =>
      Prompt.choice(question, options: options, defaultValue: defaultValue);

  @override
  String secret(String question) => Prompt.secret(question);
}
