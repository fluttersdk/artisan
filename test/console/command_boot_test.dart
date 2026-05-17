import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('CommandBoot', () {
    test('declares two V1 values: none + connected', () {
      expect(CommandBoot.values, hasLength(2));
      expect(
          CommandBoot.values,
          containsAll(<CommandBoot>[
            CommandBoot.none,
            CommandBoot.connected,
          ]));
    });

    test('each value exposes a human-readable name', () {
      expect(CommandBoot.none.name, 'none');
      expect(CommandBoot.connected.name, 'connected');
    });

    test('values are usable in switch statements', () {
      String label(CommandBoot boot) {
        switch (boot) {
          case CommandBoot.none:
            return 'bare';
          case CommandBoot.connected:
            return 'connected';
        }
      }

      expect(label(CommandBoot.none), 'bare');
      expect(label(CommandBoot.connected), 'connected');
    });
  });
}
