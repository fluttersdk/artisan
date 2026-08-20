import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Verifies that a connected command refuses to drive an app belonging to a
/// different project.
///
/// Per-project session files stop the two apps from sharing a slot, but the
/// legacy pointer is still read when this project has no session of its own,
/// and it describes whichever app started last. Without a check, a command
/// run from project A while only project B is up would connect to B and
/// succeed: that is the failure that once produced a screenshot of an
/// entirely different product.
void main() {
  group('sessionOwnershipError', () {
    late Directory projectA;
    late Directory projectB;

    setUp(() async {
      projectA = await Directory.systemTemp.createTemp('artisan_own_a_');
      projectB = await Directory.systemTemp.createTemp('artisan_own_b_');
    });

    tearDown(() async {
      for (final Directory dir in <Directory>[projectA, projectB]) {
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });

    test('accepts state whose projectRoot is the working directory', () {
      expect(
        sessionOwnershipError(
          state: <String, dynamic>{'projectRoot': projectA.path},
          workingDirectory: projectA.path,
        ),
        isNull,
      );
    });

    test('accepts a working directory inside the project', () async {
      // Running from `backend/` or a package subdirectory is normal and must
      // not read as somebody else's session.
      final Directory nested = Directory('${projectA.path}/backend');
      await nested.create(recursive: true);

      expect(
        sessionOwnershipError(
          state: <String, dynamic>{'projectRoot': projectA.path},
          workingDirectory: nested.path,
        ),
        isNull,
      );
    });

    test('rejects state belonging to another project', () {
      final String? error = sessionOwnershipError(
        state: <String, dynamic>{'projectRoot': projectB.path},
        workingDirectory: projectA.path,
      );

      expect(error, isNotNull);
      expect(error, contains(projectB.path));
      expect(error, contains('another project'));
    });

    test('accepts state with no recorded projectRoot', () {
      // Hand-written state from the documented recovery recipe often omits
      // it. Refusing there would break the escape hatch people reach for
      // precisely when `artisan start` has already failed them.
      expect(
        sessionOwnershipError(
          state: <String, dynamic>{'pid': 1},
          workingDirectory: projectA.path,
        ),
        isNull,
      );
    });

    test('accepts anything when the caller named the state file', () {
      expect(
        sessionOwnershipError(
          state: <String, dynamic>{'projectRoot': projectB.path},
          workingDirectory: projectA.path,
          explicitStatePath: '/tmp/somewhere.json',
        ),
        isNull,
      );
    });

    test('ARTISAN_STATE_FILE counts as naming the session', () {
      // Both spellings are documented as equivalent and `path` honours both,
      // so a guard that saw only the flag read the session the env var
      // pointed at and then refused to drive it.
      expect(
        sessionOwnershipError(
          state: <String, dynamic>{'projectRoot': projectB.path},
          workingDirectory: projectA.path,
          explicitStatePath: '/tmp/named.json',
        ),
        isNull,
      );
    });
  });
}
