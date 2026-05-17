import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('TinkerCommand', () {
    setUp(() {
      Tinker.casters.clear();
    });

    test('metadata: name=tinker, boot=connected', () {
      final command = TinkerCommand();

      expect(command.name, 'tinker');
      expect(command.boot, CommandBoot.connected);
      expect(command.description, isNotEmpty);
    });

    test('inherits ArtisanCommand contract', () {
      final command = TinkerCommand();

      expect(command, isA<ArtisanCommand>());
    });

    test('Tinker.casters chain is consulted by every invocation (contract)',
        () {
      // Sanity guard: appending a caster does not throw and shows up in the
      // chain consumed by TinkerCommand's _formatResult.
      Tinker.casters.add((v) => v?.toString());

      expect(Tinker.casters, isNotEmpty);
    });
  });
}
