import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Verifies that a command which ACTS on the recorded session refuses one
/// belonging to another project.
///
/// `stop` reads the state and sends SIGTERM to the pid it finds. The legacy
/// pointer describes whichever app started last, so running `stop` from a
/// project that has nothing up would reach across and kill a sibling's
/// running app, reporting a clean success while doing it.
void main() {
  group('StopCommand session ownership', () {
    late Directory tempHome;
    late Directory sibling;
    late List<int> killed;
    late bool Function(int, ProcessSignal) priorKill;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('artisan_stop_own_');
      sibling = await Directory.systemTemp.createTemp('artisan_sibling_');
      StateFile.debugHomeOverride = tempHome.path;
      StateFile.pathOverride = null;
      killed = <int>[];
      priorKill = StopCommand.stopKillFunction;
      StopCommand.stopKillFunction = (int pid, ProcessSignal _) {
        killed.add(pid);
        return true;
      };
    });

    tearDown(() async {
      StopCommand.stopKillFunction = priorKill;
      StateFile.debugHomeOverride = null;
      StateFile.debugProjectRootOverride = null;
      StateFile.pathOverride = null;
      for (final Directory dir in <Directory>[tempHome, sibling]) {
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });

    Future<void> writePointer(Map<String, dynamic> data) async {
      final Directory dir = Directory('${tempHome.path}/.artisan');
      await dir.create(recursive: true);
      await File('${dir.path}/state.json').writeAsString(jsonEncode(data));
    }

    test('refuses to stop an app owned by another project', () async {
      await writePointer(<String, dynamic>{
        'pid': 4242,
        'projectRoot': sibling.path,
      });
      StateFile.debugProjectRootOverride = Directory.current.path;

      final output = BufferedOutput();
      final int code = await StopCommand().handle(
        ArtisanContext.bare(MapInput(const {}), output),
      );

      expect(code, 1);
      expect(killed, isEmpty, reason: 'a sibling app must survive this');
      expect(output.content, contains('another project'));
    });

    test('stops an app owned by this project', () async {
      await writePointer(<String, dynamic>{
        'pid': 4242,
        'projectRoot': Directory.current.path,
      });
      StateFile.debugProjectRootOverride = Directory.current.path;

      final output = BufferedOutput();
      final int code = await StopCommand().handle(
        ArtisanContext.bare(MapInput(const {}), output),
      );

      expect(code, 0);
      expect(killed, contains(4242));
    });
  });
}
