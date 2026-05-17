import '../console/artisan_output.dart';
import 'install_operation.dart';

/// Pure-function renderer that prints a structured dry-run preview of a
/// staged [InstallOperation] list without touching the filesystem.
///
/// All state is passed via parameters; the class holds no instance fields and
/// exposes a single static entry point. Output is deterministic: no timestamps,
/// no random IDs.
///
/// ## Output format
///
/// ```
/// DRY RUN -- would execute N operations for <pluginName>:
///
/// [Pubspec]
///   [add-dep] foo: ^1.0.0
///
/// [Filesystem]
///   [write-file] lib/main.dart
///
/// [Shell]
///   [run-shell] dart format .
///
/// No changes written. Re-run without --dry-run to apply.
/// ```
///
/// Empty categories are omitted. The fixed category order is:
/// Pubspec, Filesystem, Magic, Native, Web, Env, Shell.
///
/// ## Usage
///
/// ```dart
/// DryRunRenderer.render(output, ops, pluginName: 'firebase_messaging');
/// ```
class DryRunRenderer {
  /// Private constructor: this class is static-only.
  DryRunRenderer._();

  /// Emits the dry-run preview to [output].
  ///
  /// Groups [ops] by category in a fixed order and prints each op via
  /// [InstallOperation.describe]. Empty categories are omitted. A footer
  /// line is always emitted at the end.
  ///
  /// @param output      The [ArtisanOutput] to write to (never touches disk).
  /// @param ops         The staged operations to render.
  /// @param pluginName  Optional plugin identifier included in the header.
  static void render(
    ArtisanOutput output,
    List<InstallOperation> ops, {
    String? pluginName,
  }) {
    // 1. Emit the header line including op count and optional plugin name.
    final suffix = pluginName != null ? ' for $pluginName' : '';
    output.writeln(
      'DRY RUN -- would execute ${ops.length} operations$suffix:',
    );

    // 2. Partition ops into the seven named categories in fixed order.
    final pubspec = <InstallOperation>[];
    final filesystem = <InstallOperation>[];
    final magic = <InstallOperation>[];
    final native = <InstallOperation>[];
    final web = <InstallOperation>[];
    final env = <InstallOperation>[];
    final shell = <InstallOperation>[];

    for (final op in ops) {
      switch (op) {
        case AddDependency():
        case AddPathDependency():
        case RemoveDependency():
        case AddPubspecAsset():
          pubspec.add(op);
        case PublishFile():
        case WriteFile():
        case DeleteFile():
        case CopyFile():
        case MergeJson():
          filesystem.add(op);
        case InjectImport():
        case InjectBeforePattern():
        case InjectAfterPattern():
        case InjectMainDartImport():
        case InjectIntoMainDart():
        case InjectRouteRegistration():
          magic.add(op);
        case InjectAndroidPermission():
        case InjectAndroidMetaData():
        case InjectInfoPlistKey():
        case InjectEntitlement():
        case InjectPodfileLine():
        case InjectGradlePlugin():
        case InjectGradleDependency():
          native.add(op);
        case InjectIntoWebHead():
        case AddWebMetaTag():
          web.add(op);
        case InjectEnvVar():
          env.add(op);
        case RunShell():
          shell.add(op);
      }
    }

    // 3. Emit each non-empty category with its bracketed label and indented op
    //    lines. The fixed order is Pubspec -> Filesystem -> Magic -> Native ->
    //    Web -> Env -> Shell.
    _renderCategory(output, '[Pubspec]', pubspec);
    _renderCategory(output, '[Filesystem]', filesystem);
    _renderCategory(output, '[Magic]', magic);
    _renderCategory(output, '[Native]', native);
    _renderCategory(output, '[Web]', web);
    _renderCategory(output, '[Env]', env);
    _renderCategory(output, '[Shell]', shell);

    // 4. Emit the footer so the user knows nothing was written.
    output.writeln('');
    output.writeln(
      'No changes written. Re-run without --dry-run to apply.',
    );
  }

  /// Emits a category block when [ops] is non-empty.
  ///
  /// @param output  Target output stream.
  /// @param label   Bracketed category label (e.g. `'[Pubspec]'`).
  /// @param ops     Operations belonging to this category.
  static void _renderCategory(
    ArtisanOutput output,
    String label,
    List<InstallOperation> ops,
  ) {
    if (ops.isEmpty) return;
    output.writeln('');
    output.writeln(label);
    for (final op in ops) {
      output.writeln('  ${op.describe()}');
    }
  }
}
