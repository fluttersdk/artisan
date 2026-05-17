import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

BufferedOutput _makeOutput() => BufferedOutput();

void main() {
  group('DryRunRenderer.render()', () {
    test('header includes op count and plugin name when supplied', () {
      final out = _makeOutput();
      DryRunRenderer.render(
        out,
        const [WriteFile(targetPath: 'lib/a.dart', content: 'a')],
        pluginName: 'demo',
      );

      final content = out.content;
      expect(content, contains('1'));
      expect(content, contains('demo'));
      expect(content, contains('DRY RUN'));
    });

    test('header includes op count without plugin name when omitted', () {
      final out = _makeOutput();
      DryRunRenderer.render(
        out,
        const [
          WriteFile(targetPath: 'lib/a.dart', content: 'a'),
          WriteFile(targetPath: 'lib/b.dart', content: 'b'),
        ],
      );

      final content = out.content;
      expect(content, contains('2'));
      expect(content, contains('DRY RUN'));
    });

    test('empty op list emits header and footer with zero ops', () {
      final out = _makeOutput();
      DryRunRenderer.render(out, const []);

      final content = out.content;
      expect(content, contains('0'));
      expect(content, contains('DRY RUN'));
      expect(content, contains('No changes written'));
    });

    test('each op produces a line via op.describe()', () {
      final out = _makeOutput();
      DryRunRenderer.render(
        out,
        const [
          AddDependency(name: 'foo', version: '^1.0.0'),
          WriteFile(targetPath: 'lib/x.dart', content: 'x'),
          RunShell(command: 'dart', args: ['format', '.']),
        ],
        pluginName: 'test_plugin',
      );

      final content = out.content;
      expect(content, contains('[add-dep] foo: ^1.0.0'));
      expect(content, contains('[write-file] lib/x.dart'));
      expect(content, contains('[run-shell] dart format .'));
    });

    test(
        'ops are grouped by category in fixed order: Pubspec then Filesystem '
        'then Shell', () {
      final out = _makeOutput();
      // Stage in a mixed order: Shell first, then Filesystem, then Pubspec.
      DryRunRenderer.render(
        out,
        const [
          RunShell(command: 'dart', args: ['format', '.']),
          WriteFile(targetPath: 'lib/x.dart', content: 'x'),
          AddDependency(name: 'foo', version: '^1.0.0'),
        ],
        pluginName: 'demo',
      );

      final content = out.content;
      // Pubspec section must appear before Filesystem section.
      final pubspecIdx = content.indexOf('[Pubspec]');
      final filesystemIdx = content.indexOf('[Filesystem]');
      final shellIdx = content.indexOf('[Shell]');

      expect(pubspecIdx, greaterThan(-1));
      expect(filesystemIdx, greaterThan(-1));
      expect(shellIdx, greaterThan(-1));
      expect(pubspecIdx, lessThan(filesystemIdx));
      expect(filesystemIdx, lessThan(shellIdx));
    });

    test('footer line is always present', () {
      final out = _makeOutput();
      DryRunRenderer.render(out, const [], pluginName: 'demo');

      expect(out.content, contains('No changes written'));
      expect(out.content, contains('--dry-run'));
    });

    test('empty categories are omitted from output', () {
      final out = _makeOutput();
      // Only a Shell op: Pubspec, Filesystem, Magic, Native, Web, Env headers
      // must not appear.
      DryRunRenderer.render(
        out,
        const [
          RunShell(command: 'flutter', args: ['pub', 'get'])
        ],
        pluginName: 'demo',
      );

      final content = out.content;
      expect(content, isNot(contains('[Pubspec]')));
      expect(content, isNot(contains('[Filesystem]')));
      expect(content, contains('[Shell]'));
    });
  });
}
