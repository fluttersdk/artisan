/// Translation layer that maps an [InstallManifest] onto the
/// [PluginInstaller] chain methods and commits the result.
///
/// `ManifestInstaller` is the bridge between the declarative `install.yaml`
/// world (typed by Step 27 `ManifestParser`) and the imperative
/// `PluginInstaller` DSL (Wave 3). It walks the manifest sections in a fixed
/// order, drives prompts immediately, resolves placeholder templates, then
/// translates each section into the matching chain method.
///
/// ## Execution order
///
/// 1. `_runPrompts` (IMMEDIATE; before any chain method enqueues an op).
/// 2. `_resolvePlaceholders` (pure substitution, no I/O).
/// 3. `_applyPubspec`
/// 4. `_applyPublish`
/// 5. `_applyJsonMerge`
/// 6. `_applyMagic`
/// 7. `_applyNative`
/// 8. `_applyEnv`
/// 9. `_applyPostInstall`
/// 10. `installer.commit(dryRun: ..., force: ...)`
///
/// ## Uninstall semantics (v1 limitations)
///
/// `uninstall()` reads the install record at
/// `.artisan/installed/<pluginName>.json`, reconstructs each recorded op
/// from its persisted typed payload, replays through [reverseOf], and
/// commits a fresh [InstallTransaction] carrying the reverse ops. The
/// install record carries the full typed payload for every op subclass
/// (see [InstallTransaction._serializeOp]) so reconstruction is lossless
/// for `WriteFile` / `CopyFile` / `PublishFile`.
///
/// The current v1 trade-off lives in [reverseOf]: only file-creating ops
/// (`AddDependency` -> `RemoveDependency`, `WriteFile` / `CopyFile` /
/// `PublishFile` -> `DeleteFile`) have a typed reverse. Every other op
/// (`Inject*`, `AddPubspecAsset`, `MergeJson`, `RunShell`, ...) returns
/// null with a logged skip warning because the matching `removeX` editor
/// helpers do not yet exist. The Plugin Authoring Guide (Step 40) and the
/// `doc/install_yaml_schema.md` Uninstall section enumerate the limitation
/// per op type and what manual cleanup is required.
///
/// When the install record file is missing, `uninstall()` returns an `Error`
/// so the operator does not silently believe the plugin was removed.
///
/// ## Usage
///
/// ```dart
/// final manifest = ManifestParser.parseFile('install.yaml');
/// final installer = ManifestInstaller(
///   InstallContext.real(artisanCtx),
///   manifest,
///   promptOverrides: {'configPath': '/etc/example.conf'},
/// );
/// final result = await installer.install(dryRun: false, force: false);
/// ```
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'install_context.dart';
import 'install_manifest.dart';
import 'install_operation.dart';
import 'install_transaction.dart';
import 'plugin_installer.dart';

/// Bridges an [InstallManifest] onto a [PluginInstaller] chain + commits.
class ManifestInstaller {
  /// Creates a `ManifestInstaller` for [manifest] bound to [ctx].
  ///
  /// [promptOverrides] lets the CLI inject prompt answers ahead of time so
  /// `--path=/x --level=info` style flags can bypass the interactive prompt
  /// entirely. The map is keyed by prompt `key` (matching [PromptSpec.key]).
  ///
  /// @param ctx              The active [InstallContext].
  /// @param manifest         The parsed manifest produced by [ManifestParser].
  /// @param promptOverrides  Optional CLI-flag-supplied answers (key → value).
  ManifestInstaller(
    InstallContext ctx,
    InstallManifest manifest, {
    Map<String, String> promptOverrides = const <String, String>{},
  })  : _ctx = ctx,
        _manifest = manifest,
        _promptOverrides = Map<String, String>.unmodifiable(promptOverrides);

  final InstallContext _ctx;
  final InstallManifest _manifest;
  final Map<String, String> _promptOverrides;

  /// Match `{{ prompts.KEY }}` references inside placeholder values.
  static final RegExp _promptRefRegex =
      RegExp(r'\{\{\s*prompts\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Drives prompts, resolves placeholders, applies every manifest section,
  /// and commits the [PluginInstaller] transaction.
  ///
  /// @param dryRun          Forward to [PluginInstaller.commit].
  /// @param force           Forward to [PluginInstaller.commit].
  /// @param nonInteractive  When `true`, every prompt returns its default
  ///                        rather than calling the [PromptDriver].
  /// @return The [TransactionResult] from the underlying commit.
  Future<TransactionResult> install({
    bool dryRun = false,
    bool force = false,
    bool nonInteractive = false,
  }) async {
    final installer = prepare(nonInteractive: nonInteractive);
    final result = await installer.commit(dryRun: dryRun, force: force);

    // Echo the post-install message after a Success so the operator sees the
    // plugin author's banner text. Dry-run / Conflict / Error short-circuit
    // the message because the install did not actually land.
    if (result is Success && _manifest.postInstall.message != null) {
      _ctx.artisanContext.output.info(_manifest.postInstall.message!);
    }

    return result;
  }

  /// Builds the fully-staged [PluginInstaller] WITHOUT committing.
  ///
  /// Exposed primarily for tests so assertions can inspect
  /// `installer.pendingOps` without firing the underlying transaction. Also
  /// used internally by [install] which calls this then [PluginInstaller.commit].
  ///
  /// @param nonInteractive  When `true`, prompts fall back to their defaults.
  /// @return The wired [PluginInstaller] ready for commit.
  PluginInstaller prepare({bool nonInteractive = false}) {
    // 1. Drive prompts first. promptOverrides win; then defaults (when
    //    nonInteractive); otherwise the live PromptDriver answers.
    final promptResults = _runPrompts(nonInteractive: nonInteractive);

    // 2. Resolve placeholder templates. Pure string substitution; no I/O.
    final placeholders = _resolvePlaceholders(promptResults);

    // 3. Construct the installer + walk every section in fixed order. The
    //    decomposition keeps each section's translator under ~30 lines so the
    //    overall method stays under the 100-line cap mandated by the plan.
    final installer = PluginInstaller(_ctx, pluginName: _manifest.pluginName);
    _applyPubspec(installer);
    _applyPublish(installer, placeholders);
    _applyJsonMerge(installer);
    _applyMagic(installer);
    _applyNative(installer);
    _applyEnv(installer);
    _applyPostInstall(installer);

    return installer;
  }

  /// Reverses a recorded install by reading the install record file and
  /// replaying [reverseOf] against each recorded op.
  ///
  /// V1 limitation: only `WriteFile` / `DeleteFile` / `CopyFile` carry full
  /// payload in the record. Other op types surface as type-only markers; for
  /// those, this method logs a skip warning and continues.
  ///
  /// @param force  Forwarded to the reverse [InstallTransaction.commit].
  /// @return [Success] on a clean reverse, [Error] when the record file is
  ///         missing or the reverse transaction fails.
  Future<TransactionResult> uninstall({bool force = false}) async {
    final recordPath = _recordPath();
    if (!_ctx.fs.exists(recordPath)) {
      return Error(
        error: 'No install record at $recordPath; cannot derive an '
            'uninstall plan. Either the plugin was never installed via '
            'ManifestInstaller or the record was deleted manually.',
        rolledBack: false,
      );
    }

    // 1. Decode the record payload.
    final raw = _ctx.fs.readAsString(recordPath);
    final record = jsonDecode(raw);
    if (record is! Map<String, dynamic>) {
      return Error(
        error: 'Install record at $recordPath is not a JSON object.',
        rolledBack: false,
      );
    }
    final opsRaw = record['ops'];
    if (opsRaw is! List) {
      return Error(
        error: 'Install record at $recordPath has no "ops" array.',
        rolledBack: false,
      );
    }

    // 2. Replay each recorded op through reverseOf. Type-only records map to
    //    null + a skip warning; full-payload records map to a typed reverse.
    final reverseOps = <InstallOperation>[];
    final skipped = <String>[];
    for (final entry in opsRaw) {
      if (entry is! Map) {
        skipped.add('non-map entry');
        continue;
      }
      final reconstructed = _opFromRecord(entry);
      if (reconstructed == null) {
        skipped.add('${entry['type']} (no payload in record)');
        continue;
      }
      final reverse = reverseOf(reconstructed);
      if (reverse == null) {
        skipped.add('${reconstructed.runtimeType} (no reverse possible)');
        continue;
      }
      reverseOps.add(reverse);
    }

    if (skipped.isNotEmpty) {
      _ctx.artisanContext.output.warning(
        'ManifestInstaller.uninstall: skipped ${skipped.length} op(s) without '
        'a clean reverse: ${skipped.join(', ')}. The Plugin Authoring Guide '
        'lists the V1 limitations.',
      );
    }

    // 3. Commit the reverse ops via a fresh InstallTransaction. We bypass the
    //    high-level PluginInstaller chain methods because we already have a
    //    list of typed InstallOperations to dispatch.
    final tx = InstallTransaction(_ctx, pluginName: _manifest.pluginName);
    for (final op in reverseOps) {
      tx.stage(op);
    }
    final result = await tx.commit(force: force);

    // 4. On Success, drop the install record so re-install starts clean.
    if (result is Success) {
      _ctx.fs.delete(recordPath);
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Section translators (one per manifest section)
  // ---------------------------------------------------------------------------

  void _applyPubspec(PluginInstaller installer) {
    _manifest.pubspec.deps.forEach((name, version) {
      installer.addDependency(name, version);
    });
    _manifest.pubspec.devDeps.forEach((name, version) {
      installer.addDevDependency(name, version);
    });
    for (final asset in _manifest.pubspec.assets) {
      installer.addPubspecAsset(asset);
    }
  }

  void _applyPublish(
    PluginInstaller installer,
    Map<String, String> placeholders,
  ) {
    _manifest.publish.forEach((stubName, targetPath) {
      installer.publishConfig(
        stubName: stubName,
        targetPath: targetPath,
        replacements: placeholders,
      );
    });
  }

  void _applyJsonMerge(PluginInstaller installer) {
    _manifest.jsonMerge.forEach((targetPath, spec) {
      // Load the stub data NOW (synchronously through the StubDriver) so the
      // parsed Map<String, dynamic> hits PluginInstaller.mergeJson which only
      // accepts already-parsed data, not a raw stub key.
      final stubBody = _ctx.stubs.load(spec.source);
      final parsed = jsonDecode(stubBody);
      if (parsed is! Map<String, dynamic>) {
        throw FormatException(
          'json_merge source "${spec.source}" must decode to a JSON object; '
          'got ${parsed.runtimeType}.',
        );
      }
      installer.mergeJson(
        targetPath: targetPath,
        sourceData: parsed,
        additive: spec.additive,
      );
    });
  }

  void _applyMagic(PluginInstaller installer) {
    final magic = _manifest.magic;
    if (magic.provider != null) {
      installer.injectProvider(magic.provider!);
    }
    if (magic.configFactory != null) {
      installer.injectConfigFactory(magic.configFactory!);
    }
    if (magic.routes != null) {
      installer.injectRoute(magic.routes!);
    }
  }

  void _applyNative(PluginInstaller installer) {
    final native = _manifest.native;
    if (native.android != null) _applyAndroid(installer, native.android!);
    if (native.ios != null) _applyApplePlatform(installer, 'ios', native.ios!);
    if (native.macos != null) {
      _applyApplePlatform(installer, 'macos', _asIos(native.macos!));
    }
    if (native.web != null) _applyWeb(installer, native.web!);
  }

  void _applyAndroid(PluginInstaller installer, AndroidConfig android) {
    for (final permission in android.permissions) {
      installer.injectAndroidPermission(permission);
    }
    android.metaData.forEach((name, value) {
      installer.injectAndroidMetaData(name: name, value: value);
    });
    final gradle = android.gradle;
    if (gradle != null) {
      for (final plugin in gradle.plugins) {
        installer.injectGradlePlugin(
          pluginId: plugin.id,
          version: plugin.version,
        );
      }
      for (final dep in gradle.deps) {
        installer.injectGradleDependency(
            scope: dep.scope, notation: dep.notation);
      }
    }
  }

  void _applyApplePlatform(
    PluginInstaller installer,
    String platform,
    IosConfig config,
  ) {
    config.infoPlist.forEach((key, value) {
      installer.injectInfoPlistKey(key: key, value: value, platform: platform);
    });
    config.entitlements.forEach((key, value) {
      installer.injectEntitlement(platform: platform, key: key, value: value);
    });
    final podfile = config.podfile;
    if (podfile != null) {
      for (final pod in podfile.pods) {
        installer.injectPodfileLine(platform: platform, line: "pod '$pod'");
      }
    }
  }

  /// Adapts a [MacosConfig] payload to the [IosConfig] shape so
  /// [_applyApplePlatform] can dispatch both with one method. The two configs
  /// share field-by-field structure; this method is a structural cast.
  IosConfig _asIos(MacosConfig macos) {
    return IosConfig(
      infoPlist: macos.infoPlist,
      entitlements: macos.entitlements,
      podfile: macos.podfile,
    );
  }

  void _applyWeb(PluginInstaller installer, WebConfig web) {
    for (final script in web.headScripts) {
      installer.injectIntoWebHead(script);
    }
    for (final tag in web.metaTags) {
      installer.addWebMetaTag(tag);
    }
  }

  void _applyEnv(PluginInstaller installer) {
    _manifest.env.forEach((key, spec) {
      installer.injectEnvVar(
        key: key,
        value: spec.defaultValue,
        comment: spec.comment,
      );
    });
  }

  void _applyPostInstall(PluginInstaller installer) {
    final post = _manifest.postInstall;
    for (final shell in post.run) {
      installer.runShell(command: shell.cmd, args: shell.args);
    }
    for (final ask in post.askToRun) {
      installer.askToRunShell(
        prompt: ask.prompt,
        command: ask.cmd,
        args: ask.args,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Prompts + placeholders
  // ---------------------------------------------------------------------------

  /// Drives each declared prompt and returns the captured `key → answer` map.
  ///
  /// Precedence: [_promptOverrides] (CLI flag injection) wins. Then, when
  /// [nonInteractive] is true, defaults win. Otherwise the [PromptDriver] is
  /// invoked through the matching type-specific call (string / bool / choice).
  Map<String, String> _runPrompts({required bool nonInteractive}) {
    final results = <String, String>{};
    for (final prompt in _manifest.prompts) {
      if (_promptOverrides.containsKey(prompt.key)) {
        results[prompt.key] = _promptOverrides[prompt.key]!;
        continue;
      }
      if (nonInteractive) {
        results[prompt.key] = prompt.defaultValue ?? '';
        continue;
      }
      results[prompt.key] = _drivePrompt(prompt);
    }
    return results;
  }

  /// Dispatches one [PromptSpec] to the right [PromptDriver] method based on
  /// `type`. Booleans are stored as `'true'` / `'false'` so the substitution
  /// pipeline can treat every answer as a String.
  String _drivePrompt(PromptSpec prompt) {
    switch (prompt.type) {
      case 'bool':
        final defaultBool = prompt.defaultValue == 'true';
        final answered =
            _ctx.prompt.confirm(prompt.question, defaultValue: defaultBool);
        return answered ? 'true' : 'false';
      case 'choice':
        return _ctx.prompt.choice(
          prompt.question,
          options: prompt.options,
          defaultValue: prompt.defaultValue,
        );
      case 'string':
      default:
        return _ctx.prompt.ask(
          prompt.question,
          defaultValue: prompt.defaultValue,
        );
    }
  }

  /// Substitutes `{{ prompts.X }}` references in every placeholder value with
  /// the matching prompt answer. Unreferenced placeholder values pass through
  /// unchanged.
  Map<String, String> _resolvePlaceholders(Map<String, String> promptResults) {
    final out = <String, String>{};
    _manifest.placeholders.forEach((key, template) {
      out[key] = template.replaceAllMapped(_promptRefRegex, (match) {
        final ref = match.group(1)!;
        return promptResults[ref] ?? match.group(0)!;
      });
    });
    return out;
  }

  // ---------------------------------------------------------------------------
  // Uninstall helpers
  // ---------------------------------------------------------------------------

  String _recordPath() => p.join(
        _ctx.projectRoot,
        '.artisan',
        'installed',
        '${_manifest.pluginName}.json',
      );

  /// Reconstructs a typed [InstallOperation] from a record entry.
  ///
  /// Mirrors the schema produced by [InstallTransaction._serializeOp]. Pattern
  /// fields ([InjectBeforePattern.pattern] / [InjectAfterPattern.pattern])
  /// are rebuilt as plain `String` Patterns because the record persists them
  /// via `toString()` and the reverse-op logic does not currently need a
  /// RegExp roundtrip (those ops have no reverse in V1).
  ///
  /// Returns `null` for unknown type strings or entries that fail the typed
  /// payload shape check; callers log a skip warning for those.
  InstallOperation? _opFromRecord(Map entry) {
    final type = entry['type'];
    switch (type) {
      case 'WriteFile':
        final target = entry['targetPath'];
        final content = entry['content'];
        if (target is String && content is String) {
          return WriteFile(targetPath: target, content: content);
        }
        return null;
      case 'DeleteFile':
        final target = entry['targetPath'];
        if (target is String) {
          return DeleteFile(targetPath: target);
        }
        return null;
      case 'CopyFile':
        final source = entry['sourcePath'];
        final target = entry['targetPath'];
        if (source is String && target is String) {
          return CopyFile(sourcePath: source, targetPath: target);
        }
        return null;
      case 'PublishFile':
        final stub = entry['sourceStubName'];
        final target = entry['targetPath'];
        final rawReplacements = entry['replacements'];
        if (stub is String && target is String && rawReplacements is Map) {
          return PublishFile(
            sourceStubName: stub,
            targetPath: target,
            replacements: rawReplacements.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ),
          );
        }
        return null;
      case 'AddDependency':
        final name = entry['name'];
        final version = entry['version'];
        final isDev = entry['isDev'];
        if (name is String && version is String) {
          return AddDependency(
            name: name,
            version: version,
            isDev: isDev is bool ? isDev : false,
          );
        }
        return null;
      case 'AddPathDependency':
        final name = entry['name'];
        final path = entry['path'];
        if (name is String && path is String) {
          return AddPathDependency(name: name, path: path);
        }
        return null;
      case 'RemoveDependency':
        final name = entry['name'];
        if (name is String) {
          return RemoveDependency(name: name);
        }
        return null;
      case 'AddPubspecAsset':
        final assetPath = entry['assetPath'];
        if (assetPath is String) {
          return AddPubspecAsset(assetPath: assetPath);
        }
        return null;
      case 'MergeJson':
        final target = entry['targetPath'];
        final additive = entry['additive'];
        if (target is String) {
          // sourceData is intentionally omitted from the record (see
          // _serializeOp). The reverse for MergeJson is V1-deferred, so an
          // empty sourceData is acceptable for round-trip reconstruction.
          return MergeJson(
            targetPath: target,
            sourceData: const <String, dynamic>{},
            additive: additive is bool ? additive : true,
          );
        }
        return null;
      case 'InjectImport':
        final targetFile = entry['targetFile'];
        final importStatement = entry['importStatement'];
        if (targetFile is String && importStatement is String) {
          return InjectImport(
            targetFile: targetFile,
            importStatement: importStatement,
          );
        }
        return null;
      case 'InjectBeforePattern':
        final targetFile = entry['targetFile'];
        final pattern = entry['pattern'];
        final code = entry['code'];
        if (targetFile is String && pattern is String && code is String) {
          return InjectBeforePattern(
            targetFile: targetFile,
            pattern: pattern,
            code: code,
          );
        }
        return null;
      case 'InjectAfterPattern':
        final targetFile = entry['targetFile'];
        final pattern = entry['pattern'];
        final code = entry['code'];
        if (targetFile is String && pattern is String && code is String) {
          return InjectAfterPattern(
            targetFile: targetFile,
            pattern: pattern,
            code: code,
          );
        }
        return null;
      case 'InjectAndroidPermission':
        final permission = entry['permission'];
        if (permission is String) {
          return InjectAndroidPermission(permission: permission);
        }
        return null;
      case 'InjectAndroidMetaData':
        final name = entry['name'];
        final value = entry['value'];
        if (name is String && value is String) {
          return InjectAndroidMetaData(name: name, value: value);
        }
        return null;
      case 'InjectInfoPlistKey':
        final platform = entry['platform'];
        final key = entry['key'];
        final value = entry['value'];
        if (platform is String && key is String && value is String) {
          return InjectInfoPlistKey(
            key: key,
            value: value,
            platform: platform,
          );
        }
        return null;
      case 'InjectEntitlement':
        final platform = entry['platform'];
        final key = entry['key'];
        final value = entry['value'];
        if (platform is String && key is String && value is String) {
          return InjectEntitlement(
            platform: platform,
            key: key,
            value: value,
          );
        }
        return null;
      case 'InjectPodfileLine':
        final platform = entry['platform'];
        final line = entry['line'];
        if (platform is String && line is String) {
          return InjectPodfileLine(platform: platform, line: line);
        }
        return null;
      case 'InjectGradlePlugin':
        final pluginId = entry['pluginId'];
        final version = entry['version'];
        if (pluginId is String) {
          return InjectGradlePlugin(
            pluginId: pluginId,
            version: version is String ? version : null,
          );
        }
        return null;
      case 'InjectGradleDependency':
        final scope = entry['scope'];
        final notation = entry['notation'];
        if (scope is String && notation is String) {
          return InjectGradleDependency(scope: scope, notation: notation);
        }
        return null;
      case 'InjectEnvVar':
        final key = entry['key'];
        final value = entry['value'];
        final comment = entry['comment'];
        if (key is String && value is String) {
          return InjectEnvVar(
            key: key,
            value: value,
            comment: comment is String ? comment : null,
          );
        }
        return null;
      case 'InjectIntoWebHead':
        final content = entry['content'];
        if (content is String) {
          return InjectIntoWebHead(content: content);
        }
        return null;
      case 'AddWebMetaTag':
        final attributes = entry['attributes'];
        if (attributes is Map) {
          return AddWebMetaTag(
            attributes: attributes.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ),
          );
        }
        return null;
      case 'InjectMainDartImport':
        final importStatement = entry['importStatement'];
        if (importStatement is String) {
          return InjectMainDartImport(importStatement: importStatement);
        }
        return null;
      case 'InjectIntoMainDart':
        final placement = entry['placement'];
        final code = entry['code'];
        if (placement is String && code is String) {
          final parsed = MainDartPlacement.values
              .where((e) => e.name == placement)
              .firstOrNull;
          if (parsed == null) return null;
          return InjectIntoMainDart(placement: parsed, code: code);
        }
        return null;
      case 'InjectRouteRegistration':
        final functionName = entry['functionName'];
        if (functionName is String) {
          return InjectRouteRegistration(functionName: functionName);
        }
        return null;
      case 'RunShell':
        final command = entry['command'];
        final args = entry['args'];
        final workingDir = entry['workingDir'];
        if (command is String && args is List) {
          return RunShell(
            command: command,
            args: args.map((e) => e.toString()).toList(),
            workingDir: workingDir is String ? workingDir : null,
          );
        }
        return null;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Static reverse-op derivation (exhaustive over InstallOperation)
  // ---------------------------------------------------------------------------

  /// Returns the reverse op for [op], or `null` when no clean reverse exists
  /// in V1.
  ///
  /// The switch is exhaustive over the sealed [InstallOperation] hierarchy so
  /// adding a new op type without updating this method fails compilation.
  ///
  /// Reversibility table (V1):
  /// - `AddDependency` / `AddPathDependency` → [RemoveDependency]
  /// - `RemoveDependency` → null (we cannot resurrect the prior version)
  /// - `PublishFile` / `WriteFile` / `CopyFile` → [DeleteFile]
  /// - `DeleteFile` → null (we never persisted the deleted content)
  /// - `RunShell` → null (shell side effects are unknowable)
  /// - All `Inject*` / `Merge*` / `AddPubspecAsset` / `AddWebMetaTag` → null
  ///   in V1 because the recorded payload would need bespoke remove-ops on
  ///   the relevant editor helpers. Tracked as a V2 enhancement.
  ///
  /// @param op  Any sealed [InstallOperation].
  /// @return The reverse op, or `null` when no clean reverse is available.
  @visibleForTesting
  static InstallOperation? reverseOf(InstallOperation op) {
    return switch (op) {
      AddDependency(:final name) => RemoveDependency(name: name),
      AddPathDependency(:final name) => RemoveDependency(name: name),
      RemoveDependency() => null,
      AddPubspecAsset() => null,
      PublishFile(:final targetPath) => DeleteFile(targetPath: targetPath),
      WriteFile(:final targetPath) => DeleteFile(targetPath: targetPath),
      DeleteFile() => null,
      CopyFile(:final targetPath) => DeleteFile(targetPath: targetPath),
      MergeJson() => null,
      InjectImport() => null,
      InjectBeforePattern() => null,
      InjectAfterPattern() => null,
      InjectAndroidPermission() => null,
      InjectAndroidMetaData() => null,
      InjectInfoPlistKey() => null,
      InjectEntitlement() => null,
      InjectPodfileLine() => null,
      InjectGradlePlugin() => null,
      InjectGradleDependency() => null,
      InjectEnvVar() => null,
      InjectIntoWebHead() => null,
      AddWebMetaTag() => null,
      InjectMainDartImport() => null,
      InjectIntoMainDart() => null,
      InjectRouteRegistration() => null,
      RunShell() => null,
    };
  }
}
