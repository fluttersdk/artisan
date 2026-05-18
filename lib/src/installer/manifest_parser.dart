/// YAML → typed [InstallManifest] parser + schema validator.
///
/// The parser is the front-line schema-error surface for plugin authors. It
/// MUST produce actionable error messages because every install.yaml mistake
/// downstream of validation cascades into hard-to-trace dispatcher failures.
///
/// Validation rules (Step 27):
/// - `plugin_name` is present, non-empty, matches `^[a-z_][a-z0-9_]*$`.
/// - Every `prompts[*].key` is unique.
/// - Every `placeholders[*]` value's `{{ prompts.X }}` references resolve.
/// - `magic.provider`, when present, matches `^[A-Z][A-Za-z0-9]*$`.
///
/// All failures throw [ManifestValidationException] (subclass of
/// [InstallException]). Raw YAML parse errors (malformed input) bubble up as
/// [FormatException] so callers can distinguish "syntax broken" from "schema
/// violated".
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'install_exception.dart';
import 'install_manifest.dart';

/// Static parser: reads YAML text, returns a validated [InstallManifest].
class ManifestParser {
  /// Validation regex for `plugin_name`. Matches a Dart/pubspec package name:
  /// starts with lowercase or underscore, followed by lowercase, digits, or
  /// underscores.
  static final RegExp _pluginNameRegex = RegExp(r'^[a-z_][a-z0-9_]*$');

  /// Validation regex for `magic.provider`. PascalCase identifier.
  static final RegExp _providerNameRegex = RegExp(r'^[A-Z][A-Za-z0-9]*$');

  /// Match `{{ prompts.KEY }}` references inside placeholder values. Allows
  /// any whitespace around the dotted reference so authors can use either
  /// `{{prompts.x}}` or `{{ prompts.x }}` per taste.
  static final RegExp _promptRefRegex =
      RegExp(r'\{\{\s*prompts\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}');

  /// Private to disable instantiation; the class is a static namespace.
  const ManifestParser._();

  /// Reads the file at [yamlPath] and delegates to [parseString].
  ///
  /// @param yamlPath  Filesystem path to an `install.yaml` file.
  /// @return The parsed + validated [InstallManifest].
  /// @throws FileSystemException  When [yamlPath] does not exist.
  /// @throws FormatException  When the YAML body is syntactically invalid.
  /// @throws ManifestValidationException  When the schema validation fails.
  static InstallManifest parseFile(String yamlPath) {
    final content = File(yamlPath).readAsStringSync();
    return parseString(content);
  }

  /// Parses [yamlContent], builds the typed model, and runs [validate]
  /// before returning.
  ///
  /// @param yamlContent  The raw `install.yaml` text.
  /// @return The parsed + validated [InstallManifest].
  /// @throws FormatException  When the YAML body is syntactically invalid.
  /// @throws ManifestValidationException  When the schema validation fails.
  static InstallManifest parseString(String yamlContent) {
    // 1. Parse the YAML. The yaml package throws YamlException on broken
    //    input; rewrap as FormatException so callers do not need to depend on
    //    the yaml package's exception type.
    final dynamic raw;
    try {
      raw = loadYaml(yamlContent);
    } on YamlException catch (e) {
      throw FormatException('install.yaml is not valid YAML: $e');
    }

    // 2. The root MUST be a map. Scalars / lists at the top level are a
    //    schema violation, not a syntax one, so use ManifestValidationException.
    if (raw is! YamlMap) {
      throw ManifestValidationException(
        'install.yaml root must be a map; got ${raw.runtimeType}.',
      );
    }

    // 3. Build the typed model. Each section factory tolerates absence and
    //    returns a sensible empty default so partial manifests parse cleanly.
    final manifest = _build(raw);

    // 4. Run the schema validations. Any failure throws and the caller never
    //    receives a partially-validated manifest.
    validate(manifest);

    return manifest;
  }

  /// Runs schema-level validations against the already-parsed [manifest].
  ///
  /// @param manifest  The parsed [InstallManifest].
  /// @throws ManifestValidationException  When any validation rule fails.
  static void validate(InstallManifest manifest) {
    _validatePluginName(manifest.pluginName);
    _validatePromptKeysUnique(manifest.prompts);
    _validatePlaceholderReferences(manifest.placeholders, manifest.prompts);
    _validateProviderName(manifest.magic.provider);
  }

  // ---------------------------------------------------------------------------
  // Build helpers
  // ---------------------------------------------------------------------------

  /// Builds the typed [InstallManifest] from a raw [YamlMap]. Each section is
  /// defaulted to an empty payload when absent.
  static InstallManifest _build(YamlMap root) {
    final pluginNameRaw = root['plugin_name'];
    if (pluginNameRaw is! String) {
      // The downstream validator catches the missing case too, but raising
      // here means the typed model never carries an empty plugin_name even
      // momentarily.
      throw ManifestValidationException(
        'install.yaml requires a top-level "plugin_name" string.',
      );
    }

    return InstallManifest(
      pluginName: pluginNameRaw,
      pubspec: root['dependencies'] is YamlMap
          ? PubspecDeps.fromYaml(root['dependencies'])
          : PubspecDeps.empty(),
      publish: _publishMap(root['publish']),
      jsonMerge: _jsonMergeMap(root['json_merge']),
      magic: root['magic'] is YamlMap
          ? MagicIntegration.fromYaml(root['magic'])
          : MagicIntegration.empty(),
      native: root['native'] is YamlMap
          ? NativeConfig.fromYaml(root['native'])
          : NativeConfig.empty(),
      env: _envMap(root['env']),
      prompts: _promptList(root['prompts']),
      placeholders: _placeholdersMap(root['placeholders']),
      postInstall: root['post_install'] is YamlMap
          ? PostInstallSpec.fromYaml(root['post_install'])
          : PostInstallSpec.empty(),
      bootstrapCommand: root['bootstrap_command'] is String
          ? root['bootstrap_command'] as String
          : null,
    );
  }

  /// Parses the `publish:` map into a `<stubName, targetPath>` map.
  static Map<String, String> _publishMap(Object? raw) {
    if (raw is! YamlMap) return <String, String>{};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k == null) return;
      if (v is! String) {
        throw FormatException(
          'publish entry "$k" must map to a String target path; '
          'got ${v.runtimeType}.',
        );
      }
      out[k.toString()] = v;
    });
    return out;
  }

  /// Parses the `json_merge:` map into typed [JsonMergeSpec]s.
  static Map<String, JsonMergeSpec> _jsonMergeMap(Object? raw) {
    if (raw is! YamlMap) return <String, JsonMergeSpec>{};
    final out = <String, JsonMergeSpec>{};
    raw.forEach((k, v) {
      if (k == null) return;
      if (v is! YamlMap) {
        throw FormatException(
          'json_merge entry "$k" must be a map with "source" + optional '
          '"additive"; got ${v.runtimeType}.',
        );
      }
      out[k.toString()] = JsonMergeSpec.fromYaml(v);
    });
    return out;
  }

  /// Parses the `env:` map into typed [EnvVarSpec]s.
  static Map<String, EnvVarSpec> _envMap(Object? raw) {
    if (raw is! YamlMap) return <String, EnvVarSpec>{};
    final out = <String, EnvVarSpec>{};
    raw.forEach((k, v) {
      if (k == null) return;
      if (v is! YamlMap) {
        throw FormatException(
          'env entry "$k" must be a map with "default" + optional '
          '"comment"; got ${v.runtimeType}.',
        );
      }
      out[k.toString()] = EnvVarSpec.fromYaml(v);
    });
    return out;
  }

  /// Parses the `prompts:` list into typed [PromptSpec]s.
  static List<PromptSpec> _promptList(Object? raw) {
    if (raw is! YamlList) return const <PromptSpec>[];
    final out = <PromptSpec>[];
    for (final entry in raw) {
      if (entry is! YamlMap) {
        throw FormatException(
          'prompts entries must be maps with "key" + "type" + "question"; '
          'got ${entry.runtimeType}.',
        );
      }
      out.add(PromptSpec.fromYaml(entry));
    }
    return out;
  }

  /// Parses the `placeholders:` map into a `<key, template>` map.
  static Map<String, String> _placeholdersMap(Object? raw) {
    if (raw is! YamlMap) return <String, String>{};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k == null) return;
      out[k.toString()] = v?.toString() ?? '';
    });
    return out;
  }

  // ---------------------------------------------------------------------------
  // Validation helpers
  // ---------------------------------------------------------------------------

  static void _validatePluginName(String name) {
    if (name.isEmpty) {
      throw const ManifestValidationException(
        'plugin_name must not be empty.',
      );
    }
    if (!_pluginNameRegex.hasMatch(name)) {
      throw ManifestValidationException(
        'plugin_name "$name" does not match required regex '
        '${_pluginNameRegex.pattern}.',
      );
    }
  }

  static void _validatePromptKeysUnique(List<PromptSpec> prompts) {
    final seen = <String>{};
    for (final prompt in prompts) {
      if (!seen.add(prompt.key)) {
        throw ManifestValidationException(
          'Duplicate prompt key "${prompt.key}" in prompts list.',
        );
      }
    }
  }

  static void _validatePlaceholderReferences(
    Map<String, String> placeholders,
    List<PromptSpec> prompts,
  ) {
    final promptKeys = prompts.map((p) => p.key).toSet();
    placeholders.forEach((placeholderKey, template) {
      for (final match in _promptRefRegex.allMatches(template)) {
        final referenced = match.group(1)!;
        if (!promptKeys.contains(referenced)) {
          throw ManifestValidationException(
            'Placeholder "$placeholderKey" references unknown prompt key '
            '"$referenced".',
          );
        }
      }
    });
  }

  static void _validateProviderName(String? provider) {
    if (provider == null) return;
    if (!_providerNameRegex.hasMatch(provider)) {
      throw ManifestValidationException(
        'magic.provider "$provider" does not match PascalCase regex '
        '${_providerNameRegex.pattern}.',
      );
    }
  }
}
