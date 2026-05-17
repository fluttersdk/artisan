import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/console/generator_command.dart';
import 'package:args/args.dart';
import 'dart:io';

class TestGeneratorCommand extends GeneratorCommand {
  TestGeneratorCommand(this.testRoot);

  final String testRoot;

  @override
  String get name => 'make:test';

  @override
  String get description => 'Make a test file';

  @override
  String getStub() => 'class {{ className }} {\n  // test {{ namespace }}\n}';

  @override
  String getDefaultNamespace() => 'lib/test_dir';

  @override
  Map<String, String> getReplacements(String name) => {};

  // Expose for testing without a real project root
  @override
  String getProjectRoot() => testRoot;
}

void main() {
  group('GeneratorCommand', () {
    late Directory tempDir;
    late TestGeneratorCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_gen_');
      cmd = TestGeneratorCommand(tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('getPath resolves correctly', () {
      final path = cmd.getPath('Admin/UserController');
      expect(path, '${tempDir.path}/lib/test_dir/admin/user_controller.dart');

      final simplePath = cmd.getPath('UserController');
      expect(simplePath, '${tempDir.path}/lib/test_dir/user_controller.dart');
    });

    test('buildClass replaces placeholders correctly', () {
      final content = cmd.buildClass('Admin/UserController');
      expect(
          content, 'class UserController {\n  // test lib/test_dir/admin\n}');
    });

    test('handle creates file successfully', () async {
      final results = parser.parse(['Admin/UserController']);
      cmd.arguments = results;

      await cmd.handle();

      final file =
          File('${tempDir.path}/lib/test_dir/admin/user_controller.dart');
      expect(file.existsSync(), true);
      expect(file.readAsStringSync(),
          'class UserController {\n  // test lib/test_dir/admin\n}');
    });

    test('handle aborts if file exists without --force', () async {
      // First run to create file
      var results = parser.parse(['UserController']);
      cmd.arguments = results;
      await cmd.handle();

      // Modify file to verify it's not overwritten
      final file = File('${tempDir.path}/lib/test_dir/user_controller.dart');
      file.writeAsStringSync('Modified');

      // Second run should fail
      results = parser.parse(['UserController']);
      cmd.arguments = results;

      // It won't throw, just print an error, but we can verify the file wasn't changed
      await cmd.handle();
      expect(file.readAsStringSync(), 'Modified');
    });

    test('handle overwrites if file exists with --force', () async {
      // First run to create file
      var results = parser.parse(['UserController']);
      cmd.arguments = results;
      await cmd.handle();

      // Modify file
      final file = File('${tempDir.path}/lib/test_dir/user_controller.dart');
      file.writeAsStringSync('Modified');

      // Second run with --force should overwrite
      results = parser.parse(['UserController', '--force']);
      cmd.arguments = results;

      await cmd.handle();
      expect(file.readAsStringSync(),
          'class UserController {\n  // test lib/test_dir\n}');
    });
  });
}
