import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Shared contract suite. Runs against both [RealFs] (backed by a real temp
/// directory) and [InMemoryFs] (backed by a [Map]) to guarantee parity.
///
/// [makeAbsPath] turns a logical filename into an absolute path the
/// implementation under test understands. For [RealFs] this joins the temp
/// directory; for [InMemoryFs] it just prefixes a synthetic root.
typedef PathBuilder = String Function(String relative);

void main() {
  group('RealFs', () {
    late Directory tempDir;
    late RealFs fs;

    String abs(String relative) => p.join(tempDir.path, relative);

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_vfs_real_');
      fs = const RealFs();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('writeAsString + readAsString round-trips content', () {
      final path = abs('hello.txt');

      fs.writeAsString(path, 'hello world');

      expect(fs.readAsString(path), 'hello world');
    });

    test('exists returns true for existing file, false otherwise', () {
      final path = abs('present.txt');
      fs.writeAsString(path, 'x');

      expect(fs.exists(path), isTrue);
      expect(fs.exists(abs('absent.txt')), isFalse);
    });

    test('readAsString throws FileSystemException when missing', () {
      expect(
        () => fs.readAsString(abs('missing.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('writeAsString auto-creates parent directories', () {
      final path = abs('nested/dir/file.txt');

      fs.writeAsString(path, 'content');

      expect(File(path).existsSync(), isTrue);
      expect(fs.readAsString(path), 'content');
    });

    test('delete removes an existing file', () {
      final path = abs('to_delete.txt');
      fs.writeAsString(path, 'gone');

      fs.delete(path);

      expect(fs.exists(path), isFalse);
    });

    test('delete is idempotent on missing files', () {
      expect(() => fs.delete(abs('never_existed.txt')), returnsNormally);
    });

    test('copy preserves content and auto-creates parent', () {
      final from = abs('a.txt');
      final to = abs('nested/b.txt');
      fs.writeAsString(from, 'payload');

      fs.copy(from, to);

      expect(fs.readAsString(to), 'payload');
      expect(fs.exists(from), isTrue);
    });

    test('copy throws FileSystemException when source missing', () {
      expect(
        () => fs.copy(abs('absent.txt'), abs('dest.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rename moves content and removes the source', () {
      final from = abs('original.txt');
      final to = abs('renamed.txt');
      fs.writeAsString(from, 'data');

      fs.rename(from, to);

      expect(fs.exists(from), isFalse);
      expect(fs.readAsString(to), 'data');
    });

    test('rename overwrites destination when present', () {
      final from = abs('src.txt');
      final to = abs('dst.txt');
      fs.writeAsString(from, 'new');
      fs.writeAsString(to, 'old');

      fs.rename(from, to);

      expect(fs.readAsString(to), 'new');
      expect(fs.exists(from), isFalse);
    });

    test('rename throws FileSystemException when source missing', () {
      expect(
        () => fs.rename(abs('nope.txt'), abs('whatever.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('listSync returns filenames only, non-recursive', () {
      fs.writeAsString(abs('a.txt'), '1');
      fs.writeAsString(abs('b.txt'), '2');
      fs.writeAsString(abs('sub/c.txt'), '3');

      final entries = fs.listSync(tempDir.path);

      expect(entries, containsAll(<String>['a.txt', 'b.txt']));
      expect(entries, isNot(contains('c.txt')));
    });

    test('md5 produces a deterministic hash', () {
      final path = abs('hash.txt');
      fs.writeAsString(path, 'consistent content');

      final first = fs.md5(path);
      final second = fs.md5(path);

      expect(first, second);
      expect(first.length, 32); // md5 hex = 32 chars
    });

    test('md5 throws FileSystemException when file missing', () {
      expect(
        () => fs.md5(abs('absent.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('InMemoryFs', () {
    late InMemoryFs fs;

    String abs(String relative) => '/virtual/$relative';

    setUp(() {
      fs = InMemoryFs();
    });

    test('writeAsString + readAsString round-trips content', () {
      fs.writeAsString(abs('hello.txt'), 'hello world');

      expect(fs.readAsString(abs('hello.txt')), 'hello world');
    });

    test('exists returns true for existing file, false otherwise', () {
      fs.writeAsString(abs('present.txt'), 'x');

      expect(fs.exists(abs('present.txt')), isTrue);
      expect(fs.exists(abs('absent.txt')), isFalse);
    });

    test('readAsString throws FileSystemException when missing', () {
      expect(
        () => fs.readAsString(abs('missing.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('writeAsString does not require parent creation step', () {
      fs.writeAsString(abs('nested/dir/file.txt'), 'content');

      expect(fs.readAsString(abs('nested/dir/file.txt')), 'content');
    });

    test('delete removes an existing entry', () {
      fs.writeAsString(abs('to_delete.txt'), 'gone');

      fs.delete(abs('to_delete.txt'));

      expect(fs.exists(abs('to_delete.txt')), isFalse);
    });

    test('delete is idempotent on missing entries', () {
      expect(() => fs.delete(abs('never_existed.txt')), returnsNormally);
    });

    test('copy preserves content', () {
      fs.writeAsString(abs('a.txt'), 'payload');

      fs.copy(abs('a.txt'), abs('nested/b.txt'));

      expect(fs.readAsString(abs('nested/b.txt')), 'payload');
      expect(fs.exists(abs('a.txt')), isTrue);
    });

    test('copy throws FileSystemException when source missing', () {
      expect(
        () => fs.copy(abs('absent.txt'), abs('dest.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('snapshot exposes an unmodifiable view of the underlying map', () {
      fs.writeAsString(abs('a.txt'), '1');

      final snap = fs.snapshot;

      expect(snap[abs('a.txt')], '1');
      expect(() => snap['mutation'] = 'x', throwsUnsupportedError);
    });

    test('rename moves content and removes the source', () {
      fs.writeAsString(abs('original.txt'), 'data');

      fs.rename(abs('original.txt'), abs('renamed.txt'));

      expect(fs.exists(abs('original.txt')), isFalse);
      expect(fs.readAsString(abs('renamed.txt')), 'data');
    });

    test('rename overwrites destination when present', () {
      fs.writeAsString(abs('src.txt'), 'new');
      fs.writeAsString(abs('dst.txt'), 'old');

      fs.rename(abs('src.txt'), abs('dst.txt'));

      expect(fs.readAsString(abs('dst.txt')), 'new');
      expect(fs.exists(abs('src.txt')), isFalse);
    });

    test('rename throws FileSystemException when source missing', () {
      expect(
        () => fs.rename(abs('nope.txt'), abs('whatever.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('listSync returns filenames only, non-recursive', () {
      fs.writeAsString(abs('a.txt'), '1');
      fs.writeAsString(abs('b.txt'), '2');
      fs.writeAsString(abs('sub/c.txt'), '3');

      final entries = fs.listSync('/virtual');

      expect(entries, containsAll(<String>['a.txt', 'b.txt']));
      expect(entries, isNot(contains('c.txt')));
      expect(entries, isNot(contains('sub/c.txt')));
    });

    test('md5 produces a deterministic hash', () {
      fs.writeAsString(abs('hash.txt'), 'consistent content');

      final first = fs.md5(abs('hash.txt'));
      final second = fs.md5(abs('hash.txt'));

      expect(first, second);
      expect(first.length, 32);
    });

    test('md5 throws FileSystemException when file missing', () {
      expect(
        () => fs.md5(abs('absent.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('md5 matches RealFs hash for identical content', () {
      // Cross-implementation parity: the same bytes yield the same digest
      // regardless of where they live.
      final realDir = Directory.systemTemp.createTempSync('artisan_vfs_xref_');
      addTearDown(() {
        if (realDir.existsSync()) realDir.deleteSync(recursive: true);
      });

      const payload = 'parity check';
      final realPath = p.join(realDir.path, 'parity.txt');

      const realFs = RealFs();
      realFs.writeAsString(realPath, payload);
      fs.writeAsString(abs('parity.txt'), payload);

      expect(fs.md5(abs('parity.txt')), realFs.md5(realPath));
    });
  });
}
