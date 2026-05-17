import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('shellQuoteTokens', () {
    test('leaves bareword tokens unquoted', () {
      expect(
          shellQuoteTokens(['nohup', 'flutter', 'run']), 'nohup flutter run');
    });

    test('quotes tokens containing spaces', () {
      expect(shellQuoteTokens(['hello world']), "'hello world'");
    });

    test('quotes tokens containing shell metacharacters', () {
      expect(shellQuoteTokens([r'$(rm -rf /)']), "'\$(rm -rf /)'");
      expect(shellQuoteTokens(['a;b']), "'a;b'");
      expect(shellQuoteTokens(['a|b']), "'a|b'");
      expect(shellQuoteTokens(['a&b']), "'a&b'");
    });

    test("escapes embedded single quotes via canonical '\\'' pattern", () {
      expect(shellQuoteTokens(["it's"]), "'it'\\''s'");
    });

    test('handles empty token list', () {
      expect(shellQuoteTokens(<String>[]), '');
    });

    test('joins multiple tokens with single space', () {
      expect(
        shellQuoteTokens(['nohup', 'flutter', 'run', '-d', 'chrome']),
        'nohup flutter run -d chrome',
      );
    });

    test('preserves bareword path-like tokens', () {
      expect(
        shellQuoteTokens(['/Users/anilcan/.artisan/state.json']),
        '/Users/anilcan/.artisan/state.json',
      );
    });

    test('quotes path with space', () {
      expect(
        shellQuoteTokens(['/Users/anil can/.artisan/state.json']),
        "'/Users/anil can/.artisan/state.json'",
      );
    });

    test('quotes tokens with newline', () {
      expect(shellQuoteTokens(['line1\nline2']), "'line1\nline2'");
    });

    test('accepts an empty string token as a quoted empty word', () {
      expect(shellQuoteTokens(['']), "''");
    });

    test('handles equals signs and colons as barewords', () {
      expect(
        shellQuoteTokens(['--web-port=3100', 'http://example.com:8080']),
        '--web-port=3100 http://example.com:8080',
      );
    });
  });
}
