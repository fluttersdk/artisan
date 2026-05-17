import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MakeCommandCommand', () {
    test('metadata: name=make:command, boot=none', () {
      final command = MakeCommandCommand();

      expect(command.name, 'make:command');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('declares the canonical stub name + default namespace', () {
      final command = MakeCommandCommand();

      expect(command.getStub(), 'artisan_command');
      expect(command.getDefaultNamespace(), 'lib/app/commands');
    });

    test('inherits from ArtisanGeneratorCommand', () {
      final command = MakeCommandCommand();

      expect(command, isA<ArtisanGeneratorCommand>());
    });

    test('getPath composes the default namespace + snake-cased file name', () {
      final command = _ProjectRootOverride();

      final filePath = command.getPath('SyncMonitors');

      expect(
        filePath,
        p.join(command.fakeRoot, 'lib/app/commands', 'sync_monitors.dart'),
      );
    });

    test('getPath honors nested name segments', () {
      final command = _ProjectRootOverride();

      final filePath = command.getPath('Admin/Cleanup');

      expect(
        filePath,
        p.join(
          command.fakeRoot,
          'lib/app/commands',
          'admin',
          'cleanup.dart',
        ),
      );
    });
  });
}

class _ProjectRootOverride extends MakeCommandCommand {
  _ProjectRootOverride() {
    fakeRoot = Directory.systemTemp.createTempSync('artisan_mkc_').path;
  }

  late String fakeRoot;

  @override
  String getProjectRoot() => fakeRoot;
}
