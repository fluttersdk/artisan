import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Minimal no-op [PromptDriver] for conflict-detector tests.
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

/// Minimal no-op [StubDriver] for conflict-detector tests.
class _SilentStubDriver implements StubDriver {
  @override
  String load(String name, {List<String>? searchPaths}) => '';

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) => '';
}

InstallContext _makeCtx({required VirtualFs fs}) {
  return InstallContext.test(
    fs: fs,
    prompt: _SilentPromptDriver(),
    stubs: _SilentStubDriver(),
    projectRoot: '/proj',
  );
}

/// Writes a plugin record file at the expected location.
///
/// The [hashes] map keys are absolute paths; values are md5 hex strings.
void _writeRecord(
  InMemoryFs fs,
  String pluginName,
  Map<String, String> hashes,
) {
  final recordPath = '/proj/.artisan/installed/$pluginName.json';
  final record = <String, dynamic>{
    'plugin': pluginName,
    'installedAt': '2025-01-01T00:00:00.000Z',
    'ops': <dynamic>[],
    'stubHashes': hashes,
  };
  fs.writeAsString(recordPath, jsonEncode(record));
}

void main() {
  group('ConflictDetector.detect()', () {
    test('returns empty list when target file does not exist (clean install)',
        () {
      final fs = InMemoryFs();
      // No pre-existing file at /proj/lib/a.dart.
      final ctx = _makeCtx(fs: fs);
      final detector = ConflictDetector(ctx);

      final conflicts = detector.detect(
        const [WriteFile(targetPath: 'lib/a.dart', content: 'hello')],
        pluginName: 'demo',
      );

      expect(conflicts, isEmpty);
    });

    test(
        'returns unmanaged-file conflict when file exists but no record file '
        'is present', () {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/lib/a.dart', 'existing content');
      // No record file written.
      final ctx = _makeCtx(fs: fs);
      final detector = ConflictDetector(ctx);

      final conflicts = detector.detect(
        const [WriteFile(targetPath: 'lib/a.dart', content: 'new')],
        pluginName: 'demo',
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.first.absPath, '/proj/lib/a.dart');
      expect(conflicts.first.reason, 'unmanaged-file');
    });

    test(
        'returns no conflict when file exists and recorded hash matches '
        'current file content', () {
      final fs = InMemoryFs();
      const fileContent = 'unchanged content';
      fs.writeAsString('/proj/lib/a.dart', fileContent);
      // Record the md5 of the current content so it looks unmodified.
      final currentHash = fs.md5('/proj/lib/a.dart');
      _writeRecord(fs, 'demo', {'/proj/lib/a.dart': currentHash});
      final ctx = _makeCtx(fs: fs);
      final detector = ConflictDetector(ctx);

      final conflicts = detector.detect(
        const [WriteFile(targetPath: 'lib/a.dart', content: 'new')],
        pluginName: 'demo',
      );

      expect(conflicts, isEmpty);
    });

    test(
        'returns modified-since-last-known-stub conflict when file exists and '
        'recorded hash diverges from current content', () {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/lib/a.dart', 'original content');
      final originalHash = fs.md5('/proj/lib/a.dart');
      // Now the user modifies the file.
      fs.writeAsString('/proj/lib/a.dart', 'user-modified content');
      // Record still holds the original hash.
      _writeRecord(fs, 'demo', {'/proj/lib/a.dart': originalHash});
      final ctx = _makeCtx(fs: fs);
      final detector = ConflictDetector(ctx);

      final conflicts = detector.detect(
        const [WriteFile(targetPath: 'lib/a.dart', content: 'new')],
        pluginName: 'demo',
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.first.absPath, '/proj/lib/a.dart');
      expect(conflicts.first.reason, 'modified-since-last-known-stub');
      expect(conflicts.first.lastKnownHash, originalHash);
      expect(conflicts.first.currentHash, fs.md5('/proj/lib/a.dart'));
    });

    test(
        'handles mixed ops: some clean, some conflicting, across multiple files',
        () {
      final fs = InMemoryFs();
      // File A: unmodified (matching hash).
      const contentA = 'content a';
      fs.writeAsString('/proj/lib/a.dart', contentA);
      final hashA = fs.md5('/proj/lib/a.dart');
      // File B: user-modified (diverging hash).
      fs.writeAsString('/proj/lib/b.dart', 'original b');
      final originalHashB = fs.md5('/proj/lib/b.dart');
      fs.writeAsString('/proj/lib/b.dart', 'user changed b');
      // File C: does not exist yet (clean install).
      _writeRecord(fs, 'demo', {
        '/proj/lib/a.dart': hashA,
        '/proj/lib/b.dart': originalHashB,
      });
      final ctx = _makeCtx(fs: fs);
      final detector = ConflictDetector(ctx);

      final conflicts = detector.detect(
        const [
          WriteFile(targetPath: 'lib/a.dart', content: 'new a'),
          WriteFile(targetPath: 'lib/b.dart', content: 'new b'),
          WriteFile(targetPath: 'lib/c.dart', content: 'new c'),
        ],
        pluginName: 'demo',
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.first.absPath, '/proj/lib/b.dart');
      expect(conflicts.first.reason, 'modified-since-last-known-stub');
    });

    test(
        'RunShell and AddDependency ops are filtered out and never produce '
        'conflicts', () {
      final fs = InMemoryFs();
      final ctx = _makeCtx(fs: fs);
      final detector = ConflictDetector(ctx);

      final conflicts = detector.detect(
        const [
          RunShell(command: 'dart', args: ['format', '.']),
          AddDependency(name: 'foo', version: '^1.0.0'),
          RemoveDependency(name: 'bar'),
        ],
        pluginName: 'demo',
      );

      expect(conflicts, isEmpty);
    });
  });
}
