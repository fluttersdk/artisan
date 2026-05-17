import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('RestartCommand', () {
    test('metadata: name=restart, boot=none', () {
      final command = RestartCommand();

      expect(command.name, 'restart');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('inherits from ArtisanCommand', () {
      final command = RestartCommand();

      expect(command, isA<ArtisanCommand>());
    });

    test('description mentions stop + start', () {
      final command = RestartCommand();

      expect(command.description.toLowerCase(), contains('stop'));
      expect(command.description.toLowerCase(), contains('start'));
    });
  });
}
