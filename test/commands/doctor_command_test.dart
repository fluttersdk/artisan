import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('DoctorCommand', () {
    test('metadata: name=doctor, boot=none', () {
      final command = DoctorCommand();

      expect(command.name, 'doctor');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('handle runs preflight checks and returns 0 or 1', () async {
      final command = DoctorCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final code = await command.handle(ctx);

      // Cannot assert pass/fail in arbitrary CI; only that the contract holds.
      expect(code, anyOf(0, 1));
      expect(output.content, contains('flutter --version'));
      expect(output.content, contains('dart --version'));
      expect(output.content, contains('port 3100'));
    });

    test('output lines start with checkmark or cross', () async {
      final command = DoctorCommand();
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      await command.handle(ctx);

      final lines = output.content.trim().split('\n');
      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(line.trim(), anyOf(startsWith('✓'), startsWith('✗')));
      }
    });

    test('runs end-to-end without throwing', () async {
      final command = DoctorCommand();
      final ctx = ArtisanContext.bare(MapInput(const {}), BufferedOutput());

      await expectLater(command.handle(ctx), completes);
    });
  });
}
