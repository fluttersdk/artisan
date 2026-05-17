import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('InstallException', () {
    setUp(() {});
    tearDown(() {});

    test('stores message and has no offending op by default', () {
      const exception = InstallException('Something went wrong.');

      expect(exception.message, 'Something went wrong.');
      expect(exception.offendingOp, isNull);
    });

    test('stores optional offendingOp', () {
      const op = 'add_dependency';
      const exception = InstallException('Failed.', offendingOp: op);

      expect(exception.offendingOp, 'add_dependency');
    });

    test('toString includes the message', () {
      const exception = InstallException('Network timeout.');

      expect(exception.toString(), contains('Network timeout.'));
    });

    test('toString includes offendingOp when set', () {
      const exception =
          InstallException('Bad op.', offendingOp: 'publish_file');

      expect(exception.toString(), contains('Bad op.'));
      expect(exception.toString(), contains('publish_file'));
    });

    test('implements Exception', () {
      const exception = InstallException('test');

      expect(exception, isA<Exception>());
    });

    test('can be thrown and caught', () {
      expect(
        () => throw const InstallException('thrown'),
        throwsA(isA<InstallException>()),
      );
    });
  });

  group('ManifestValidationException', () {
    setUp(() {});
    tearDown(() {});

    test('extends InstallException', () {
      const exception = ManifestValidationException('Invalid manifest field.');

      expect(exception, isA<InstallException>());
    });

    test('stores message from InstallException', () {
      const exception =
          ManifestValidationException('Missing required key: name.');

      expect(exception.message, 'Missing required key: name.');
    });

    test('stores optional offendingOp', () {
      const exception = ManifestValidationException(
        'Bad value.',
        offendingOp: 'validate_manifest',
      );

      expect(exception.offendingOp, 'validate_manifest');
    });

    test('toString includes class name and message', () {
      const exception = ManifestValidationException('Schema error.');

      expect(exception.toString(), contains('Schema error.'));
    });

    test('can be thrown and caught as InstallException', () {
      expect(
        () => throw const ManifestValidationException('manifest broken'),
        throwsA(isA<InstallException>()),
      );
    });

    test('can be thrown and caught as ManifestValidationException', () {
      expect(
        () => throw const ManifestValidationException('manifest broken'),
        throwsA(isA<ManifestValidationException>()),
      );
    });
  });
}
