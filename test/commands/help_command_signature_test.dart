import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('HelpCommand integration with signature-bearing commands', () {
    test('renders signature-bearing command with Arguments section', () async {
      final registry = ArtisanRegistry();
      registry.register(_SignatureCmd(), providerName: 'test');
      final cmd = HelpCommand(registry);

      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const <String, dynamic>{}, positional: <String>['sync:demo']),
        output,
      );
      final code = await cmd.handle(ctx);

      expect(code, 0);
      final printed = output.content;
      expect(printed, contains('Arguments:'));
      expect(printed, contains('team'));
      expect(printed, contains('scope'));
      expect(printed, contains('default=all'));
      expect(printed, contains('Skip prompts'));
    });

    test('renders Usage with required vs optional positional shape', () async {
      final registry = ArtisanRegistry();
      registry.register(_SignatureCmd(), providerName: 'test');
      final cmd = HelpCommand(registry);

      final output = BufferedOutput();
      await cmd.handle(
        ArtisanContext.bare(
          MapInput(const <String, dynamic>{},
              positional: <String>['sync:demo']),
          output,
        ),
      );

      final printed = output.content;
      expect(printed, contains('<team>'));
      expect(printed, contains('[scope]'));
    });

    test('renders signature-less command without Arguments section', () async {
      final registry = ArtisanRegistry();
      registry.register(_BareCmd(), providerName: 'test');
      final cmd = HelpCommand(registry);

      final output = BufferedOutput();
      await cmd.handle(
        ArtisanContext.bare(
          MapInput(const <String, dynamic>{}, positional: <String>['bare']),
          output,
        ),
      );

      final printed = output.content;
      expect(printed, isNot(contains('Arguments:')));
      expect(printed, contains('[arguments]'));
    });
  });
}

class _SignatureCmd extends ArtisanCommand {
  @override
  String get signature =>
      'sync:demo {team : Team slug} {scope=all : Subset filter} '
      '{--force : Skip prompts} {--limit=50}';

  @override
  String get description => 'demo';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _BareCmd extends ArtisanCommand {
  @override
  String get name => 'bare';

  @override
  String get description => 'no signature';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}
