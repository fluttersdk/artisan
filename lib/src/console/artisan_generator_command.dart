import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import '../helpers/file_helper.dart';
import '../stubs/stub_loader.dart';
import 'artisan_command.dart';
import 'artisan_context.dart';
import 'command_boot.dart';
import 'string_helper.dart';

/// Base for code-gen commands (make:controller, make:model, etc.).
///
/// Subclasses:
/// - declare [getStub] (stub file name without `.stub` extension)
/// - declare [getDefaultNamespace] (output directory under project root)
/// - optionally override [getReplacements] to add custom placeholders
/// - inherit `--force` flag from [configure]
abstract class ArtisanGeneratorCommand extends ArtisanCommand {
  @override
  CommandBoot get boot => CommandBoot.none;

  /// Stub name (without `.stub` extension). Resolved via [StubLoader].
  String getStub();

  /// Default output directory under the host project root.
  String getDefaultNamespace();

  /// Project root; defaults to walking up for `pubspec.yaml`.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Resolve full output path from the user-supplied `name` (supports nested
  /// `Admin/UserController`).
  String getPath(String name) {
    final parsed = StringHelper.parseName(name);
    final namespace = getDefaultNamespace();
    final projectRoot = getProjectRoot();
    if (parsed.directory.isEmpty) {
      return path.join(projectRoot, namespace, '${parsed.fileName}.dart');
    }
    return path.join(
      projectRoot,
      namespace,
      parsed.directory,
      '${parsed.fileName}.dart',
    );
  }

  /// Load stub, replace placeholders, return final content.
  String buildClass(String name) {
    final stubsDir =
        Platform.environment['ARTISAN_STUBS_DIR'] ??
        Platform.environment['MAGIC_CLI_STUBS_DIR'];
    final stubName = getStub();
    String stub;
    if (stubName.contains(' ') || stubName.contains('{')) {
      stub = stubName; // backwards-compat: raw stub string
    } else {
      stub = StubLoader.load(
        stubName,
        searchPaths: stubsDir != null ? [stubsDir] : null,
      );
    }
    stub = _replaceNamespace(stub, name);
    stub = _replaceClass(stub, name);
    for (final entry in getReplacements(name).entries) {
      stub = stub.replaceAll(entry.key, entry.value);
    }
    return stub;
  }

  String _replaceNamespace(String stub, String name) {
    final parsed = StringHelper.parseName(name);
    final defaultNs = getDefaultNamespace();
    final namespace = parsed.directory.isEmpty
        ? defaultNs
        : '$defaultNs/${parsed.directory}';
    return stub.replaceAll('{{ namespace }}', namespace);
  }

  String _replaceClass(String stub, String name) {
    final parsed = StringHelper.parseName(name);
    return stub.replaceAll('{{ className }}', parsed.className);
  }

  /// All placeholder → value mappings for this command.
  Map<String, String> getReplacements(String name) => const {};

  @override
  void configure(ArgParser parser) {
    super.configure(parser);
    parser.addFlag(
      'force',
      help: 'Overwrite the file if it exists.',
      negatable: false,
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final name = ctx.input.argument(0);
    if (name == null || name.isEmpty) {
      ctx.output.error('Not enough arguments (missing: "name").');
      return 1;
    }
    final filePath = getPath(name);
    if (FileHelper.fileExists(filePath) && !ctx.input.hasOption('force')) {
      ctx.output.error('File already exists at $filePath');
      return 1;
    }
    final content = buildClass(name);
    FileHelper.writeFile(filePath, content);
    ctx.output.success('Created: $filePath');
    return 0;
  }
}
