import 'package:my_plugin/cli.dart';
import 'package:test/test.dart';

void main() {
  group('MyPluginArtisanProvider', () {
    test('registers install + uninstall commands', () {
      final provider = MyPluginArtisanProvider();
      final commands = provider.commands();

      expect(commands.length, 2);
    });
  });
}
