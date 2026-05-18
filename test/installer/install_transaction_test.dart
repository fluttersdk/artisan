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

/// Stub driver that resolves stub names from a fixed in-memory map. Used by
/// the PublishFile payload-coverage test so a real stub body lands on disk.
class _MapStubDriverInline implements StubDriver {
  _MapStubDriverInline(this.stubs);

  final Map<String, String> stubs;

  @override
  String load(String name, {List<String>? searchPaths}) {
    final body = stubs[name];
    if (body == null) {
      throw StateError('Stub "$name" not registered in _MapStubDriverInline.');
    }
    return body;
  }

  @override
  String replace(String stub, Map<String, String> replacements) {
    var out = stub;
    replacements.forEach((k, v) {
      out = out.replaceAll('{{ $k }}', v).replaceAll('{{$k}}', v);
    });
    return out;
  }

  @override
  String make(String name, Map<String, String> replacements) =>
      replace(load(name), replacements);
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

  group('_serializeOp full payload coverage (Phase 3 Fix 1)', () {
    // Each test seeds a real on-disk project root so helper-backed ops can
    // dispatch without throwing, then asserts the persisted record entry
    // for that op carries every typed payload field, not just `{type: ...}`.
    Directory makeTempProject() {
      final tmp = Directory.systemTemp.createTempSync('artisan_tx_test_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      return tmp;
    }

    InstallContext realCtx(Directory root) {
      return InstallContext.test(
        fs: RealFs(),
        prompt: _SilentPromptDriver(),
        stubs: _SilentStubDriver(),
        clock: () => DateTime.utc(2025, 6, 1),
        projectRoot: root.path,
      );
    }

    Map<String, dynamic> recordFor(Directory root, String plugin) {
      final raw = File(
        '${root.path}/.artisan/installed/$plugin.json',
      ).readAsStringSync();
      return jsonDecode(raw) as Map<String, dynamic>;
    }

    test('PublishFile serializes sourceStubName + targetPath + replacements',
        () async {
      final root = makeTempProject();
      // Use a stub driver that returns the requested stub name verbatim.
      final ctx = InstallContext.test(
        fs: RealFs(),
        prompt: _SilentPromptDriver(),
        stubs: _MapStubDriverInline(const {
          'install/cfg.stub': 'hello {{ NAME }}',
        }),
        clock: () => DateTime.utc(2025, 6, 1),
        projectRoot: root.path,
      );
      final tx = InstallTransaction(ctx, pluginName: 'demo');
      tx.stage(const PublishFile(
        sourceStubName: 'install/cfg.stub',
        targetPath: 'lib/config/cfg.dart',
        replacements: {'NAME': 'world'},
      ));

      final result = await tx.commit();
      expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');

      final op = (recordFor(root, 'demo')['ops'] as List).single
          as Map<String, dynamic>;
      expect(op['type'], 'PublishFile');
      expect(op['sourceStubName'], 'install/cfg.stub');
      expect(op['targetPath'], 'lib/config/cfg.dart');
      expect(op['replacements'], {'NAME': 'world'});
    });

    test('AddDependency serializes name + version + isDev', () async {
      final root = makeTempProject();
      File('${root.path}/pubspec.yaml')
          .writeAsStringSync('name: app\ndependencies:\n');
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const AddDependency(name: 'intl', version: '^0.20.0'));
      tx.stage(const AddDependency(
          name: 'mocktail', version: '^1.0.0', isDev: true));

      // force: pubspec.yaml pre-existed and ConflictDetector flags it as
      // unmanaged on first install. The post-install record will hash it so
      // a subsequent install passes cleanly.
      final result = await tx.commit(force: true);
      expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');

      final ops =
          (recordFor(root, 'demo')['ops'] as List).cast<Map<String, dynamic>>();
      expect(ops[0], {
        'type': 'AddDependency',
        'name': 'intl',
        'version': '^0.20.0',
        'isDev': false
      });
      expect(ops[1], {
        'type': 'AddDependency',
        'name': 'mocktail',
        'version': '^1.0.0',
        'isDev': true
      });
    });

    test('AddPathDependency serializes name + path', () async {
      final root = makeTempProject();
      File('${root.path}/pubspec.yaml')
          .writeAsStringSync('name: app\ndependencies:\n');
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const AddPathDependency(name: 'my_lib', path: '../my_lib'));
      await tx.commit(force: true);

      final op = (recordFor(root, 'demo')['ops'] as List).single
          as Map<String, dynamic>;
      expect(op,
          {'type': 'AddPathDependency', 'name': 'my_lib', 'path': '../my_lib'});
    });

    test('RemoveDependency serializes name', () async {
      final root = makeTempProject();
      File('${root.path}/pubspec.yaml')
          .writeAsStringSync('name: app\ndependencies:\n  foo: ^1.0.0\n');
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const RemoveDependency(name: 'foo'));
      await tx.commit(force: true);

      final op = (recordFor(root, 'demo')['ops'] as List).single
          as Map<String, dynamic>;
      expect(op, {'type': 'RemoveDependency', 'name': 'foo'});
    });

    test('AddPubspecAsset serializes assetPath', () async {
      final root = makeTempProject();
      File('${root.path}/pubspec.yaml')
          .writeAsStringSync('name: app\nflutter:\n  assets:\n');
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const AddPubspecAsset(assetPath: 'assets/cfg.json'));
      await tx.commit(force: true);

      final op = (recordFor(root, 'demo')['ops'] as List).single
          as Map<String, dynamic>;
      expect(op, {'type': 'AddPubspecAsset', 'assetPath': 'assets/cfg.json'});
    });

    test('InjectEnvVar serializes key + value + comment', () async {
      final root = makeTempProject();
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const InjectEnvVar(
        key: 'API_KEY',
        value: 'secret',
        comment: 'managed by demo',
      ));
      await tx.commit();

      final op = (recordFor(root, 'demo')['ops'] as List).single
          as Map<String, dynamic>;
      expect(op, {
        'type': 'InjectEnvVar',
        'key': 'API_KEY',
        'value': 'secret',
        'comment': 'managed by demo',
      });
    });

    test(
        'Inject* native + web ops on absent platforms still serialize their '
        'typed payload', () async {
      // No android/, ios/, macos/, or web/ dirs: the dispatcher silently
      // skips, but the persisted record entry MUST still carry the full
      // payload so uninstall on a future re-init can reverse it.
      final root = makeTempProject();
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const InjectAndroidPermission(
          permission: 'android.permission.INTERNET'));
      tx.stage(
          const InjectAndroidMetaData(name: 'flutter.preview', value: 'true'));
      tx.stage(const InjectInfoPlistKey(
          key: 'NSCameraUsageDescription', value: 'why'));
      tx.stage(const InjectEntitlement(
          platform: 'ios', key: 'com.apple.security.app-sandbox', value: true));
      tx.stage(const InjectPodfileLine(platform: 'ios', line: "pod 'X'"));
      tx.stage(
          const InjectGradlePlugin(pluginId: 'com.google.x', version: '1.0'));
      tx.stage(const InjectGradleDependency(
          scope: 'implementation', notation: 'g:a:1'));
      tx.stage(const InjectIntoWebHead(content: '<script></script>'));
      tx.stage(const AddWebMetaTag(attributes: {'name': 'viewport'}));
      // RunShell uses /bin/echo via PATH-absent fallback in dart's Process,
      // workingDir omitted so the temp project root is used implicitly.
      tx.stage(const RunShell(command: 'true', args: []));

      final result = await tx.commit();
      expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');

      final ops =
          (recordFor(root, 'demo')['ops'] as List).cast<Map<String, dynamic>>();
      expect(ops[0], {
        'type': 'InjectAndroidPermission',
        'permission': 'android.permission.INTERNET'
      });
      expect(ops[1], {
        'type': 'InjectAndroidMetaData',
        'name': 'flutter.preview',
        'value': 'true',
      });
      expect(ops[2], {
        'type': 'InjectInfoPlistKey',
        'platform': 'ios',
        'key': 'NSCameraUsageDescription',
        'value': 'why',
      });
      expect(ops[3], {
        'type': 'InjectEntitlement',
        'platform': 'ios',
        'key': 'com.apple.security.app-sandbox',
        'value': 'true',
      });
      expect(ops[4],
          {'type': 'InjectPodfileLine', 'platform': 'ios', 'line': "pod 'X'"});
      expect(ops[5], {
        'type': 'InjectGradlePlugin',
        'pluginId': 'com.google.x',
        'version': '1.0'
      });
      expect(ops[6], {
        'type': 'InjectGradleDependency',
        'scope': 'implementation',
        'notation': 'g:a:1',
      });
      expect(ops[7],
          {'type': 'InjectIntoWebHead', 'content': '<script></script>'});
      expect(ops[8], {
        'type': 'AddWebMetaTag',
        'attributes': {'name': 'viewport'}
      });
      expect(ops[9], {
        'type': 'RunShell',
        'command': 'true',
        'args': <String>[],
      });
    });

    test('RunShell serializes command + args + workingDir when set', () async {
      final root = makeTempProject();
      Directory('${root.path}/sub').createSync(recursive: true);
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(RunShell(
        command: 'true',
        args: const ['ok'],
        workingDir: '${root.path}/sub',
      ));

      final result = await tx.commit();
      expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');

      final op = (recordFor(root, 'demo')['ops'] as List).single
          as Map<String, dynamic>;
      expect(op['type'], 'RunShell');
      expect(op['command'], 'true');
      expect(op['args'], ['ok']);
      expect(op['workingDir'], '${root.path}/sub');
    });

    test('main.dart + route registry ops serialize their typed payload',
        () async {
      final root = makeTempProject();
      // Pre-create both files with a minimal Magic.init scaffold so the
      // MainDartEditor + RouteRegistryEditor can locate their anchors.
      File('${root.path}/lib/main.dart').createSync(recursive: true);
      File('${root.path}/lib/main.dart').writeAsStringSync('''
import 'package:magic/magic.dart';

void main() async {
  await Magic.init();
  runApp(const MagicApplication());
}
''');
      File('${root.path}/lib/app/providers/route_service_provider.dart')
          .createSync(recursive: true);
      File('${root.path}/lib/app/providers/route_service_provider.dart')
          .writeAsStringSync('''
class RouteServiceProvider {
  Future<void> boot() async {
  }
}
''');
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const InjectMainDartImport(importStatement: "import 'x.dart';"));
      tx.stage(const InjectIntoMainDart(
          placement: MainDartPlacement.afterInit, code: 'Boot();'));
      tx.stage(const InjectRouteRegistration(functionName: 'registerXRoutes'));

      // force: pre-existing main.dart + route_service_provider.dart land as
      // unmanaged on first install; the post-write hash is recorded so a
      // subsequent install passes cleanly.
      final result = await tx.commit(force: true);
      expect(result, isA<Success>(), reason: 'Got: ${result.describe()}');

      final ops =
          (recordFor(root, 'demo')['ops'] as List).cast<Map<String, dynamic>>();
      expect(ops[0], {
        'type': 'InjectMainDartImport',
        'importStatement': "import 'x.dart';",
      });
      expect(ops[1], {
        'type': 'InjectIntoMainDart',
        'placement': 'afterInit',
        'code': 'Boot();',
      });
      expect(ops[2], {
        'type': 'InjectRouteRegistration',
        'functionName': 'registerXRoutes',
      });
    });

    test('MergeJson serializes targetPath + additive (NOT sourceData)',
        () async {
      final root = makeTempProject();
      File('${root.path}/data.json').writeAsStringSync('{"a":1}');
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const MergeJson(
        targetPath: 'data.json',
        sourceData: {'huge': 'payload'},
        additive: false,
      ));
      await tx.commit(force: true);

      final op = (recordFor(root, 'demo')['ops'] as List).single
          as Map<String, dynamic>;
      expect(op,
          {'type': 'MergeJson', 'targetPath': 'data.json', 'additive': false});
      // sourceData intentionally omitted to keep the record small.
      expect(op.containsKey('sourceData'), isFalse);
    });

    test('InjectImport / InjectBeforePattern / InjectAfterPattern serialize',
        () async {
      final root = makeTempProject();
      File('${root.path}/lib/x.dart').createSync(recursive: true);
      File('${root.path}/lib/x.dart').writeAsStringSync(
          "import 'a.dart';\n\nvoid main() {\n  Magic.init();\n}\n");
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const InjectImport(
        targetFile: 'lib/x.dart',
        importStatement: "import 'b.dart';",
      ));
      tx.stage(InjectBeforePattern(
        targetFile: 'lib/x.dart',
        pattern: RegExp(r'Magic\.init'),
        code: '// before',
      ));
      tx.stage(InjectAfterPattern(
        targetFile: 'lib/x.dart',
        pattern: RegExp(r'Magic\.init\(\);'),
        code: '// after',
      ));
      await tx.commit(force: true);

      final ops =
          (recordFor(root, 'demo')['ops'] as List).cast<Map<String, dynamic>>();
      expect(ops[0], {
        'type': 'InjectImport',
        'targetFile': 'lib/x.dart',
        'importStatement': "import 'b.dart';",
      });
      expect(ops[1]['type'], 'InjectBeforePattern');
      expect(ops[1]['targetFile'], 'lib/x.dart');
      expect(ops[1]['pattern'], contains('Magic'));
      expect(ops[1]['code'], '// before');
      expect(ops[2]['type'], 'InjectAfterPattern');
      expect(ops[2]['code'], '// after');
    });
  });

  group('_buildRecord helper-target hashes (Phase 3 Fix 3)', () {
    Directory makeTempProject() {
      final tmp = Directory.systemTemp.createTempSync('artisan_tx_hash_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      return tmp;
    }

    InstallContext realCtx(Directory root) {
      return InstallContext.test(
        fs: RealFs(),
        prompt: _SilentPromptDriver(),
        stubs: _SilentStubDriver(),
        clock: () => DateTime.utc(2025, 6, 1),
        projectRoot: root.path,
      );
    }

    test('AddDependency hashes the post-write pubspec.yaml content', () async {
      final root = makeTempProject();
      final pubspec = File('${root.path}/pubspec.yaml');
      pubspec.writeAsStringSync('name: app\ndependencies:\n');
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const AddDependency(name: 'intl', version: '^0.20.0'));
      await tx.commit(force: true);

      final record = jsonDecode(
          File('${root.path}/.artisan/installed/demo.json')
              .readAsStringSync()) as Map<String, dynamic>;
      final hashes = record['stubHashes'] as Map<String, dynamic>;
      final pubspecAbs = '${root.path}/pubspec.yaml';
      expect(hashes[pubspecAbs], isA<String>(),
          reason: 'helper-backed write must be hashed in the record so '
              'ConflictDetector treats a re-install as clean');
      expect((hashes[pubspecAbs] as String).length, 32);
    });

    test('InjectEnvVar hashes the post-write .env file', () async {
      final root = makeTempProject();
      final tx = InstallTransaction(realCtx(root), pluginName: 'demo');
      tx.stage(const InjectEnvVar(key: 'API', value: 'x'));
      await tx.commit();

      final record = jsonDecode(
          File('${root.path}/.artisan/installed/demo.json')
              .readAsStringSync()) as Map<String, dynamic>;
      final hashes = record['stubHashes'] as Map<String, dynamic>;
      expect(hashes['${root.path}/.env'], isA<String>());
    });
  });

  group('record-write happens BEFORE shell ops (Phase 3 Fix 4)', () {
    test('shell failure leaves the install record on disk', () async {
      final tmp = Directory.systemTemp.createTempSync('artisan_tx_shell_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final ctx = InstallContext.test(
        fs: RealFs(),
        prompt: _SilentPromptDriver(),
        stubs: _SilentStubDriver(),
        projectRoot: tmp.path,
      );
      final tx = InstallTransaction(ctx, pluginName: 'demo');
      tx.stage(const WriteFile(targetPath: 'lib/a.dart', content: 'a'));
      // Pick a command that will fail with a non-zero exit on every OS.
      tx.stage(const RunShell(command: 'false', args: []));

      final result = await tx.commit();

      expect(result, isA<Error>(),
          reason: 'shell op exit 1 must surface as Error');
      // CRITICAL: record must already exist so uninstall can clean up.
      final recordPath = '${tmp.path}/.artisan/installed/demo.json';
      expect(File(recordPath).existsSync(), isTrue,
          reason: 'record must be persisted BEFORE shell ops run so a shell '
              'failure leaves the install state recoverable via uninstall');
      // File written before shell phase should also be on disk.
      expect(File('${tmp.path}/lib/a.dart').existsSync(), isTrue);
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
