/// Typed model layer for the `install.yaml` plugin manifest (schema v1).
///
/// `InstallManifest` is the parsed, validated, strongly-typed shape of an
/// `install.yaml` file. `ManifestParser` produces it; `ManifestInstaller`
/// consumes it. The model is intentionally inert: every field is `final`, no
/// method touches I/O, and every nested class exposes a `fromYaml(YamlMap m)`
/// factory that returns sensible empty defaults when its section is absent.
///
/// The schema is documented in full at `doc/install_yaml_schema.md`. Sample
/// manifests live under `doc/samples/`.
library;

import 'package:yaml/yaml.dart';

/// Root manifest carrying every section a plugin can declare.
///
/// Every field except [pluginName] has a sensible empty default so partial
/// manifests parse without raising. `final` everywhere so the model is
/// effectively immutable post-construction.
class InstallManifest {
  /// Plugin pubspec package name. MUST match `^[a-z_][a-z0-9_]*$`.
  final String pluginName;

  /// Pubspec dependencies (runtime + dev + asset paths).
  final PubspecDeps pubspec;

  /// Map of `stub_name` → `target_path` for `publishConfig` translation.
  final Map<String, String> publish;

  /// Map of `target_path` → `JsonMergeSpec` for `mergeJson` translation.
  final Map<String, JsonMergeSpec> jsonMerge;

  /// Magic-framework integration slots (provider / config_factory / routes).
  final MagicIntegration magic;

  /// Per-platform native configuration (android / ios / macos / web).
  final NativeConfig native;

  /// Environment variables to inject into `.env`.
  final Map<String, EnvVarSpec> env;

  /// Ordered list of prompts driven IMMEDIATELY at the start of install.
  final List<PromptSpec> prompts;

  /// Map of placeholder key → value template. Values may reference prompt
  /// answers via `{{ prompts.KEY }}` (with optional surrounding whitespace).
  final Map<String, String> placeholders;

  /// Post-install shell ops + final info message.
  final PostInstallSpec postInstall;

  /// Optional plugin-specific bootstrap command name run after a Success.
  final String? bootstrapCommand;

  /// Creates an [InstallManifest] with every section already typed and
  /// defaulted.
  const InstallManifest({
    required this.pluginName,
    required this.pubspec,
    required this.publish,
    required this.jsonMerge,
    required this.magic,
    required this.native,
    required this.env,
    required this.prompts,
    required this.placeholders,
    required this.postInstall,
    this.bootstrapCommand,
  });
}

/// Pubspec dependency section: `dependencies` / `dev_dependencies` / asset
/// paths to append under `flutter.assets`.
class PubspecDeps {
  /// `dependencies:` map (package name → version constraint).
  final Map<String, String> deps;

  /// `dev_dependencies:` map (package name → version constraint).
  final Map<String, String> devDeps;

  /// Asset paths to append under `flutter.assets`.
  final List<String> assets;

  /// Creates a [PubspecDeps] payload.
  const PubspecDeps({
    required this.deps,
    required this.devDeps,
    required this.assets,
  });

  /// Empty payload used when the `dependencies:` section is absent.
  factory PubspecDeps.empty() => const PubspecDeps(
        deps: <String, String>{},
        devDeps: <String, String>{},
        assets: <String>[],
      );

  /// Parses the `dependencies:` sub-map. Tolerates missing nested keys.
  factory PubspecDeps.fromYaml(YamlMap m) {
    return PubspecDeps(
      deps: _stringMap(m['pubspec']),
      devDeps: _stringMap(m['dev_pubspec']),
      assets: _stringList(m['pubspec_assets']),
    );
  }
}

/// JSON merge spec: where to read the source from + whether existing keys
/// survive a collision.
class JsonMergeSpec {
  /// Stub key whose content is parsed as JSON.
  final String source;

  /// When `true` (default), existing keys in the target file survive.
  final bool additive;

  /// Creates a [JsonMergeSpec].
  const JsonMergeSpec({required this.source, this.additive = true});

  /// Parses one entry under the `json_merge:` map.
  factory JsonMergeSpec.fromYaml(YamlMap m) {
    final source = m['source'];
    if (source is! String) {
      throw FormatException(
        'json_merge entry missing required "source" string.',
      );
    }
    final additive = m['additive'];
    return JsonMergeSpec(
      source: source,
      additive: additive is bool ? additive : true,
    );
  }
}

/// Magic-framework integration block. Every slot is optional.
class MagicIntegration {
  /// Provider class name. Translates to `injectProvider(provider)`.
  final String? provider;

  /// Config factory expression. Translates to `injectConfigFactory(name)`.
  final String? configFactory;

  /// Route registration function name. Translates to `injectRoute(name)`.
  final String? routes;

  /// Creates a [MagicIntegration].
  const MagicIntegration({this.provider, this.configFactory, this.routes});

  /// Empty integration used when the `magic:` section is absent.
  factory MagicIntegration.empty() => const MagicIntegration();

  /// Parses the `magic:` sub-map.
  factory MagicIntegration.fromYaml(YamlMap m) {
    return MagicIntegration(
      provider: m['provider'] is String ? m['provider'] as String : null,
      configFactory:
          m['config_factory'] is String ? m['config_factory'] as String : null,
      routes: m['routes'] is String ? m['routes'] as String : null,
    );
  }
}

/// Per-platform native configuration. Each slot is independently optional.
class NativeConfig {
  /// Android sub-section (permissions / meta_data / gradle).
  final AndroidConfig? android;

  /// iOS sub-section (info_plist / entitlements / podfile).
  final IosConfig? ios;

  /// macOS sub-section (same shape as iOS).
  final MacosConfig? macos;

  /// Web sub-section (head_scripts / meta_tags).
  final WebConfig? web;

  /// Creates a [NativeConfig].
  const NativeConfig({this.android, this.ios, this.macos, this.web});

  /// Empty payload used when the `native:` section is absent.
  factory NativeConfig.empty() => const NativeConfig();

  /// Parses the `native:` sub-map.
  factory NativeConfig.fromYaml(YamlMap m) {
    return NativeConfig(
      android:
          m['android'] is YamlMap ? AndroidConfig.fromYaml(m['android']) : null,
      ios: m['ios'] is YamlMap ? IosConfig.fromYaml(m['ios']) : null,
      macos: m['macos'] is YamlMap ? MacosConfig.fromYaml(m['macos']) : null,
      web: m['web'] is YamlMap ? WebConfig.fromYaml(m['web']) : null,
    );
  }
}

/// Android native configuration sub-section.
class AndroidConfig {
  /// Permissions to add under `<uses-permission>`.
  final List<String> permissions;

  /// `<meta-data>` entries (name → value).
  final Map<String, String> metaData;

  /// Optional Gradle plugins + dependencies block.
  final GradleConfig? gradle;

  /// Creates an [AndroidConfig].
  const AndroidConfig({
    required this.permissions,
    required this.metaData,
    this.gradle,
  });

  /// Parses the `native.android:` sub-map.
  factory AndroidConfig.fromYaml(YamlMap m) {
    return AndroidConfig(
      permissions: _stringList(m['permissions']),
      metaData: _stringMap(m['meta_data']),
      gradle:
          m['gradle'] is YamlMap ? GradleConfig.fromYaml(m['gradle']) : null,
    );
  }
}

/// Gradle plugins + dependencies block (lives under `native.android.gradle`).
class GradleConfig {
  /// Gradle plugins (id + optional version).
  final List<GradlePluginSpec> plugins;

  /// Gradle dependencies (scope + Maven notation).
  final List<GradleDepSpec> deps;

  /// Creates a [GradleConfig].
  const GradleConfig({required this.plugins, required this.deps});

  /// Parses the `gradle:` sub-map.
  factory GradleConfig.fromYaml(YamlMap m) {
    return GradleConfig(
      plugins: _mapList(m['plugins'], GradlePluginSpec.fromYaml),
      deps: _mapList(m['dependencies'], GradleDepSpec.fromYaml),
    );
  }
}

/// One Gradle plugin entry: `{id, version?}`.
class GradlePluginSpec {
  /// Gradle plugin id (e.g. `com.google.gms.google-services`).
  final String id;

  /// Optional version constraint.
  final String? version;

  /// Creates a [GradlePluginSpec].
  const GradlePluginSpec({required this.id, this.version});

  /// Parses one plugin entry.
  factory GradlePluginSpec.fromYaml(YamlMap m) {
    final id = m['id'];
    if (id is! String) {
      throw FormatException('Gradle plugin missing required "id".');
    }
    return GradlePluginSpec(
      id: id,
      version: m['version'] is String ? m['version'] as String : null,
    );
  }
}

/// One Gradle dependency entry: `{scope, notation}`.
class GradleDepSpec {
  /// Gradle scope (`implementation`, `classpath`, ...).
  final String scope;

  /// Maven coordinate notation.
  final String notation;

  /// Creates a [GradleDepSpec].
  const GradleDepSpec({required this.scope, required this.notation});

  /// Parses one Gradle dependency entry.
  factory GradleDepSpec.fromYaml(YamlMap m) {
    final scope = m['scope'];
    final notation = m['notation'];
    if (scope is! String || notation is! String) {
      throw FormatException(
        'Gradle dependency entry requires both "scope" and "notation".',
      );
    }
    return GradleDepSpec(scope: scope, notation: notation);
  }
}

/// iOS native configuration sub-section.
///
/// The plist `value` field stays typed as [Object] because Info.plist allows
/// String, bool, num, and List values. The downstream dispatcher branches on
/// runtime type.
class IosConfig {
  /// Info.plist key → value map. Values may be String / bool / num / List.
  final Map<String, Object> infoPlist;

  /// Entitlements key → value map.
  final Map<String, Object> entitlements;

  /// Optional Podfile block.
  final PodfileConfig? podfile;

  /// Creates an [IosConfig].
  const IosConfig({
    required this.infoPlist,
    required this.entitlements,
    this.podfile,
  });

  /// Parses the `native.ios:` sub-map.
  factory IosConfig.fromYaml(YamlMap m) {
    return IosConfig(
      infoPlist: _objectMap(m['info_plist']),
      entitlements: _objectMap(m['entitlements']),
      podfile:
          m['podfile'] is YamlMap ? PodfileConfig.fromYaml(m['podfile']) : null,
    );
  }
}

/// macOS native configuration sub-section. Shape mirrors [IosConfig].
class MacosConfig {
  /// Info.plist key → value map.
  final Map<String, Object> infoPlist;

  /// Entitlements key → value map.
  final Map<String, Object> entitlements;

  /// Optional Podfile block.
  final PodfileConfig? podfile;

  /// Creates a [MacosConfig].
  const MacosConfig({
    required this.infoPlist,
    required this.entitlements,
    this.podfile,
  });

  /// Parses the `native.macos:` sub-map.
  factory MacosConfig.fromYaml(YamlMap m) {
    return MacosConfig(
      infoPlist: _objectMap(m['info_plist']),
      entitlements: _objectMap(m['entitlements']),
      podfile:
          m['podfile'] is YamlMap ? PodfileConfig.fromYaml(m['podfile']) : null,
    );
  }
}

/// Podfile sub-block (under `native.ios.podfile` or `native.macos.podfile`).
class PodfileConfig {
  /// Optional `platform :ios` (or `:osx`) minimum version. Informational in
  /// v1: no chain method consumes it yet.
  final String? platformVersion;

  /// Pod declarations to append to `target 'Runner'`.
  final List<String> pods;

  /// Creates a [PodfileConfig].
  const PodfileConfig({this.platformVersion, required this.pods});

  /// Parses the `podfile:` sub-map.
  factory PodfileConfig.fromYaml(YamlMap m) {
    return PodfileConfig(
      platformVersion: m['platform_version'] is String
          ? m['platform_version'] as String
          : null,
      pods: _stringList(m['pods']),
    );
  }
}

/// Web native configuration sub-section.
class WebConfig {
  /// HTML snippets to inject before `</head>`.
  final List<String> headScripts;

  /// `<meta>` attribute maps to add to `web/index.html`.
  final List<Map<String, String>> metaTags;

  /// Creates a [WebConfig].
  const WebConfig({required this.headScripts, required this.metaTags});

  /// Parses the `native.web:` sub-map.
  factory WebConfig.fromYaml(YamlMap m) {
    final tags = <Map<String, String>>[];
    final raw = m['meta_tags'];
    if (raw is YamlList) {
      for (final entry in raw) {
        if (entry is YamlMap) {
          tags.add(_stringMap(entry));
        }
      }
    }
    return WebConfig(
      headScripts: _stringList(m['head_scripts']),
      metaTags: tags,
    );
  }
}

/// One env var spec: `{default, comment?}`.
class EnvVarSpec {
  /// Default value to write into `.env`.
  final String defaultValue;

  /// Optional documentation comment (currently advisory; the v1 dispatcher
  /// does not emit it into the `.env` file).
  final String? comment;

  /// Creates an [EnvVarSpec].
  const EnvVarSpec({required this.defaultValue, this.comment});

  /// Parses one entry under the `env:` map.
  factory EnvVarSpec.fromYaml(YamlMap m) {
    final dv = m['default'];
    if (dv == null) {
      throw FormatException('env entry missing required "default".');
    }
    return EnvVarSpec(
      defaultValue: dv.toString(),
      comment: m['comment'] is String ? m['comment'] as String : null,
    );
  }
}

/// One prompt spec: `{key, type, default?, options?, question}`.
class PromptSpec {
  /// Unique key used to store the answer in the prompt-result map.
  final String key;

  /// One of `string` / `bool` / `choice`.
  final String type;

  /// Default value shown in brackets. Stored as a String regardless of [type]
  /// so the placeholder substitution layer has a uniform shape.
  final String? defaultValue;

  /// For `choice` prompts: the list of valid options. Empty otherwise.
  final List<String> options;

  /// Human-readable question text shown at the prompt.
  final String question;

  /// Creates a [PromptSpec].
  const PromptSpec({
    required this.key,
    required this.type,
    required this.question,
    this.defaultValue,
    this.options = const <String>[],
  });

  /// Parses one entry under the `prompts:` list.
  factory PromptSpec.fromYaml(YamlMap m) {
    final key = m['key'];
    final type = m['type'];
    final question = m['question'];
    if (key is! String || type is! String || question is! String) {
      throw FormatException(
        'Prompt entry requires "key", "type", and "question" strings.',
      );
    }

    final defaultRaw = m['default'];
    final defaultValue = defaultRaw?.toString();

    final options = <String>[];
    final rawOptions = m['options'];
    if (rawOptions is YamlList) {
      for (final entry in rawOptions) {
        options.add(entry.toString());
      }
    }

    return PromptSpec(
      key: key,
      type: type,
      question: question,
      defaultValue: defaultValue,
      options: options,
    );
  }
}

/// Post-install shell + message block.
class PostInstallSpec {
  /// Shell commands run unconditionally at commit phase.
  final List<ShellSpec> run;

  /// Shell commands run only after user confirmation. The prompt fires
  /// IMMEDIATELY at install time; on yes the shell call is deferred.
  final List<AskToRunSpec> askToRun;

  /// Optional info message emitted after a Success.
  final String? message;

  /// Creates a [PostInstallSpec].
  const PostInstallSpec({
    required this.run,
    required this.askToRun,
    this.message,
  });

  /// Empty post-install block used when the section is absent.
  factory PostInstallSpec.empty() => const PostInstallSpec(
        run: <ShellSpec>[],
        askToRun: <AskToRunSpec>[],
      );

  /// Parses the `post_install:` sub-map.
  factory PostInstallSpec.fromYaml(YamlMap m) {
    return PostInstallSpec(
      run: _mapList(m['run'], ShellSpec.fromYaml),
      askToRun: _mapList(m['ask_to_run'], AskToRunSpec.fromYaml),
      message: m['message'] is String ? m['message'] as String : null,
    );
  }
}

/// One unconditional shell command spec.
class ShellSpec {
  /// Executable name (no shell quoting applied by the dispatcher).
  final String cmd;

  /// Positional arguments.
  final List<String> args;

  /// Creates a [ShellSpec].
  const ShellSpec({required this.cmd, required this.args});

  /// Parses one entry under `post_install.run:`.
  factory ShellSpec.fromYaml(YamlMap m) {
    final cmd = m['cmd'];
    if (cmd is! String) {
      throw FormatException('Shell spec missing required "cmd".');
    }
    return ShellSpec(cmd: cmd, args: _stringList(m['args']));
  }
}

/// One ask-to-run shell command spec.
class AskToRunSpec {
  /// Confirmation question shown to the user.
  final String prompt;

  /// Executable name on yes.
  final String cmd;

  /// Positional arguments.
  final List<String> args;

  /// Creates an [AskToRunSpec].
  const AskToRunSpec({
    required this.prompt,
    required this.cmd,
    required this.args,
  });

  /// Parses one entry under `post_install.ask_to_run:`.
  factory AskToRunSpec.fromYaml(YamlMap m) {
    final prompt = m['prompt'];
    final cmd = m['cmd'];
    if (prompt is! String || cmd is! String) {
      throw FormatException(
        'ask_to_run entry requires "prompt" and "cmd" strings.',
      );
    }
    return AskToRunSpec(
      prompt: prompt,
      cmd: cmd,
      args: _stringList(m['args']),
    );
  }
}

// ---------------------------------------------------------------------------
// Coercion helpers (private to this file).
// ---------------------------------------------------------------------------

/// Coerces a YamlMap value into a `Map<String, String>`. Returns an empty
/// map when [raw] is null or not a map. Values are stringified via `toString`
/// so YAML scalars that arrived as bool / num still flow through unchanged.
Map<String, String> _stringMap(Object? raw) {
  if (raw is! YamlMap) return <String, String>{};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k != null) {
      out[k.toString()] = v?.toString() ?? '';
    }
  });
  return out;
}

/// Coerces a YamlMap value into a `Map<String, Object>` preserving raw
/// scalar / list values for downstream dispatcher branching on runtimeType
/// (used for plist + entitlement payloads).
Map<String, Object> _objectMap(Object? raw) {
  if (raw is! YamlMap) return <String, Object>{};
  final out = <String, Object>{};
  raw.forEach((k, v) {
    if (k == null || v == null) return;
    out[k.toString()] = v as Object;
  });
  return out;
}

/// Coerces a YamlList value into a `List<String>`. Returns an empty list
/// when [raw] is null or not a list.
List<String> _stringList(Object? raw) {
  if (raw is! YamlList) return const <String>[];
  return raw.map((entry) => entry.toString()).toList(growable: false);
}

/// Coerces a YamlList of YamlMaps into a typed list via [fromYaml]. Returns
/// an empty list when [raw] is absent. Non-map entries are silently skipped
/// so a stray comment or scalar does not break the parse.
List<T> _mapList<T>(Object? raw, T Function(YamlMap) fromYaml) {
  if (raw is! YamlList) return <T>[];
  final out = <T>[];
  for (final entry in raw) {
    if (entry is YamlMap) {
      out.add(fromYaml(entry));
    }
  }
  return out;
}
