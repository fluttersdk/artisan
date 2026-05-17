import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('parsePidLines', () {
    test('parses both HOLDER and FLUTTER tags', () {
      final got = parsePidLines(<String>['HOLDER=1234', 'FLUTTER=5678']);
      expect(got, {'HOLDER': 1234, 'FLUTTER': 5678});
    });

    test('returns empty map for empty input', () {
      expect(parsePidLines(const <String>[]), isEmpty);
    });

    test('skips unknown tags', () {
      final got = parsePidLines(<String>[
        'HOLDER=1',
        'UNKNOWN=42',
        'FLUTTER=2',
      ]);
      expect(got, {'HOLDER': 1, 'FLUTTER': 2});
    });

    test('skips lines that do not match the pattern at all', () {
      final got = parsePidLines(<String>[
        'Building package executable...',
        'Built fluttersdk_artisan:fluttersdk_artisan.',
        'HOLDER=99',
      ]);
      expect(got, {'HOLDER': 99});
    });

    test('skips entries with non-integer values', () {
      // The regex itself requires \d+, so this case never matches; the
      // safety net inside parsePidLines protects against future regex
      // loosening. Use a tag-shaped string with no number.
      final got = parsePidLines(<String>['HOLDER=', 'FLUTTER=abc']);
      expect(got, isEmpty);
    });

    test('trims surrounding whitespace per line', () {
      final got = parsePidLines(<String>['  HOLDER=10  ', '\tFLUTTER=20']);
      expect(got, {'HOLDER': 10, 'FLUTTER': 20});
    });

    test('later match for same tag overwrites earlier one', () {
      final got = parsePidLines(<String>['HOLDER=1', 'HOLDER=2']);
      expect(got, {'HOLDER': 2});
    });

    test('mixed valid and invalid lines yields only the valid entries', () {
      final got = parsePidLines(<String>[
        '',
        'HOLDER=7',
        'noise',
        'FLUTTER=8',
        'noise2',
      ]);
      expect(got, {'HOLDER': 7, 'FLUTTER': 8});
    });
  });
}
