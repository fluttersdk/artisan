import 'package:awesome_plugin/cli.dart';
import 'package:test/test.dart';

void main() {
  group('AwesomePluginArtisanProvider', () {
    test('registers install + uninstall commands', () {
      final provider = AwesomePluginArtisanProvider();
      final commands = provider.commands();

      expect(commands.length, 2);
    });
  });
}
