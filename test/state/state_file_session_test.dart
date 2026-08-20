import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Verifies that two projects driven at once do not share one state file.
///
/// `~/.artisan/state.json` was a single global slot. A second project's
/// `artisan start` silently took it over, and every connected command from
/// the first project then drove the second app, succeeding each time. The
/// measured case had a worktree in another repository rewrite the file
/// mid-session; two commands later produced a screenshot of an entirely
/// different product before anyone noticed.
void main() {
  group('StateFile session isolation', () {
    late Directory tempHome;
    late Directory projectA;
    late Directory projectB;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('artisan_session_');
      projectA = await Directory.systemTemp.createTemp('artisan_proj_a_');
      projectB = await Directory.systemTemp.createTemp('artisan_proj_b_');
      StateFile.debugHomeOverride = tempHome.path;
      StateFile.pathOverride = null;
    });

    tearDown(() async {
      StateFile.debugHomeOverride = null;
      StateFile.debugProjectRootOverride = null;
      StateFile.pathOverride = null;
      for (final Directory dir in <Directory>[
        tempHome,
        projectA,
        projectB,
      ]) {
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });

    test('two projects get two files', () {
      StateFile.debugProjectRootOverride = projectA.path;
      final String a = StateFile.path;
      StateFile.debugProjectRootOverride = projectB.path;
      final String b = StateFile.path;

      expect(a, isNot(equals(b)));
      expect(a, contains('/.artisan/sessions/'));
      expect(b, contains('/.artisan/sessions/'));
    });

    test('the same project resolves to the same file', () {
      StateFile.debugProjectRootOverride = projectA.path;
      final String first = StateFile.path;
      final String second = StateFile.path;

      expect(first, equals(second));
    });

    test('a write for one project is invisible to the other', () async {
      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.write(<String, dynamic>{
        'pid': 111,
        'projectRoot': projectA.path,
      });

      StateFile.debugProjectRootOverride = projectB.path;
      await StateFile.write(<String, dynamic>{
        'pid': 222,
        'projectRoot': projectB.path,
      });

      StateFile.debugProjectRootOverride = projectA.path;
      final Map<String, dynamic>? a = await StateFile.read();

      expect(
        a?['pid'],
        equals(111),
        reason: 'project B taking the global slot must not repoint project A',
      );
    });

    test('write mirrors to the legacy pointer for hand-written recipes',
        () async {
      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.write(<String, dynamic>{
        'pid': 111,
        'projectRoot': projectA.path,
      });

      final File pointer = File(StateFile.legacyPointerPath);
      expect(pointer.existsSync(), isTrue);
      final Map<String, dynamic> decoded =
          jsonDecode(pointer.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['pid'], equals(111));
    });

    test('read falls back to the legacy pointer when no session file exists',
        () async {
      // The documented recovery recipe is to hand-write ~/.artisan/state.json
      // when `artisan start` cannot boot the app. That has to keep working.
      final Directory dir = Directory('${tempHome.path}/.artisan');
      await dir.create(recursive: true);
      await File('${dir.path}/state.json').writeAsString(
        jsonEncode(<String, dynamic>{'pid': 999}),
      );

      StateFile.debugProjectRootOverride = projectA.path;
      final Map<String, dynamic>? got = await StateFile.read();

      expect(got?['pid'], equals(999));
    });

    test('pathOverride wins over the session path', () {
      StateFile.debugProjectRootOverride = projectA.path;
      StateFile.pathOverride = '${tempHome.path}/custom.json';

      expect(StateFile.path, equals('${tempHome.path}/custom.json'));
    });

    test('delete removes the session file and the matching pointer', () async {
      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.write(<String, dynamic>{
        'pid': 111,
        'projectRoot': projectA.path,
      });

      await StateFile.delete();

      expect(File(StateFile.path).existsSync(), isFalse);
      expect(File(StateFile.legacyPointerPath).existsSync(), isFalse);
    });

    test('delete leaves a pointer that belongs to another project', () async {
      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.write(<String, dynamic>{
        'pid': 111,
        'projectRoot': projectA.path,
      });
      StateFile.debugProjectRootOverride = projectB.path;
      await StateFile.write(<String, dynamic>{
        'pid': 222,
        'projectRoot': projectB.path,
      });

      // A stops. The pointer currently describes B, which is still running,
      // so taking it away would break B's connected commands.
      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.delete();

      final File pointer = File(StateFile.legacyPointerPath);
      expect(pointer.existsSync(), isTrue);
      final Map<String, dynamic> decoded =
          jsonDecode(pointer.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['pid'], equals(222));
    });

    test('a trailing separator resolves to the same session', () {
      // `artisan start` records `Directory.current.path`; a shell or a script
      // that appends a separator would otherwise open a SECOND session for
      // the same project and every connected command would miss the first.
      StateFile.debugProjectRootOverride = projectA.path;
      final String plain = StateFile.path;
      StateFile.debugProjectRootOverride =
          '${projectA.path}${Platform.pathSeparator}';
      final String trailing = StateFile.path;

      expect(trailing, equals(plain));
    });

    test('the same directory reached through a symlink is one session', () {
      // A git worktree checkout is routinely a symlink, and two sessions for
      // one project is the bug this whole file exists to prevent.
      final Link link = Link('${tempHome.path}/link-to-a');
      link.createSync(projectA.path);
      addTearDown(() => link.deleteSync());

      StateFile.debugProjectRootOverride = projectA.path;
      final String direct = StateFile.path;
      StateFile.debugProjectRootOverride = link.path;
      final String viaLink = StateFile.path;

      expect(viaLink, equals(direct));
    });

    test('without the debug override the session lands under the real home',
        () {
      // Every other test in this file pins the home directory, so the
      // production resolution has never run: a regression there would move
      // every session on every machine and no test would notice.
      StateFile.debugHomeOverride = null;
      StateFile.debugProjectRootOverride = projectA.path;

      final String home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '/tmp';

      expect(StateFile.path, startsWith('$home/.artisan/sessions/'));
      expect(StateFile.legacyPointerPath, equals('$home/.artisan/state.json'));
      expect(StateFile.homeDir, equals('$home/.artisan'));
    });

    test('delete leaves a pointer that records no project', () async {
      // The hand-written recovery file usually omits projectRoot, and the
      // read path honours it. Deleting it took away the escape hatch people
      // reach for precisely when `start` has already failed them.
      final Directory dir = Directory('${tempHome.path}/.artisan');
      await dir.create(recursive: true);
      await File('${dir.path}/state.json').writeAsString(
        jsonEncode(<String, dynamic>{'pid': 999}),
      );

      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.delete();

      expect(File(StateFile.legacyPointerPath).existsSync(), isTrue);
    });

    test('delete from a subdirectory still clears this project\'s pointer',
        () async {
      // `stop` run from `backend/` has no session file of its own, so the
      // fallback root is the subdirectory. Comparing exactly left the
      // pointer behind, advertising a session that had just been stopped.
      final Directory nested = Directory('${projectA.path}/backend');
      await nested.create(recursive: true);

      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.write(<String, dynamic>{
        'pid': 111,
        'projectRoot': projectA.path,
      });

      StateFile.debugProjectRootOverride = nested.path;
      await StateFile.delete();

      expect(File(StateFile.legacyPointerPath).existsSync(), isFalse);
    });

    test('the staging file is per process, not per path', () async {
      // The legacy pointer is shared, so two projects starting at once both
      // staged `state.json.tmp`; the loser's rename threw after flutter run
      // had already spawned.
      StateFile.debugProjectRootOverride = projectA.path;
      await StateFile.write(<String, dynamic>{'pid': 1});

      final List<String> leftovers = Directory('${tempHome.path}/.artisan')
          .listSync()
          .whereType<File>()
          .map((File f) => f.path)
          .where((String p) => p.endsWith('.tmp'))
          .toList();

      expect(leftovers, isEmpty, reason: 'staging files are renamed away');
    });

    test('a subdirectory of the project resolves to the project session', () {
      // `sessionOwnershipError` blesses running from `backend/` or a package
      // subdirectory, but the session FILE was keyed on the working
      // directory, so a command from there missed its own session, fell back
      // to the shared pointer, and with two apps up got refused for driving
      // somebody else's. The isolation only held for callers standing in the
      // repo root.
      File('${projectA.path}/pubspec.yaml').writeAsStringSync('name: proj_a\n');
      final Directory nested = Directory('${projectA.path}/packages/app');
      nested.createSync(recursive: true);

      StateFile.debugProjectRootOverride = projectA.path;
      final String fromRoot = StateFile.path;
      StateFile.debugProjectRootOverride = nested.path;
      final String fromNested = StateFile.path;

      expect(fromNested, equals(fromRoot));
    });

    test('a nested package with its own pubspec keeps its own session', () {
      // The walk stops at the NEAREST pubspec, because that is the unit
      // `artisan start` boots. Two packages in one repo are two apps.
      File('${projectA.path}/pubspec.yaml').writeAsStringSync('name: proj_a\n');
      final Directory inner = Directory('${projectA.path}/example');
      inner.createSync(recursive: true);
      File('${inner.path}/pubspec.yaml').writeAsStringSync('name: inner\n');

      StateFile.debugProjectRootOverride = projectA.path;
      final String outer = StateFile.path;
      StateFile.debugProjectRootOverride = inner.path;
      final String innerPath = StateFile.path;

      expect(innerPath, isNot(equals(outer)));
    });

    test('a directory with no pubspec anywhere above it keys on itself', () {
      // Non-Dart callers and the hand-written recovery recipe must not hit a
      // walk that climbs to the filesystem root and lands everyone in one
      // shared session.
      StateFile.debugProjectRootOverride = projectB.path;
      expect(StateFile.path, contains('/.artisan/sessions/'));
      expect(
        StateFile.path,
        equals(StateFile.sessionPathFor(projectB.path)),
      );
    });
  });
}
