import 'package:meta/meta.dart';

import 'install_context.dart';
import 'install_operation.dart';
import 'install_transaction.dart';

/// Fluent builder consumed by every plugin's `<plugin>:install` command.
///
/// `PluginInstaller` collects an ordered list of [InstallOperation]s through
/// chain methods (Steps 19-23) and a final [commit] call dispatches them to
/// an [InstallTransaction] for atomic write + record persistence + conflict
/// pre-flight.
///
/// ## Lifecycle (one-shot)
///
/// Each `PluginInstaller` instance commits exactly once. After [commit]
/// returns ANY result ([Success] / [DryRun] / [Conflict] / [Error]) a second
/// call throws [StateError]. The reasoning is symmetric with
/// [InstallTransaction]'s own one-shot semantics: replaying chain-built ops
/// against partially mutated disk state silently corrupts the install record.
/// Plugin authors should construct a fresh `PluginInstaller` per install pass.
///
/// ## startWith / endWith escape hatches
///
/// - [startWith] fires immediately before the ops dispatch and runs even when
///   the dispatch later returns a non-[Success] result. Use it for setup that
///   must happen regardless of outcome (e.g. priming a logger).
/// - [endWith] fires only after a [Success] result lands. Use it for
///   post-install side effects that are unsafe to run on a half-applied
///   install (e.g. printing a "next steps" banner).
///
/// ## Method classification, IMMEDIATE vs DEFERRED
///
/// Chain methods fall into two distinct execution categories. Plugin authors
/// MUST internalise the split because it determines whether a method's effect
/// is visible inside the chain or only after [commit].
///
/// ### IMMEDIATE (run synchronously when called)
///
/// - [ask], [confirm], [choice]: drive [InstallContext.prompt] synchronously
///   and store the answer in an internal [_vars] map. Subsequent chain calls
///   can read the captured value via the [vars] getter and branch on it
///   (`if (installer.vars['enableX'] == 'true') ...`).
/// - [startWith], [endWith]: register lifecycle hooks. Neither fires at
///   registration time; both fire later from [commit].
///
/// ### DEFERRED (enqueued as an [InstallOperation], applied during commit)
///
/// - All `add*` / `inject*` / `write*` / `delete*` / `copy*` / `publish*` /
///   `merge*` / `wrap*` methods plus [runShell]. They append to the internal
///   op list and only touch the filesystem during [commit].
///
/// [askToRunShell] is a hybrid: it runs the prompt IMMEDIATELY, but enqueues
/// a [RunShell] op when the user confirms (so the shell command still
/// executes deferredly).
///
/// ## Limitations
///
/// Several dispatcher arms delegate to legacy helper classes
/// ([ConfigEditor], [JsonEditor], [MainDartEditor], [XmlEditor], [PlistWriter],
/// [PodfileEditor], [GradleEditor], [HtmlEditor], [EnvEditor]) which read and
/// write through [FileHelper]/`dart:io` directly. Those helpers BYPASS the
/// [InstallContext.fs] [VirtualFs] abstraction. Consequences:
///
/// - Tests targeting pubspec / inject / native / web / env dispatcher arms
///   must point `projectRoot` at a real temp directory; an [InMemoryFs] alone
///   will not see the writes.
/// - The atomic `.tmp` swap performed by [InstallTransaction.commit] applies
///   only to [WriteFile] / [DeleteFile] / [CopyFile] / [PublishFile]
///   ops. Helper-backed ops commit synchronously during the stage phase, so
///   a failure later in the dispatch does NOT roll them back. V1 trade-off:
///   plugins should order their ops so the helper-backed mutations follow
///   any high-risk file writes, not precede them.
///
/// ## Usage
///
/// ```dart
/// final installer = PluginInstaller(ctx, pluginName: 'magic_logger');
/// final result = await installer
///   .startWith((ctx) => ctx.artisanContext.output.info('Installing...'))
///   .addDependency('intl', '^0.20.0')
///   .publishConfig(stubName: 'install/logger.dart.stub',
///                  targetPath: 'lib/config/logger.dart')
///   .injectProvider('LoggerServiceProvider')
///   .ask(varName: 'logPath', question: 'Log path?', defaultValue: '/tmp/log')
///   .endWith((ctx) => ctx.artisanContext.output.success('Run "flutter pub get"'))
///   .commit(dryRun: false, force: false);
/// ```
class PluginInstaller {
  /// Creates a `PluginInstaller` bound to [ctx] for the plugin identified by
  /// [pluginName].
  ///
  /// [pluginName] threads through [InstallTransaction] to the
  /// `.artisan/installed/<pluginName>.json` record file path.
  ///
  /// @param ctx         The active [InstallContext] (fs / prompt / stubs /
  ///                    clock / output).
  /// @param pluginName  Pubspec package name of the plugin under installation.
  PluginInstaller(InstallContext ctx, {required String pluginName})
      : _ctx = ctx,
        _pluginName = pluginName;

  final InstallContext _ctx;
  final String _pluginName;
  final List<InstallOperation> _ops = <InstallOperation>[];

  /// Captured answers from [ask] / [confirm] / [choice]. Booleans are stored
  /// as the strings `'true'` / `'false'` so the whole map can be passed
  /// directly to placeholder substitution helpers. The map is private; the
  /// public [vars] getter returns an unmodifiable view.
  final Map<String, String> _vars = <String, String>{};

  /// Hook fired immediately before [commit] dispatches its ops. `null` when no
  /// [startWith] call was made. First-class function fields use the explicit
  /// `void Function(...)?` type, Dart has no `Closure` type.
  void Function(InstallContext)? _startWith;

  /// Hook fired only after [commit] returns [Success]. `null` when no
  /// [endWith] call was made.
  void Function(InstallContext)? _endWith;

  /// One-shot guard. Flipped to `true` inside [commit] before any work runs so
  /// a second call always throws regardless of the first call's outcome.
  bool _committed = false;

  /// Number of operations currently queued for the next [commit].
  ///
  /// @return The length of the internal pending-op list.
  int get pendingCount => _ops.length;

  /// Read-only view of the queued operations in insertion order. Mutating the
  /// returned list throws [UnsupportedError].
  ///
  /// @return An unmodifiable [List] of pending [InstallOperation]s.
  List<InstallOperation> get pendingOps =>
      List<InstallOperation>.unmodifiable(_ops);

  /// Read-only view of the captured prompt answers.
  ///
  /// Populated synchronously by [ask], [confirm], and [choice]. Subsequent
  /// chain calls can branch on `installer.vars['key']` to assemble
  /// conditional install plans. Mutating the returned map throws
  /// [UnsupportedError].
  ///
  /// @return An unmodifiable [Map] of varName → captured answer string.
  Map<String, String> get vars => Map<String, String>.unmodifiable(_vars);

  /// Registers a callback invoked immediately before the ops are dispatched
  /// inside [commit].
  ///
  /// Fires once per `PluginInstaller` instance. Replaces any previously
  /// registered hook (last-write-wins). Returns `this` for chaining.
  ///
  /// @param hook  The callback. Receives the bound [InstallContext].
  /// @return This installer (chainable).
  PluginInstaller startWith(void Function(InstallContext) hook) {
    _startWith = hook;
    return this;
  }

  /// Registers a callback invoked after [commit] returns [Success].
  ///
  /// Does NOT fire on [DryRun], [Conflict], or [Error] outcomes. Replaces any
  /// previously registered hook (last-write-wins). Returns `this` for
  /// chaining.
  ///
  /// @param hook  The callback. Receives the bound [InstallContext].
  /// @return This installer (chainable).
  PluginInstaller endWith(void Function(InstallContext) hook) {
    _endWith = hook;
    return this;
  }

  /// Test-only seam: enqueues [op] directly without going through a chain
  /// method.
  ///
  /// Production callers should use the public chain methods; this exists so
  /// the original Step 18 lifecycle tests can populate the queue with
  /// arbitrary op shapes without coupling to the chain-method surface.
  ///
  /// @param op  The [InstallOperation] to enqueue.
  @visibleForTesting
  void stageForTest(InstallOperation op) {
    _ops.add(op);
  }

  // ---------------------------------------------------------------------------
  // Pubspec
  // ---------------------------------------------------------------------------

  /// Enqueues an [AddDependency] for the runtime `dependencies:` map.
  ///
  /// @param name     Package name as published on pub.dev.
  /// @param version  Version constraint, e.g. `'^1.0.0'`.
  /// @return This installer (chainable).
  PluginInstaller addDependency(String name, String version) {
    _ops.add(AddDependency(name: name, version: version));
    return this;
  }

  /// Enqueues an [AddDependency] flagged for the `dev_dependencies:` map.
  ///
  /// @param name     Package name.
  /// @param version  Version constraint.
  /// @return This installer (chainable).
  PluginInstaller addDevDependency(String name, String version) {
    _ops.add(AddDependency(name: name, version: version, isDev: true));
    return this;
  }

  /// Enqueues an [AddPathDependency] for a relative-path dependency.
  ///
  /// Useful when the plugin ships a sibling package that must be referenced
  /// by filesystem path rather than a published version.
  ///
  /// @param name  Package name as it should appear in `pubspec.yaml`.
  /// @param path  Relative path to the package root.
  /// @return This installer (chainable).
  PluginInstaller addPathDependency(String name, String path) {
    _ops.add(AddPathDependency(name: name, path: path));
    return this;
  }

  /// Enqueues a [RemoveDependency] that strips [name] from either map.
  ///
  /// Idempotent at dispatcher level: removing an absent dependency is a
  /// silent no-op.
  ///
  /// @param name  Package name to remove.
  /// @return This installer (chainable).
  PluginInstaller removeDependency(String name) {
    _ops.add(RemoveDependency(name: name));
    return this;
  }

  /// Enqueues an [AddPubspecAsset] appending [assetPath] to `flutter.assets`.
  ///
  /// The dispatcher uses [ConfigEditor.appendPubspecListEntry] which
  /// preserves existing entries. Idempotent on duplicate paths.
  ///
  /// @param assetPath  Asset path relative to the project root.
  /// @return This installer (chainable).
  PluginInstaller addPubspecAsset(String assetPath) {
    _ops.add(AddPubspecAsset(assetPath: assetPath));
    return this;
  }

  // ---------------------------------------------------------------------------
  // File
  // ---------------------------------------------------------------------------

  /// Enqueues a [PublishFile]: the dispatcher loads [stubName] via the
  /// context's [StubDriver], substitutes [replacements], and writes the
  /// rendered content to [targetPath].
  ///
  /// @param stubName      Logical stub name (no extension) resolvable by
  ///                      [StubDriver.load].
  /// @param targetPath    Destination path (absolute or relative to
  ///                      `projectRoot`).
  /// @param replacements  Placeholder map applied to the loaded stub.
  /// @return This installer (chainable).
  PluginInstaller publishConfig({
    required String stubName,
    required String targetPath,
    Map<String, String> replacements = const <String, String>{},
  }) {
    _ops.add(PublishFile(
      sourceStubName: stubName,
      targetPath: targetPath,
      replacements: replacements,
    ));
    return this;
  }

  /// Enqueues a [WriteFile] that writes [content] verbatim to [targetPath].
  ///
  /// Prefer [publishConfig] when the content originates from a stub template.
  /// Use [writeFile] for programmatically generated content.
  ///
  /// @param targetPath  Destination path.
  /// @param content     Raw UTF-8 content to write.
  /// @return This installer (chainable).
  PluginInstaller writeFile({
    required String targetPath,
    required String content,
  }) {
    _ops.add(WriteFile(targetPath: targetPath, content: content));
    return this;
  }

  /// Enqueues a [DeleteFile] removing the file at [targetPath]. Idempotent
  /// at dispatcher level: deleting an absent file is a silent no-op.
  ///
  /// @param targetPath  Path to delete.
  /// @return This installer (chainable).
  PluginInstaller deleteFile(String targetPath) {
    _ops.add(DeleteFile(targetPath: targetPath));
    return this;
  }

  /// Enqueues a [CopyFile] copying [sourcePath] to [targetPath].
  ///
  /// @param sourcePath  Source path.
  /// @param targetPath  Destination path.
  /// @return This installer (chainable).
  PluginInstaller copyFile({
    required String sourcePath,
    required String targetPath,
  }) {
    _ops.add(CopyFile(sourcePath: sourcePath, targetPath: targetPath));
    return this;
  }

  /// Enqueues a [MergeJson] that deep-merges [sourceData] into the JSON file
  /// at [targetPath].
  ///
  /// @param targetPath  Path to the target JSON file.
  /// @param sourceData  Map to merge into the target.
  /// @param additive    When `true` (default), existing keys are preserved
  ///                    and only new keys are inserted. When `false`,
  ///                    conflicting keys are overwritten by the source.
  /// @return This installer (chainable).
  PluginInstaller mergeJson({
    required String targetPath,
    required Map<String, dynamic> sourceData,
    bool additive = true,
  }) {
    _ops.add(MergeJson(
      targetPath: targetPath,
      sourceData: sourceData,
      additive: additive,
    ));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Inject
  // ---------------------------------------------------------------------------

  /// Enqueues an [InjectImport] that appends [importStatement] to
  /// [targetFile] (after any existing imports).
  ///
  /// @param targetFile       Path of the Dart file receiving the import.
  /// @param importStatement  Full import line (semicolon optional).
  /// @return This installer (chainable).
  PluginInstaller injectImport({
    required String targetFile,
    required String importStatement,
  }) {
    _ops.add(InjectImport(
      targetFile: targetFile,
      importStatement: importStatement,
    ));
    return this;
  }

  /// Enqueues an [InjectBeforePattern] that inserts [code] immediately before
  /// the first match of [pattern] in [targetFile].
  ///
  /// @param targetFile  Path of the file to mutate.
  /// @param pattern     Regex or literal string locating the anchor.
  /// @param code        Snippet to insert before the match.
  /// @return This installer (chainable).
  PluginInstaller injectBefore({
    required String targetFile,
    required Pattern pattern,
    required String code,
  }) {
    _ops.add(InjectBeforePattern(
      targetFile: targetFile,
      pattern: pattern,
      code: code,
    ));
    return this;
  }

  /// Enqueues an [InjectAfterPattern] that inserts [code] immediately after
  /// the first match of [pattern] in [targetFile].
  ///
  /// @param targetFile  Path of the file to mutate.
  /// @param pattern     Regex or literal string locating the anchor.
  /// @param code        Snippet to insert after the match.
  /// @return This installer (chainable).
  PluginInstaller injectAfter({
    required String targetFile,
    required Pattern pattern,
    required String code,
  }) {
    _ops.add(InjectAfterPattern(
      targetFile: targetFile,
      pattern: pattern,
      code: code,
    ));
    return this;
  }

  /// Enqueues an [InjectMainDartImport] adding [importStatement] to
  /// `<projectRoot>/lib/main.dart`.
  ///
  /// Mirrors [injectImport] but locks the target to `main.dart` so the
  /// dry-run output can group main.dart mutations under their own tag.
  ///
  /// @param importStatement  Full import line.
  /// @return This installer (chainable).
  PluginInstaller injectMainDartImport(String importStatement) {
    _ops.add(InjectMainDartImport(importStatement: importStatement));
    return this;
  }

  /// Enqueues an [InjectIntoMainDart] with placement
  /// [MainDartPlacement.beforeInit].
  ///
  /// @param code  Code snippet to insert immediately before `Magic.init(...)`.
  /// @return This installer (chainable).
  PluginInstaller injectBeforeMagicInit(String code) {
    _ops.add(InjectIntoMainDart(
      placement: MainDartPlacement.beforeInit,
      code: code,
    ));
    return this;
  }

  /// Enqueues an [InjectIntoMainDart] with placement
  /// [MainDartPlacement.afterInit].
  ///
  /// @param code  Code snippet to insert immediately after `Magic.init(...)`.
  /// @return This installer (chainable).
  PluginInstaller injectAfterMagicInit(String code) {
    _ops.add(InjectIntoMainDart(
      placement: MainDartPlacement.afterInit,
      code: code,
    ));
    return this;
  }

  /// Enqueues an [InjectIntoMainDart] with placement
  /// [MainDartPlacement.wrapRunApp].
  ///
  /// The [wrapperName] string is the constructor name the dispatcher wraps
  /// around `runApp`'s argument (e.g. `'SentryWidget'`).
  ///
  /// @param wrapperName  Widget constructor name.
  /// @return This installer (chainable).
  PluginInstaller wrapRunApp(String wrapperName) {
    _ops.add(InjectIntoMainDart(
      placement: MainDartPlacement.wrapRunApp,
      code: wrapperName,
    ));
    return this;
  }

  /// Enqueues a composite (import + after-pattern injection) that registers
  /// [providerClassName] inside `lib/config/app.dart`'s `'providers': [...]`
  /// list.
  ///
  /// The injected entry uses Magic's closure shape `(app) => X(app),` because
  /// the providers list is typed `List<ServiceProvider Function(MagicApplication)>`.
  /// A bare constructor `X(),` would fail to compile.
  ///
  /// The import statement defaults to
  /// `package:<pluginName>/<pluginName>.dart` derived from the installer's
  /// [_pluginName]; pass [package] to override (e.g. when the provider lives
  /// in a sub-import).
  ///
  /// Plugin Authoring Guide requirement: the consumer's
  /// `lib/config/app.dart` MUST declare `'providers': [...]` as a Dart map
  /// literal entry. Plugins targeting non-conforming app.dart files will see
  /// the after-pattern injection silently no-op (helper behaviour) and the
  /// install reports Success regardless. Document the requirement upstream.
  ///
  /// @param providerClassName  Provider class to instantiate.
  /// @param package            Optional import target overriding the default
  ///                           `package:<pluginName>/<pluginName>.dart`.
  /// @return This installer (chainable).
  PluginInstaller injectProvider(
    String providerClassName, {
    String? package,
  }) {
    final String importTarget =
        package ?? 'package:$_pluginName/$_pluginName.dart';
    _ops.add(InjectImport(
      targetFile: 'lib/config/app.dart',
      importStatement: "import '$importTarget';",
    ));
    // Append to the END of the providers list (just after the last entry's
    // trailing comma) using a lookahead-anchored regex that only matches the
    // last `(app) => XxxServiceProvider(app),` line before the closing `]`.
    // Falls back to inserting after `'providers': [` (i.e. at the top of the
    // list) when the host's providers list is empty.
    _ops.add(InjectAfterPattern(
      targetFile: 'lib/config/app.dart',
      pattern:
          RegExp(r'\(app\)\s*=>\s*\w+ServiceProvider\(app\),(?=\s*\n\s*\])'),
      code: '\n      (app) => $providerClassName(app),',
    ));
    return this;
  }

  /// Enqueues a composite that registers [factoryName] inside `lib/main.dart`'s
  /// `configFactories: [...]` list.
  ///
  /// The import defaults to `package:<pluginName>/<pluginName>.dart`; pass
  /// [package] to override.
  ///
  /// @param factoryName  Top-level factory expression to insert.
  /// @param package      Optional import override.
  /// @return This installer (chainable).
  PluginInstaller injectConfigFactory(
    String factoryName, {
    String? package,
  }) {
    final String importTarget =
        package ?? 'package:$_pluginName/$_pluginName.dart';
    _ops.add(InjectMainDartImport(
      importStatement: "import '$importTarget';",
    ));
    // Append to the END of the configFactories list (just after the last
    // entry's trailing comma) using a lookahead-anchored regex that only
    // matches the last `() => xxxConfig,` line before the closing `]`.
    _ops.add(InjectAfterPattern(
      targetFile: 'lib/main.dart',
      pattern: RegExp(r'\(\)\s*=>\s*\w+Config,(?=\s*\n\s*\])'),
      code: '\n      () => $factoryName,',
    ));
    return this;
  }

  /// Enqueues an [InjectRouteRegistration] that calls
  /// `<registerFunctionName>();` inside the `boot()` method of
  /// `<projectRoot>/lib/app/providers/route_service_provider.dart`.
  ///
  /// @param registerFunctionName  Top-level route-registration function name.
  /// @return This installer (chainable).
  PluginInstaller injectRoute(String registerFunctionName) {
    _ops.add(InjectRouteRegistration(functionName: registerFunctionName));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Native
  // ---------------------------------------------------------------------------

  /// Enqueues an [InjectAndroidPermission]. Dispatcher silently skips when
  /// the consumer project has no `android/` directory.
  ///
  /// @param permission  Fully-qualified Android permission name.
  /// @return This installer (chainable).
  PluginInstaller injectAndroidPermission(String permission) {
    _ops.add(InjectAndroidPermission(permission: permission));
    return this;
  }

  /// Enqueues an [InjectAndroidMetaData] adding a `<meta-data>` element
  /// inside `<application>`. Skipped on non-Android consumers.
  ///
  /// @param name   `android:name` attribute value.
  /// @param value  `android:value` attribute value.
  /// @return This installer (chainable).
  PluginInstaller injectAndroidMetaData({
    required String name,
    required String value,
  }) {
    _ops.add(InjectAndroidMetaData(name: name, value: value));
    return this;
  }

  /// Enqueues an [InjectInfoPlistKey] setting [key] to [value] inside
  /// `<projectRoot>/<platform>/Runner/Info.plist`.
  ///
  /// The dispatcher dispatches on `value.runtimeType`:
  /// [String] → `PlistWriter.setStringKey`,
  /// [bool] → `PlistWriter.setBoolKey`,
  /// `List<String>` → `PlistWriter.setArrayKey`.
  /// Any other shape surfaces an [Error] result from the transaction.
  /// Skipped silently when the platform directory is absent.
  ///
  /// @param key       Plist key.
  /// @param value     Plist value (`String`, `bool`, or `List<String>`).
  /// @param platform  `'ios'` (default) or `'macos'`.
  /// @return This installer (chainable).
  PluginInstaller injectInfoPlistKey({
    required String key,
    required Object value,
    String platform = 'ios',
  }) {
    _ops.add(InjectInfoPlistKey(key: key, value: value, platform: platform));
    return this;
  }

  /// Enqueues an [InjectEntitlement] setting [key] to [value] in
  /// `<projectRoot>/<platform>/Runner/Runner.entitlements`.
  ///
  /// Dispatcher branches on `value` type ([String] / [bool]). Skipped
  /// silently when the platform directory is absent.
  ///
  /// @param platform  `'ios'` or `'macos'`.
  /// @param key       Entitlement key.
  /// @param value     Entitlement value (String / bool).
  /// @return This installer (chainable).
  PluginInstaller injectEntitlement({
    required String platform,
    required String key,
    required Object value,
  }) {
    _ops.add(InjectEntitlement(platform: platform, key: key, value: value));
    return this;
  }

  /// Enqueues an [InjectPodfileLine] appending [line] to the `target 'Runner'`
  /// block of the platform Podfile.
  ///
  /// @param platform  `'ios'` (default) or `'macos'`.
  /// @param line      Fully-formed CocoaPods pod declaration.
  /// @return This installer (chainable).
  PluginInstaller injectPodfileLine({
    String platform = 'ios',
    required String line,
  }) {
    _ops.add(InjectPodfileLine(platform: platform, line: line));
    return this;
  }

  /// Enqueues an [InjectGradlePlugin] adding [pluginId] to the
  /// `plugins { ... }` block of `<projectRoot>/android/app/build.gradle.kts`
  /// (or `.gradle` when the Kotlin variant is absent).
  ///
  /// @param pluginId  Gradle plugin ID.
  /// @param version   Optional version string.
  /// @return This installer (chainable).
  PluginInstaller injectGradlePlugin({
    required String pluginId,
    String? version,
  }) {
    _ops.add(InjectGradlePlugin(pluginId: pluginId, version: version));
    return this;
  }

  /// Enqueues an [InjectGradleDependency] adding [notation] under [scope] in
  /// `<projectRoot>/android/app/build.gradle.kts` (or `.gradle`).
  ///
  /// @param scope     Gradle scope (`'implementation'`, `'classpath'`, ...).
  /// @param notation  Full Maven coordinate.
  /// @return This installer (chainable).
  PluginInstaller injectGradleDependency({
    required String scope,
    required String notation,
  }) {
    _ops.add(InjectGradleDependency(scope: scope, notation: notation));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Web
  // ---------------------------------------------------------------------------

  /// Enqueues an [InjectIntoWebHead] inserting [content] before `</head>` in
  /// `<projectRoot>/web/index.html`. Skipped silently on consumers without a
  /// `web/` directory.
  ///
  /// @param content  Raw HTML to insert.
  /// @return This installer (chainable).
  PluginInstaller injectIntoWebHead(String content) {
    _ops.add(InjectIntoWebHead(content: content));
    return this;
  }

  /// Enqueues an [AddWebMetaTag] adding a `<meta>` element to
  /// `<projectRoot>/web/index.html`.
  ///
  /// @param attributes  `name`/`content`/`charset`/etc. attribute map.
  /// @return This installer (chainable).
  PluginInstaller addWebMetaTag(Map<String, String> attributes) {
    _ops.add(AddWebMetaTag(attributes: attributes));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Env
  // ---------------------------------------------------------------------------

  /// Enqueues an [InjectEnvVar] writing `<key>=<value>` to `<projectRoot>/.env`.
  /// Creates `.env` when absent.
  ///
  /// When [comment] is supplied, the dispatcher routes it through to
  /// [EnvEditor.setKey] which renders a `# <comment>` line directly above the
  /// `KEY=VALUE` line. The comment is also persisted on the [InjectEnvVar] op
  /// payload so uninstall + manual record inspection retain it verbatim.
  ///
  /// @param key      Environment variable name.
  /// @param value    Raw value (the dispatcher quotes when needed).
  /// @param comment  Optional single-line comment text (without the leading `#`).
  /// @return This installer (chainable).
  PluginInstaller injectEnvVar({
    required String key,
    required String value,
    String? comment,
  }) {
    _ops.add(InjectEnvVar(key: key, value: value, comment: comment));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Interactive (IMMEDIATE)
  // ---------------------------------------------------------------------------

  /// IMMEDIATE: prompts the user via [InstallContext.prompt] and stores the
  /// answer under [varName] in [_vars].
  ///
  /// Use [vars] to read captured answers when assembling subsequent ops.
  ///
  /// @param varName       Key under which the answer is stored in [vars].
  /// @param question      Prompt text.
  /// @param defaultValue  Optional default for ENTER.
  /// @param validator     Optional answer validator (return non-null error to
  ///                      re-ask).
  /// @return This installer (chainable).
  PluginInstaller ask({
    required String varName,
    required String question,
    String? defaultValue,
    String? Function(String)? validator,
  }) {
    _vars[varName] = _ctx.prompt.ask(
      question,
      defaultValue: defaultValue,
      validator: validator,
    );
    return this;
  }

  /// IMMEDIATE: prompts the user for a yes/no answer and stores it under
  /// [varName] as `'true'` or `'false'`.
  ///
  /// @param varName       Key under which the answer is stored in [vars].
  /// @param question      Prompt text.
  /// @param defaultValue  Default for ENTER.
  /// @return This installer (chainable).
  PluginInstaller confirm({
    required String varName,
    required String question,
    bool defaultValue = false,
  }) {
    final answered = _ctx.prompt.confirm(question, defaultValue: defaultValue);
    _vars[varName] = answered ? 'true' : 'false';
    return this;
  }

  /// IMMEDIATE: prompts the user to pick one of [options] and stores the
  /// selected option string under [varName].
  ///
  /// @param varName       Key under which the answer is stored in [vars].
  /// @param question      Prompt text.
  /// @param options       Non-empty list of valid choices.
  /// @param defaultValue  Optional default for ENTER.
  /// @return This installer (chainable).
  PluginInstaller choice({
    required String varName,
    required String question,
    required List<String> options,
    String? defaultValue,
  }) {
    _vars[varName] = _ctx.prompt.choice(
      question,
      options: options,
      defaultValue: defaultValue,
    );
    return this;
  }

  // ---------------------------------------------------------------------------
  // Shell (DEFERRED + hybrid)
  // ---------------------------------------------------------------------------

  /// Enqueues a [RunShell] that executes [command] with [args] inside
  /// [workingDir] (defaults to `_ctx.projectRoot`).
  ///
  /// `runShell` is the escape hatch: it lets a plugin install command call
  /// out to `flutter pub get`, `dart format`, `pod install`, etc. without
  /// dropping out of the install framework.
  ///
  /// @param command     Executable (no shell quoting).
  /// @param args        Positional arguments.
  /// @param workingDir  Optional working directory override.
  /// @return This installer (chainable).
  PluginInstaller runShell({
    required String command,
    List<String> args = const <String>[],
    String? workingDir,
  }) {
    _ops.add(RunShell(
      command: command,
      args: args,
      workingDir: workingDir,
    ));
    return this;
  }

  /// HYBRID: prompts immediately. When the user confirms, enqueues a
  /// [RunShell] that the dispatcher will execute during commit.
  ///
  /// @param prompt   Confirmation question.
  /// @param command  Executable to run on yes.
  /// @param args     Positional arguments.
  /// @return This installer (chainable).
  PluginInstaller askToRunShell({
    required String prompt,
    required String command,
    List<String> args = const <String>[],
  }) {
    if (_ctx.prompt.confirm(prompt)) {
      _ops.add(RunShell(command: command, args: args));
    }
    return this;
  }

  // ---------------------------------------------------------------------------
  // Commit
  // ---------------------------------------------------------------------------

  /// Dispatches the queued ops to an [InstallTransaction] and returns its
  /// result.
  ///
  /// @param dryRun  When `true`, the transaction prints staged ops and returns
  ///                [DryRun] without writing to disk.
  /// @param force   When `true`, the transaction bypasses the conflict
  ///                pre-flight and overwrites user-modified files.
  /// @return The [TransactionResult] surfaced by the underlying transaction.
  /// @throws StateError  When invoked more than once on the same instance.
  Future<TransactionResult> commit({
    bool dryRun = false,
    bool force = false,
  }) async {
    // 1. One-shot guard. Reject the second call regardless of the first
    //    call's outcome (Success / DryRun / Conflict / Error all flip the
    //    guard so the queue can never be replayed against stale state).
    if (_committed) {
      throw StateError(
        'PluginInstaller.commit() called twice on the same instance; '
        'installers are one-shot. Construct a new PluginInstaller for each '
        'install pass.',
      );
    }
    _committed = true;

    // 2. Fire the pre-commit hook (when registered). Runs before the dispatch
    //    attempt so setup work happens regardless of the eventual outcome.
    _startWith?.call(_ctx);

    // 3. Build an InstallTransaction bound to the same context and plugin
    //    identifier so the install record file path stays consistent.
    final tx = InstallTransaction(_ctx, pluginName: _pluginName);
    for (final op in _ops) {
      tx.stage(op);
    }

    // 4. Delegate the actual write / dry-run / conflict pre-flight to the
    //    transaction. Forwarding the two flags keeps the boolean surface flat.
    final result = await tx.commit(dryRun: dryRun, force: force);

    // 5. Post-commit hook fires only when the transaction reported Success.
    //    DryRun / Conflict / Error short-circuit the endWith so callers can
    //    safely use it for "next steps" banners that would mislead the user
    //    if printed after a failed or previewed run.
    if (result is Success) {
      _endWith?.call(_ctx);
    }

    return result;
  }
}
