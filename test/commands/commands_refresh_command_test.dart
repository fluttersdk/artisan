import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('CommandsRefreshCommand', () {
    final cmd = CommandsRefreshCommand();

    test('declares name commands:refresh', () {
      expect(cmd.name, 'commands:refresh');
    });

    test('declares CommandBoot.none (no VM Service required)', () {
      expect(cmd.boot, CommandBoot.none);
    });

    test('description mentions rescan + index', () {
      expect(cmd.description, contains('Rescan'));
      expect(cmd.description, contains('index'));
    });

    test('extends ArtisanCommand', () {
      expect(cmd, isA<ArtisanCommand>());
    });
  });
}
