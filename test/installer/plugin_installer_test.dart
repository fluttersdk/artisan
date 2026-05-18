import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only driver fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

/// Minimal no-op prompt driver — PluginInstaller core never prompts.
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

/// Minimal no-op stub driver — PluginInstaller core never resolves stubs.
class _SilentStubDriver implements StubDriver {
  @override
  String load(String name, {List<String>? searchPaths}) => '';

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) => '';
}

InstallContext _makeCtx({VirtualFs? fs, DateTime? fixedTime}) {
  return InstallContext.test(
    fs: fs ?? InMemoryFs(),
    prompt: _SilentPromptDriver(),
    stubs: _SilentStubDriver(),
    clock: fixedTime == null ? null : () => fixedTime,
    projectRoot: '/proj',
  );
}

void main() {
  group('PluginInstaller — initial state', () {
    test('pendingCount starts at 0 and pendingOps is empty', () {
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo');

      expect(installer.pendingCount, 0);
      expect(installer.pendingOps, isEmpty);
    });

    test('pendingOps returns an unmodifiable view', () {
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo');
      installer.stageForTest(
        const WriteFile(targetPath: 'lib/a.dart', content: 'a'),
      );

      expect(
        () => installer.pendingOps.add(
          const WriteFile(targetPath: 'x', content: 'x'),
        ),
        throwsUnsupportedError,
      );
    });

    test('stageForTest enqueues ops; pendingOps reflects insertion order', () {
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo');

      const a = WriteFile(targetPath: 'lib/a.dart', content: 'a');
      const b = WriteFile(targetPath: 'lib/b.dart', content: 'b');
      installer.stageForTest(a);
      installer.stageForTest(b);

      expect(installer.pendingCount, 2);
      expect(installer.pendingOps, [a, b]);
    });
  });

  group('PluginInstaller — commit() empty op queue', () {
    test('returns Success(opCount: 0) and writes only the install record',
        () async {
      final fs = InMemoryFs();
      final installer = PluginInstaller(
        _makeCtx(fs: fs, fixedTime: DateTime.utc(2025, 4, 1)),
        pluginName: 'demo',
      );

      final result = await installer.commit();

      expect(result, isA<Success>());
      final success = result as Success;
      expect(success.opCount, 0);
      expect(success.recordPath, '/proj/.artisan/installed/demo.json');
      expect(fs.exists(success.recordPath), isTrue);
    });
  });

  group('PluginInstaller — startWith / endWith hooks', () {
    test('startWith hook fires before commit dispatches to InstallTransaction',
        () async {
      final calls = <String>[];
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo')
          .startWith((_) => calls.add('start'));

      expect(calls, isEmpty,
          reason: 'startWith must NOT fire at registration time');

      await installer.commit();

      expect(calls, ['start']);
    });

    test('endWith hook fires AFTER a Success result', () async {
      final calls = <String>[];
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo')
          .endWith((_) => calls.add('end'));

      final result = await installer.commit();

      expect(result, isA<Success>());
      expect(calls, ['end']);
    });

    test('startWith then endWith fire in lifecycle order around a Success',
        () async {
      final calls = <String>[];
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo')
          .startWith((_) => calls.add('start'))
          .endWith((_) => calls.add('end'));

      await installer.commit();

      expect(calls, ['start', 'end']);
    });

    test('endWith does NOT fire after a Conflict result', () async {
      final fs = InMemoryFs();
      // Pre-populate an unmanaged file at the target path; ConflictDetector
      // surfaces it as `unmanaged-file` because no plugin record exists.
      fs.writeAsString('/proj/lib/a.dart', 'user-owned content');

      final calls = <String>[];
      final installer = PluginInstaller(
        _makeCtx(fs: fs),
        pluginName: 'demo',
      ).endWith((_) => calls.add('end'));
      installer.stageForTest(
        const WriteFile(targetPath: 'lib/a.dart', content: 'plugin content'),
      );

      final result = await installer.commit();

      expect(result, isA<Conflict>());
      expect(calls, isEmpty,
          reason:
              'endWith must NOT fire when the transaction returned Conflict');
    });

    test('endWith does NOT fire after an Error result', () async {
      final calls = <String>[];
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo')
          .endWith((_) => calls.add('end'));
      // CopyFile reads the source at stage time; pointing at a missing
      // source forces a real stage-time Error so endWith must stay silent.
      installer.stageForTest(
        const CopyFile(
          sourcePath: 'lib/nope_does_not_exist.dart',
          targetPath: 'lib/out.dart',
        ),
      );

      final result = await installer.commit();

      expect(result, isA<Error>());
      expect(calls, isEmpty,
          reason: 'endWith must NOT fire when the transaction returned Error');
    });

    test('startWith still fires even when commit returns Conflict', () async {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/lib/a.dart', 'user-owned content');

      final calls = <String>[];
      final installer = PluginInstaller(
        _makeCtx(fs: fs),
        pluginName: 'demo',
      ).startWith((_) => calls.add('start'));
      installer.stageForTest(
        const WriteFile(targetPath: 'lib/a.dart', content: 'plugin content'),
      );

      final result = await installer.commit();

      expect(result, isA<Conflict>());
      expect(calls, ['start'],
          reason:
              'startWith fires before the dispatch attempt regardless of outcome');
    });

    test('startWith and endWith receive the bound InstallContext', () async {
      final ctx = _makeCtx();
      final captured = <InstallContext>[];
      final installer = PluginInstaller(ctx, pluginName: 'demo')
          .startWith(captured.add)
          .endWith(captured.add);

      await installer.commit();

      expect(captured, hasLength(2));
      expect(identical(captured[0], ctx), isTrue);
      expect(identical(captured[1], ctx), isTrue);
    });
  });

  group(
      'PluginInstaller — commit dispatches staged ops through InstallTransaction',
      () {
    test('WriteFile ops surface on the filesystem after Success', () async {
      final fs = InMemoryFs();
      final installer = PluginInstaller(_makeCtx(fs: fs), pluginName: 'demo');
      installer.stageForTest(
        const WriteFile(targetPath: 'lib/x.dart', content: 'x'),
      );

      final result = await installer.commit();

      expect(result, isA<Success>());
      expect((result as Success).opCount, 1);
      expect(fs.readAsString('/proj/lib/x.dart'), 'x');
    });

    test('dry-run dispatches without touching disk and returns DryRun',
        () async {
      final fs = InMemoryFs();
      final installer = PluginInstaller(_makeCtx(fs: fs), pluginName: 'demo');
      installer.stageForTest(
        const WriteFile(targetPath: 'lib/x.dart', content: 'x'),
      );

      final result = await installer.commit(dryRun: true);

      expect(result, isA<DryRun>());
      expect((result as DryRun).opCount, 1);
      expect(fs.exists('/proj/lib/x.dart'), isFalse);
    });

    test('force bypasses the Conflict gate and proceeds to Success', () async {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/lib/a.dart', 'user-owned content');
      final installer = PluginInstaller(_makeCtx(fs: fs), pluginName: 'demo');
      installer.stageForTest(
        const WriteFile(targetPath: 'lib/a.dart', content: 'plugin content'),
      );

      final result = await installer.commit(force: true);

      expect(result, isA<Success>());
      expect(fs.readAsString('/proj/lib/a.dart'), 'plugin content');
    });

    test('plugin name threads through to the install record path', () async {
      final fs = InMemoryFs();
      final installer = PluginInstaller(
        _makeCtx(fs: fs),
        pluginName: 'firebase_messaging',
      );

      final result = await installer.commit();

      expect(
        (result as Success).recordPath,
        '/proj/.artisan/installed/firebase_messaging.json',
      );
    });
  });

  group('PluginInstaller — one-shot enforcement', () {
    test('a second commit() on the same instance throws StateError', () async {
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo');
      await installer.commit();

      expect(
        () => installer.commit(),
        throwsA(isA<StateError>()),
      );
    });

    test('one-shot guard fires for every terminal result kind (Conflict)',
        () async {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/lib/a.dart', 'user-owned');
      final installer = PluginInstaller(_makeCtx(fs: fs), pluginName: 'demo');
      installer.stageForTest(
        const WriteFile(targetPath: 'lib/a.dart', content: 'plugin'),
      );

      final first = await installer.commit();
      expect(first, isA<Conflict>());

      expect(() => installer.commit(), throwsA(isA<StateError>()));
    });

    test('one-shot guard fires for every terminal result kind (Error)',
        () async {
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo');
      installer.stageForTest(
        const CopyFile(
          sourcePath: 'lib/missing_source.dart',
          targetPath: 'lib/out.dart',
        ),
      );

      final first = await installer.commit();
      expect(first, isA<Error>());

      expect(() => installer.commit(), throwsA(isA<StateError>()));
    });

    test('one-shot guard fires after DryRun too — no replay against stale ops',
        () async {
      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo');

      final first = await installer.commit(dryRun: true);
      expect(first, isA<DryRun>());

      expect(() => installer.commit(), throwsA(isA<StateError>()));
    });
  });

  group('PluginInstaller — TransactionResult is exhaustively pattern-matchable',
      () {
    test('switch over the sealed hierarchy compiles + dispatches correctly',
        () async {
      String tag(TransactionResult r) {
        return switch (r) {
          Success() => 'success',
          DryRun() => 'dry',
          Conflict() => 'conflict',
          Error() => 'error',
        };
      }

      final installer = PluginInstaller(_makeCtx(), pluginName: 'demo');
      final result = await installer.commit();

      expect(tag(result), 'success');
    });
  });
}
