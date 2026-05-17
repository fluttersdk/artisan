import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/make_model_command.dart';

void main() {
  group('MakeModelCommand', () {
    late Directory tempDir;
    late MakeModelCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_model_');
      cmd = MakeModelCommand(testRoot: tempDir.path);
      parser = ArgParser();
      cmd.configure(parser);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('generates monitor.dart from "Monitor" input', () async {
      cmd.arguments = parser.parse(['Monitor']);
      await cmd.handle();

      final file = File('${tempDir.path}/lib/app/models/monitor.dart');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('class Monitor extends Model'));
      expect(content, contains("String get table => 'monitors'"));
      expect(content, contains("String get resource => 'monitors'"));
    });

    test('pluralization logic', () async {
      cmd.arguments = parser.parse(['Category']);
      await cmd.handle();

      final file = File('${tempDir.path}/lib/app/models/category.dart');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('class Category extends Model'));
      expect(content, contains("String get table => 'categories'"));
    });

    test('nested path creates correct directory structure', () async {
      cmd.arguments = parser.parse(['Admin/Profile']);
      await cmd.handle();

      final file = File('${tempDir.path}/lib/app/models/admin/profile.dart');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('class Profile extends Model'));
    });

    test('-m flag creates migration', () async {
      cmd.arguments = parser.parse(['Monitor', '-m']);
      await cmd.handle();

      final modelFile = File('${tempDir.path}/lib/app/models/monitor.dart');
      expect(modelFile.existsSync(), isTrue);

      final migDir = Directory('${tempDir.path}/lib/database/migrations');
      expect(migDir.existsSync(), isTrue);

      final files = migDir.listSync().whereType<File>().toList();
      expect(files.length, equals(1));
      expect(files.first.path, contains('_create_monitors_table.dart'));
    });

    test('-c flag creates controller', () async {
      cmd.arguments = parser.parse(['Monitor', '-c']);
      await cmd.handle();

      final modelFile = File('${tempDir.path}/lib/app/models/monitor.dart');
      expect(modelFile.existsSync(), isTrue);

      final ctrlFile =
          File('${tempDir.path}/lib/app/controllers/monitor_controller.dart');
      expect(ctrlFile.existsSync(), isTrue);
    });

    test(
        '--all flag creates model, migration, controller, factory, seeder, policy',
        () async {
      cmd.arguments = parser.parse(['Monitor', '--all']);
      await cmd.handle();

      expect(File('${tempDir.path}/lib/app/models/monitor.dart').existsSync(),
          isTrue);
      expect(
          File('${tempDir.path}/lib/app/controllers/monitor_controller.dart')
              .existsSync(),
          isTrue);
      expect(
          File('${tempDir.path}/lib/database/factories/monitor_factory.dart')
              .existsSync(),
          isTrue);
      expect(
          File('${tempDir.path}/lib/database/seeders/monitor_seeder.dart')
              .existsSync(),
          isTrue);
      expect(
          File('${tempDir.path}/lib/app/policies/monitor_policy.dart')
              .existsSync(),
          isTrue);

      final migDir = Directory('${tempDir.path}/lib/database/migrations');
      final migFiles = migDir.listSync().whereType<File>().toList();
      expect(migFiles.length, equals(1));
      expect(migFiles.first.path, contains('_create_monitors_table.dart'));
    });

    test('returns early when no name argument provided', () async {
      cmd.arguments = parser.parse([]);
      expect(() async => cmd.handle(), returnsNormally);
    });
  });
}
