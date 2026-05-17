import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ConsoleStyle', () {
    test('success wraps in green + check', () {
      final out = ConsoleStyle.success('done');
      expect(out, contains('✓'));
      expect(out, contains('done'));
      expect(out, contains(ConsoleStyle.green));
      expect(out, contains(ConsoleStyle.reset));
    });

    test('error wraps in red + cross', () {
      final out = ConsoleStyle.error('boom');
      expect(out, contains('✗'));
      expect(out, contains('boom'));
      expect(out, contains(ConsoleStyle.red));
    });

    test('info, warning, comment, header wrap their messages', () {
      expect(ConsoleStyle.info('hi'), contains('hi'));
      expect(ConsoleStyle.warning('hi'), contains('hi'));
      expect(ConsoleStyle.comment('hi'), contains('hi'));
      expect(ConsoleStyle.header('hi'), contains('hi'));
    });

    test('step shows current/total counter', () {
      expect(ConsoleStyle.step(2, 5, 'installing'), contains('[2/5]'));
      expect(ConsoleStyle.step(2, 5, 'installing'), contains('installing'));
    });

    test('line and newLine helpers', () {
      expect(ConsoleStyle.line(), '─' * 50);
      expect(ConsoleStyle.line(char: '=', length: 3), '===');
      expect(ConsoleStyle.newLine(), '');
    });

    test('banner draws a 3-line box around title + version', () {
      final out = ConsoleStyle.banner('Magic CLI', '1.0.0');
      final lines = out.split('\n');
      expect(lines, hasLength(3));
      expect(lines[0], contains('╔'));
      expect(lines[1], contains('Magic CLI'));
      expect(lines[1], contains('1.0.0'));
      expect(lines[2], contains('╚'));
    });

    test('table renders headers, separator, and rows', () {
      final out = ConsoleStyle.table(
        <String>['Name', 'Status'],
        <List<String>>[
          <String>['User', 'Active'],
          <String>['Admin', 'Inactive'],
        ],
      );

      expect(out, contains('Name'));
      expect(out, contains('Status'));
      expect(out, contains('User'));
      expect(out, contains('Admin'));
      expect(out, contains('─'));
    });

    test('table returns empty string when headers empty', () {
      expect(ConsoleStyle.table(const <String>[], const []), '');
    });

    test('keyValue pads the key to the requested width', () {
      final out = ConsoleStyle.keyValue('Name', 'Anil', keyWidth: 10);
      expect(out, contains('Name'));
      expect(out, contains('Anil'));
    });
  });
}
