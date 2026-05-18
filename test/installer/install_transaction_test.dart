import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Minimal no-op [PromptDriver] used in transaction tests; the orchestrator
/// never prompts so any answer is fine.
class _SilentPromptDriver implements PromptDriver {
  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) =>
      defaultValue ?? '';

  @override
  bool confirm(String question, {bool defaultValue = false}) => defaultValue;

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) =>
      defaultValue ?? options.first;

  @override
  String secret(String question) => '';
}

/// Minimal no-op [StubDriver] — transactions never resolve stubs themselves.
class _SilentStubDriver implements StubDriver {
  @override
  String load(String name, {List<String>? searchPaths}) => '';

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) => '';
}

/// Wraps an [InMemoryFs] and throws on the Nth `writeAsString` call. Used to
/// prove `commit()` rolls back all `.tmp` files when a partial write fails.
class _FailingFs implements VirtualFs {
  _FailingFs(this.inner, {required this.failOnWriteCall});

  final InMemoryFs inner;

  /// 1-based ordinal of the writeAsString call that should throw.
  final int failOnWriteCall;
  int _writes = 0;

  Map<String, String> get snapshot => inner.snapshot;

  @override
  bool exists(String absPath) => inner.exists(absPath);

  @override
  String readAsString(String absPath) => inner.readAsString(absPath);

  @override
  void writeAsString(String absPath, String content) {
    _writes++;
    if (_writes == failOnWriteCall) {
      throw FileSystemException('disk full', '/disk');
    }
    inner.writeAsString(absPath, content);
  }

  @override
  void delete(String absPath) => inner.delete(absPath);

  @override
  void copy(String fromAbs, String toAbs) => inner.copy(fromAbs, toAbs);

  @override
  void rename(String fromAbs, String toAbs) => inner.rename(fromAbs, toAbs);

  @override
  List<String> listSync(String absDir) => inner.listSync(absDir);

  @override
  String md5(String absPath) => inner.md5(absPath);
}

InstallContext _makeCtx({
  VirtualFs? fs,
  DateTime? fixedTime,
}) {
  return InstallContext.test(
    fs: fs ?? InMemoryFs(),
    prompt: _SilentPromptDriver(),
    stubs: _SilentStubDriver(),
    clock: fixedTime == null ? null : () => fixedTime,
    projectRoot: '/proj',
  );
}

void main() {
  group('stage() + pending state', () {
    test('pendingCount and pendingOps start at zero / empty', () {
      final tx = InstallTransaction(_makeCtx(), pluginName: 'demo');

      expect(tx.pendingCount, 0);
      expect(tx.pendingOps, isEmpty);
    });

    test('stage appends ops; pendingOps reflects insertion order', () {
      final tx = InstallTransaction(_makeCtx(), pluginName: 'demo');

      const a = WriteFile(targetPath: 'lib/a.dart', content: 'a');
      const b = WriteFile(targetPath: 'lib/b.dart', content: 'b');
      tx.stage(a);
      tx.stage(b);

      expect(tx.pendingCount, 2);
      expect(tx.pendingOps, [a, b]);
    });

    test('pendingOps returns an unmodifiable view', () {
      final tx = InstallTransaction(_makeCtx(), pluginName: 'demo');
      tx.stage(const WriteFile(targetPath: 'lib/a.dart', content: 'a'));

      expect(
        () => tx.pendingOps.add(
          const WriteFile(targetPath: 'x', content: 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('commit() — empty + Success', () {
    test('empty op list returns Success(opCount: 0)', () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(
        _makeCtx(fs: fs, fixedTime: DateTime.utc(2025, 1, 1)),
        pluginName: 'demo',
      );

      final result = await tx.commit();

      expect(result, isA<Success>());
      final success = result as Success;
      expect(success.opCount, 0);
      expect(success.recordPath, '/proj/.artisan/installed/demo.json');
    });
  });

  group('commit(dryRun: true)', () {
    test('writes the DRY RUN header + each op describe line, no fs writes',
        () async {
      final fs = InMemoryFs();
      final ctx = _makeCtx(fs: fs);
      final tx = InstallTransaction(ctx, pluginName: 'demo');
      tx.stage(const WriteFile(targetPath: 'lib/a.dart', content: 'a'));
      tx.stage(const DeleteFile(targetPath: 'lib/old.dart'));

      final result = await tx.commit(dryRun: true);

      expect(result, isA<DryRun>());
      expect((result as DryRun).opCount, 2);
      expect(fs.snapshot, isEmpty);

      final out = (ctx.artisanContext.output as BufferedOutput).content;
      expect(out, contains('DRY RUN'));
      expect(out, contains('2'));
      expect(out, contains('[write-file] lib/a.dart'));
      expect(out, contains('[delete-file] lib/old.dart'));
      expect(out, contains('No changes written'));
    });

    test('dry-run never writes the .artisan/installed/<plugin>.json record',
        () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.stage(const WriteFile(targetPath: 'lib/a.dart', content: 'a'));

      await tx.commit(dryRun: true);

      expect(fs.exists('/proj/.artisan/installed/demo.json'), isFalse);
    });
  });

  group('commit() — WriteFile dispatcher', () {
    test('WriteFile writes content to target absPath via VirtualFs', () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.stage(
        const WriteFile(targetPath: 'lib/hello.dart', content: 'print("hi");'),
      );

      final result = await tx.commit();

      expect(result, isA<Success>());
      expect(fs.readAsString('/proj/lib/hello.dart'), 'print("hi");');
    });

    test('WriteFile leaves no .tmp file behind after Success', () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.stage(
        const WriteFile(targetPath: 'lib/hello.dart', content: 'x'),
      );

      await tx.commit();

      final tmpKeys =
          fs.snapshot.keys.where((k) => k.endsWith('.tmp')).toList();
      expect(tmpKeys, isEmpty);
    });
  });

  group('commit() — DeleteFile dispatcher', () {
    test('DeleteFile removes target absPath from VirtualFs', () async {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/lib/old.dart', 'legacy');
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.stage(const DeleteFile(targetPath: 'lib/old.dart'));

      final result = await tx.commit();

      expect(result, isA<Success>());
      expect(fs.exists('/proj/lib/old.dart'), isFalse);
    });
  });

  group('commit() — CopyFile dispatcher', () {
    test('CopyFile preserves source and writes target with same content',
        () async {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/assets/tpl.dart', 'template body');
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.stage(
        const CopyFile(
          sourcePath: 'assets/tpl.dart',
          targetPath: 'lib/copied.dart',
        ),
      );

      final result = await tx.commit();

      expect(result, isA<Success>());
      expect(fs.readAsString('/proj/assets/tpl.dart'), 'template body');
      expect(fs.readAsString('/proj/lib/copied.dart'), 'template body');
    });
  });

  group('commit() — record file', () {
    test(
        'writes .artisan/installed/<plugin>.json with serialized ops + stubHashes',
        () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(
        _makeCtx(fs: fs, fixedTime: DateTime.utc(2025, 3, 1, 10, 30)),
        pluginName: 'magic_logger',
      );
      tx.stage(const WriteFile(targetPath: 'lib/x.dart', content: 'hello'));

      final result = await tx.commit();

      expect(result, isA<Success>());
      final recordPath = '/proj/.artisan/installed/magic_logger.json';
      expect(fs.exists(recordPath), isTrue);

      final record =
          jsonDecode(fs.readAsString(recordPath)) as Map<String, dynamic>;
      expect(record['plugin'], 'magic_logger');
      expect(record['installedAt'], '2025-03-01T10:30:00.000Z');

      final ops = record['ops'] as List<dynamic>;
      expect(ops, hasLength(1));
      expect((ops.first as Map<String, dynamic>)['type'], 'WriteFile');
      expect((ops.first as Map<String, dynamic>)['targetPath'], 'lib/x.dart');
      expect((ops.first as Map<String, dynamic>)['content'], 'hello');

      final hashes = record['stubHashes'] as Map<String, dynamic>;
      expect(hashes['/proj/lib/x.dart'], isA<String>());
      expect((hashes['/proj/lib/x.dart'] as String).length, 32);
    });

    test('plugin name threads into the record file path', () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(
        _makeCtx(fs: fs),
        pluginName: 'firebase_messaging',
      );

      final result = await tx.commit();

      expect(
        (result as Success).recordPath,
        '/proj/.artisan/installed/firebase_messaging.json',
      );
    });
  });

  group('commit() — conflict branch (Step 7 hook)', () {
    test('force = false with non-empty conflict stub returns Conflict result',
        () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.debugSetConflictsForTest(const [
        FileConflict(
            absPath: '/proj/lib/a.dart', reason: 'modified-since-install'),
      ]);
      tx.stage(const WriteFile(targetPath: 'lib/a.dart', content: 'new'));

      final result = await tx.commit();

      expect(result, isA<Conflict>());
      final conflict = result as Conflict;
      expect(conflict.conflicts, hasLength(1));
      expect(conflict.conflicts.first.absPath, '/proj/lib/a.dart');
      // No write should have happened, no record should exist.
      expect(fs.exists('/proj/lib/a.dart'), isFalse);
      expect(fs.exists('/proj/.artisan/installed/demo.json'), isFalse);
    });

    test('force = true bypasses conflicts and proceeds to Success', () async {
      final fs = InMemoryFs();
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.debugSetConflictsForTest(const [
        FileConflict(
            absPath: '/proj/lib/a.dart', reason: 'modified-since-install'),
      ]);
      tx.stage(const WriteFile(targetPath: 'lib/a.dart', content: 'new'));

      final result = await tx.commit(force: true);

      expect(result, isA<Success>());
      expect(fs.readAsString('/proj/lib/a.dart'), 'new');
    });
  });

  group('commit() — atomic rollback', () {
    test('mid-write failure rolls back all .tmp files; no target file persists',
        () async {
      final inner = InMemoryFs();
      // Fail on the SECOND writeAsString call (the second .tmp).
      final failing = _FailingFs(inner, failOnWriteCall: 2);
      final tx = InstallTransaction(_makeCtx(fs: failing), pluginName: 'demo');
      tx.stage(const WriteFile(targetPath: 'lib/a.dart', content: 'a'));
      tx.stage(const WriteFile(targetPath: 'lib/b.dart', content: 'b'));

      final result = await tx.commit();

      expect(result, isA<Error>());
      final err = result as Error;
      expect(err.rolledBack, isTrue);
      expect(err.error, contains('disk full'));

      // No .tmp file lingers and no target file was renamed into place.
      final keys = failing.snapshot.keys.toList();
      expect(keys.where((k) => k.endsWith('.tmp')), isEmpty);
      expect(failing.snapshot.containsKey('/proj/lib/a.dart'), isFalse);
      expect(failing.snapshot.containsKey('/proj/lib/b.dart'), isFalse);
      expect(
        failing.snapshot.containsKey('/proj/.artisan/installed/demo.json'),
        isFalse,
      );
    });
  });

  group('commit() — exhaustive sealed dispatch', () {
    test(
        'pattern matching exhaustively covers Success / DryRun / Conflict / Error',
        () async {
      String tag(TransactionResult r) {
        return switch (r) {
          Success() => 'success',
          DryRun() => 'dry',
          Conflict() => 'conflict',
          Error() => 'error',
        };
      }

      final tx1 = InstallTransaction(_makeCtx(), pluginName: 'demo');
      expect(tag(await tx1.commit()), 'success');

      final tx2 = InstallTransaction(_makeCtx(), pluginName: 'demo');
      expect(tag(await tx2.commit(dryRun: true)), 'dry');

      final tx3 = InstallTransaction(_makeCtx(), pluginName: 'demo');
      tx3.debugSetConflictsForTest(const [
        FileConflict(absPath: '/proj/x', reason: 'modified-since-install'),
      ]);
      tx3.stage(const WriteFile(targetPath: 'x', content: 'x'));
      expect(tag(await tx3.commit()), 'conflict');

      final tx4 = InstallTransaction(
        _makeCtx(fs: _FailingFs(InMemoryFs(), failOnWriteCall: 1)),
        pluginName: 'demo',
      );
      tx4.stage(const WriteFile(targetPath: 'x', content: 'x'));
      expect(tag(await tx4.commit()), 'error');
    });
  });

  group('commit() — one-shot semantics', () {
    test('calling commit a second time throws StateError', () async {
      final tx = InstallTransaction(_makeCtx(), pluginName: 'demo');
      await tx.commit();

      expect(
        () => tx.commit(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('dispatcher — platform-detection no-op', () {
    test(
        'InjectAndroidPermission on a non-Android project is a silent skip '
        '(returns Success, writes nothing platform-related)', () async {
      // No android/ directory under projectRoot, so the dispatcher must
      // emit an info-level skip line and complete the install without
      // touching any android files.
      final fs = InMemoryFs();
      final tx = InstallTransaction(_makeCtx(fs: fs), pluginName: 'demo');
      tx.stage(
        const InjectAndroidPermission(
            permission: 'android.permission.INTERNET'),
      );

      final result = await tx.commit();

      expect(result, isA<Success>());
      // The only artefact is the install record under .artisan/installed/.
      final manifestlike = fs.snapshot.keys
          .where((k) => k.contains('AndroidManifest.xml'))
          .toList();
      expect(manifestlike, isEmpty);
    });
  });

  group('TransactionResult.describe()', () {
    test('each subclass produces a non-empty human-readable describe', () {
      expect(
        const Success(opCount: 3, recordPath: '/x/y.json').describe(),
        contains('3'),
      );
      expect(const DryRun(opCount: 5).describe(), contains('5'));
      expect(
        const Conflict(conflicts: [
          FileConflict(absPath: '/x/a', reason: 'modified-since-install'),
        ]).describe(),
        contains('1'),
      );
      expect(
        const Error(error: 'boom', rolledBack: true).describe(),
        contains('boom'),
      );
    });
  });
}
