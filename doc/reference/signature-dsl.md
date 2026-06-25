# Signature DSL

The signature DSL compresses a command's name, positional arguments, and
options into a single Dart string. `CommandSignature.parse`
(`lib/src/console/command_signature.dart:57`) splits that string at
registration time; the registry applies it to the underlying `ArgParser`.

---

## Contents

- [Overview](#overview)
- [Grammar](#grammar)
- [Token Types](#token-types)
- [Argument Modifiers](#argument-modifiers)
- [Option Modifiers](#option-modifiers)
- [Description Annotation](#description-annotation)
- [Name Validation](#name-validation)
- [Error Handling](#error-handling)
- [Examples](#examples)
- [Related](#related)

---

<a name="overview"></a>
## Overview

```dart
String get signature => 'cmd:name {arg} {arg?} {arg=default} {--flag} {--option=val}';
```

The signature string is the primary way to declare a command's surface. The
alternative is `configure(ArgParser)`, used when the DSL cannot express the
required structure (multi-allowed options, allowed-values lists).

Of the 21 built-in commands: **6** use the signature DSL, **5** use
`configure(ArgParser)` with flags, **10** have no flag surface.

---

<a name="grammar"></a>
## Grammar

```
signature  := name (whitespace token)*
name       := lowercase with optional colon-separated namespace
token      := '{' (argument | option) '}'
argument   := name [modifier] [' : ' description]
option     := '--' name [value-spec] [' : ' description]
modifier   := '?' | '*' | '?*' | '=' default
value-spec := '=' | '=' default
```

`CommandSignature.parse` (`command_signature.dart:57`) runs four stages:

1. **Extract name** (`command_signature.dart:65`): split on the first
   whitespace or `{` via `RegExp(r'[\s{]')`; everything before is the name.
2. **Extract token blocks** (`command_signature.dart:82`): scan the tail with
   `RegExp(r'\{([^}]+)\}')`; each capture is one token body.
3. **Classify each token** (`command_signature.dart:86`): bodies starting
   with `--` route to `_parseOption`; others route to `_parseArgument`.
4. **Parse modifiers**: arguments check `=` first (default value), then
   suffix `?*` / `*` / `?`. Options check `=` to distinguish a value option
   from a boolean flag.

A ` : ` separator (`RegExp(r'\s+:\s+')`, `command_signature.dart:218`)
strips the description annotation before modifier parsing in both branches.

---

<a name="token-types"></a>
## Token Types

| Token form | Type | Read via |
|---|---|---|
| `{name}` | Positional argument | `ctx.input.argument('name')` |
| `{--name}` | Boolean flag | `ctx.input.flag('name')` |
| `{--name=}` | Value option, no default | `ctx.input.option('name')` |
| `{--name=default}` | Value option with default | `ctx.input.option('name')` |

---

<a name="argument-modifiers"></a>
## Argument Modifiers

| Syntax | `isOptional` | `isVariadic` | `defaultValue` | Behaviour |
|---|---|---|---|---|
| `{name}` | false | false | null | Required positional. |
| `{name?}` | true | false | null | Optional; `argument()` returns null when absent. |
| `{name=default}` | true | false | `"default"` | Inline default; implies optional. |
| `{name*}` | false | true | null | Variadic, one or more trailing values. |
| `{name?*}` | true | true | null | Optional variadic, zero or more. |

Modifiers are parsed in declaration order (`command_signature.dart:125`):
`=` check first, then suffix `?*` before `*` before `?`.

---

<a name="option-modifiers"></a>
## Option Modifiers

| Syntax | `isFlag` | `defaultValue` | Behaviour |
|---|---|---|---|
| `{--flag}` | true | null | Boolean switch; absent means false. |
| `{--option=}` | false | null | Value option; `option()` returns null when absent. |
| `{--option=value}` | false | `"value"` | Value option with inline default. |

`CommandSignature.applyTo` (`command_signature.dart:103`) calls
`parser.addFlag` (with `negatable: false`) for booleans and
`parser.addOption(defaultsTo: opt.defaultValue)` for value options.

---

<a name="description-annotation"></a>
## Description Annotation

Append ` : text` after a token's name and modifiers to attach a description:

```
{name : Argument description}
{--flag : Boolean flag description}
{--option=default : Value option description}
```

`_splitDescription` (`command_signature.dart:205`) matches the first
`\s+:\s+` in the body and returns `(head, description)`. The `description`
flows into `ArgParser` as `help` for options and flags; for arguments it is
stored on `ArgumentSpec` for introspection.

---

<a name="name-validation"></a>
## Name Validation

Both patterns are defined in `command_signature.dart:214-216`.

**Command name** (`_namePattern`):
```
^[a-z0-9_]+([:-][a-z0-9_]+)*$
```
Allows colon-namespaced or hyphen-namespaced segments (e.g. `plugin:install`,
`sync-monitors`). Uppercase, dots, or consecutive separators throw.

**Argument and option names** (`_argNamePattern`):
```
^[a-z0-9][a-z0-9_-]*$
```
Must start with a lowercase letter or digit; subsequent characters may
include underscores and hyphens. Both patterns throw `FormatException` at
parse time with the invalid value and expected pattern quoted in the message.

---

<a name="error-handling"></a>
## Error Handling

When a command is invoked with an option the parser does not recognize, the
dispatcher fails loudly: it writes `Unknown option: <flag>` to stderr, prints
the command help, and exits with a non-zero code. This applies to both long
(`--unknown`) and short (`-x`) forms.

```
$ artisan make:command Foo --bogus
✗ Unknown option: --bogus
ℹ Description:
  ...
```

Every other parse failure keeps its original, specific message:

| Cause | Example invocation | Message |
|-------|--------------------|---------|
| Unknown option | `--bogus`, `-x` | `Unknown option: <flag>` |
| Missing option value | `--output` (value required) | `Missing argument for "--output".` |
| Disallowed value | `--mode=zoom` (not in `allowed`) | `"zoom" is not an allowed value for option "--mode".` |
| Value on a flag | `--force=1` | `Flag option "--force" should not be given a value.` |

`--help` / `-h` and every valid invocation are unaffected: they parse and
behave exactly as before.

---

<a name="examples"></a>
## Examples

### tinker (`lib/src/commands/tinker_command.dart:22`)

```dart
String get signature => 'tinker '
    '{--eval= : Evaluate a single Dart expression in the running app, '
    'print the formatted result on stdout, and exit. Pipe-friendly.}';
```

`CommandSignature` result: name `tinker`, no arguments, one value option
`eval` (`isFlag: false`, `defaultValue: null`). `ctx.input.option('eval')`
returns `null` in REPL mode and the expression string when `--eval` is set.

---

### plugin:install (`lib/src/commands/plugin_install_command.dart:67`)

```dart
String get signature => 'plugin:install '
    '$baseFlags'
    '{name : Plugin pubspec package name (e.g. magic_logger)} '
    '{--provider= : Override the auto-derived provider class name} '
    '{--bootstrap-command= : Sub-command to chain after registration} '
    '{--use-yaml-only : Fail if install.yaml not found}';
```

`CommandSignature` result: name `plugin:install`, one required positional
argument `name`, three own options (`provider` value, `bootstrap-command`
value, `use-yaml-only` flag), plus the options from `baseFlags` expansion.

---

### plugin:uninstall (`lib/src/commands/plugin_uninstall_command.dart:54`)

```dart
String get signature => 'plugin:uninstall '
    '$baseFlags'
    '{name : Plugin pubspec package name}';
```

`CommandSignature` result: name `plugin:uninstall`, one required positional
argument `name`, no own options beyond those from `baseFlags` expansion.

---

<a name="related"></a>
## Related

- [`../commands/`](../commands/): per-command reference with full signature
  listings and usage examples.
