import 'package:my_plugin/cli.dart';
import 'package:test/test.dart';

void main() {
  group('InstallCommand', () {
    test('declares signature with baseFlags', () {
      final cmd = InstallCommand();

      expect(cmd.signature, contains('my_plugin:install'));
      expect(cmd.signature, contains('--force'));
      expect(cmd.signature, contains('--dry-run'));
    });
  });
}
