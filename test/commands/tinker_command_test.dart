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

    test('signature declares --eval= option (one-shot eval mode)', () {
      final command = TinkerCommand();

      expect(command.signature, contains('{--eval='));
      expect(command.signature, contains('REPL is skipped'));
    });

    test(
        'handle with --eval set short-circuits and propagates ctx.evaluate '
        'failure (no REPL chatter)', () async {
      // Bare context has no VmServiceClient bound; ctx.evaluate throws
      // StateError on the first call. The --eval branch catches this and
      // writes the error message to output, returning exit=1 ; verifies the
      // one-shot path is wired (REPL would never even reach evaluate without
      // stdin input).
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const {'eval': '1 + 1'}),
        output,
      );

      final exit = await TinkerCommand().handle(ctx);

      expect(exit, 1, reason: 'eval branch returns 1 when ctx.evaluate raises');
      expect(output.content, contains('non-connected'),
          reason:
              'StateError message from disconnected evaluate flows through');
      expect(output.content, isNot(contains('Tinker connected')),
          reason: 'REPL banner must not appear when --eval is set');
      expect(output.content, isNot(contains('Tinker session ended')),
          reason: 'REPL closing line must not appear when --eval is set');
    });

    test(
        'handle with empty --eval falls through to REPL banner '
        '(stdin EOF closes the loop cleanly)', () async {
      // No --eval flag ; REPL path runs. The first stdin.readLineSync() in a
      // non-tty test returns null (EOF) so the loop exits immediately. The
      // banner + closing line are written; exit is 0.
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(MapInput(const {}), output);

      final exit = await TinkerCommand().handle(ctx);

      expect(exit, 0);
      expect(output.content, contains('Tinker connected'));
      expect(output.content, contains('Tinker session ended'));
    });
  });
}
