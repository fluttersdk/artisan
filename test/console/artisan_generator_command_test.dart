import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ArtisanGeneratorCommand', () {
    late Directory projectRoot;
    late Directory stubsDir;

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync('artisan_gen_project_');
      File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync(
        'name: host_app\nversion: 0.0.1\n',
      );

      stubsDir = Directory.systemTemp.createTempSync('artisan_gen_stubs_');
      File(p.join(stubsDir.path, 'fake.stub'))
          .writeAsStringSync('class {{ className }} { /* {{ namespace }} */ }');
    });

    tearDown(() {
      if (projectRoot.existsSync()) {
        projectRoot.deleteSync(recursive: true);
      }
      if (stubsDir.existsSync()) {
        stubsDir.deleteSync(recursive: true);
      }
    });

    test('boot defaults to CommandBoot.none', () {
      final command = _FakeGenerator(projectRoot.path);

      expect(command.boot, CommandBoot.none);
    });

    test('configure registers a --force flag', () {
      final command = _FakeGenerator(projectRoot.path);
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options.containsKey('force'), isTrue);
    });

    test('getPath for a flat name lands under the default namespace', () {
      final command = _FakeGenerator(projectRoot.path);

      final filePath = command.getPath('UserController');

      expect(
        filePath,
        p.join(projectRoot.path, 'lib/app/fake', 'user_controller.dart'),
      );
    });

    test('getPath for a nested name preserves the directory', () {
      final command = _FakeGenerator(projectRoot.path);

      final filePath = command.getPath('Admin/UserController');

      expect(
        filePath,
        p.join(
          projectRoot.path,
          'lib/app/fake',
          'admin',
          'user_controller.dart',
        ),
      );
    });

    test('buildClass substitutes className via the raw-stub branch', () {
      // The buildClass helper takes a backwards-compat raw-string branch when
      // getStub() returns a string with spaces. We use it to exercise the
      // _replaceClass / _replaceNamespace branches without touching the
      // package's real assets/stubs directory.
      final raw =
          _FakeGenerator(projectRoot.path, rawStub: 'class {{ className }} {}');

      expect(raw.buildClass('Foo'), 'class Foo {}');
    });

    test('handle exits 1 when name argument is missing', () async {
      final command =
          _FakeGenerator(projectRoot.path, rawStub: 'class {{ className }} {}');
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(output.content, contains('missing: "name"'));
    });

    test('handle exits 1 when file already exists and --force absent',
        () async {
      final command =
          _FakeGenerator(projectRoot.path, rawStub: 'class {{ className }} {}');
      final ctx = ArtisanContext.bare(
        MapInput(const {}, positional: <String>['UserController']),
        BufferedOutput(),
      );
      final preExisting = command.getPath('UserController');
      File(preExisting).createSync(recursive: true);
      File(preExisting).writeAsStringSync('existing');

      final code = await command.handle(ctx);

      expect(code, 1);
    });

    test('handle writes the rendered file and exits 0', () async {
      final command =
          _FakeGenerator(projectRoot.path, rawStub: 'class {{ className }} {}');
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const {}, positional: <String>['UserController']),
        output,
      );

      final code = await command.handle(ctx);

      expect(code, 0);
      final filePath = command.getPath('UserController');
      expect(File(filePath).existsSync(), isTrue);
      expect(File(filePath).readAsStringSync(), 'class UserController {}');
      expect(output.content, contains('Created:'));
    });
  });
}

class _FakeGenerator extends ArtisanGeneratorCommand {
  _FakeGenerator(this._projectRoot, {this.rawStub = ''});

  final String _projectRoot;

  /// When set, buildClass uses the raw-string branch by returning it from
  /// getStub() with a space (so it skips StubLoader.load entirely).
  final String rawStub;

  @override
  String get name => 'make:fake';

  @override
  String get description => 'fake generator for tests';

  @override
  String getStub() => rawStub.isEmpty ? 'fake' : rawStub;

  @override
  String getDefaultNamespace() => 'lib/app/fake';

  @override
  String getProjectRoot() => _projectRoot;
}
