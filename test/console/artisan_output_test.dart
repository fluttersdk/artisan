import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('BufferedOutput', () {
    test('writeln appends text plus a newline', () {
      final output = BufferedOutput();

      output.writeln('hello');

      expect(output.content, 'hello\n');
    });

    test('writeln respects verbosity threshold', () {
      final output = BufferedOutput();

      output.writeln('verbose-only', level: 2);

      expect(output.content, isEmpty);
    });

    test('info, success, warning all flow through writeln', () {
      final output = BufferedOutput();

      output.info('i');
      output.success('s');
      output.warning('w');

      expect(output.content, 'i\ns\nw\n');
    });

    test('error wraps the text with [ERROR] prefix', () {
      final output = BufferedOutput();

      output.error('boom');

      expect(output.content, '[ERROR] boom\n');
    });

    test('comment honors level=2 default and verbosity gates', () {
      final low = BufferedOutput(verbosity: 1);
      final high = BufferedOutput(verbosity: 2);

      low.comment('quiet');
      high.comment('loud');

      expect(low.content, isEmpty);
      expect(high.content, 'loud\n');
    });

    test('debug only fires at verbosity 4', () {
      final low = BufferedOutput(verbosity: 1);
      final high = BufferedOutput(verbosity: 4);

      low.debug('quiet');
      high.debug('loud');

      expect(low.content, isEmpty);
      expect(high.content, contains('[debug] loud'));
    });
  });

  group('NullOutput', () {
    test('all writes are silent', () {
      final output = NullOutput();

      output.writeln('a');
      output.info('b');
      output.success('c');
      output.warning('d');
      output.error('e');
      output.comment('f');
      output.debug('g');

      expect(output.verbosity, 0);
    });
  });

  group('StdioOutput', () {
    test('constructor defaults to verbosity=1', () {
      expect(StdioOutput().verbosity, 1);
    });

    test('constructor accepts a custom verbosity', () {
      expect(StdioOutput(verbosity: 3).verbosity, 3);
    });

    test('all write methods run without throwing at verbosity=4', () {
      final output = StdioOutput(verbosity: 4);

      expect(() {
        output.writeln('w');
        output.info('i');
        output.success('s');
        output.warning('warn');
        output.error('e');
        output.comment('c');
        output.debug('d');
      }, returnsNormally);
    });

    test('write methods are silent below the verbosity threshold', () {
      final output = StdioOutput(verbosity: 0);

      expect(() {
        output.writeln('w');
        output.info('i');
        output.success('s');
        output.warning('warn');
        output.comment('c');
      }, returnsNormally);
    });
  });
}
