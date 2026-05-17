import 'package:args/args.dart';
import '../helpers/file_helper.dart';
import 'command.dart';
import 'string_helper.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../stubs/stub_loader.dart';

/// Base for all make:* generator commands.
abstract class GeneratorCommand extends Command {
  /// Returns the stub file name (without `.stub` extension).
  ///
  /// For example: `'model'`, `'controller'`, `'controller.resource'`.
  String getStub();

  /// Default output directory, e.g. 'lib/app/controllers'
  String getDefaultNamespace();

  /// Project root, defaults to finding it based on pubspec.yaml
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Resolve full file path from name (supports nested: 'Admin/UserController')
  String getPath(String name) {
    final parsed = StringHelper.parseName(name);
    final namespace = getDefaultNamespace();
    final projectRoot = getProjectRoot();

    if (parsed.directory.isEmpty) {
      return path.join(projectRoot, namespace, '${parsed.fileName}.dart');
    }

    return path.join(
        projectRoot, namespace, parsed.directory, '${parsed.fileName}.dart');
  }

  /// Load stub, replace all placeholders, return final content
  String buildClass(String name) {
    final stubsDir = Platform.environment['MAGIC_CLI_STUBS_DIR'];
    final stubName = getStub();
    String stub;
    if (stubName.contains(' ') || stubName.contains('{')) {
      // Backwards compatibility for tests that return raw stub content directly
      stub = stubName;
    } else {
      stub = StubLoader.load(stubName,
          searchPaths: stubsDir != null ? [stubsDir] : null);
    }
    stub = replaceNamespace(stub, name);
    stub = replaceClass(stub, name);

    final replacements = getReplacements(name);
    for (final entry in replacements.entries) {
      stub = stub.replaceAll(entry.key, entry.value);
    }

    return stub;
  }

  /// Replace {{ namespace }} placeholder
  String replaceNamespace(String stub, String name) {
    final parsed = StringHelper.parseName(name);
    final defaultNs = getDefaultNamespace();

    final namespace =
        parsed.directory.isEmpty ? defaultNs : '$defaultNs/${parsed.directory}';

    return stub.replaceAll('{{ namespace }}', namespace);
  }

  /// Replace {{ className }} placeholder (last segment of nested path)
  String replaceClass(String stub, String name) {
    final parsed = StringHelper.parseName(name);
    return stub.replaceAll('{{ className }}', parsed.className);
  }

  /// All placeholder->value mappings for this command
  Map<String, String> getReplacements(String name) => {};

  @override
  void configure(ArgParser parser) {
    super.configure(parser);
    parser.addFlag(
      'force',
      help: 'Overwrite the file if it exists',
      negatable: false,
    );
  }

  @override
  Future<void> handle() async {
    final name = argument(0);
    if (name == null || name.isEmpty) {
      error('Not enough arguments (missing: "name").');
      return;
    }

    final filePath = getPath(name);

    if (FileHelper.fileExists(filePath) && !hasOption('force')) {
      error('File already exists at $filePath');
      return;
    }

    final content = buildClass(name);
    FileHelper.writeFile(filePath, content);

    success('Created: $filePath');
  }
}
