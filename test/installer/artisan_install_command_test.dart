import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Concrete subclass used to exercise the protected helper surface that
/// `ArtisanInstallCommand` exposes. The handle implementation is trivial — the
/// helper-method behavior is what these tests cover.
class _TestInstallCommand extends ArtisanInstallCommand {
  _TestInstallCommand({this.pluginNameValue = 'test_plugin'});

  /// Allows individual tests to flip the override value (e.g. to verify that
  /// `pluginName(ctx)` returns whatever the subclass decides to expose).
  final String pluginNameValue;

  @override
  String get signature => 'test:install $baseFlags';

  @override
  String get description => 'Test install command fixture.';

  @override
  String pluginName(ArtisanContext ctx) => pluginNameValue;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

/// Concrete subclass that derives the plugin name from a positional argument
/// — proves the contract supports both static and dynamic resolution.
class _ArgDrivenInstallCommand extends ArtisanInstallCommand {
  @override
  String get signature =>
      'plugin:install $baseFlags{name : Plugin package name}';

  @override
  String get description => 'Arg-driven install command fixture.';

  @override
  String pluginName(ArtisanContext ctx) =>
      ctx.input.argument('name') ?? '<missing>';

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

/// Builds an [ArtisanContext] backed by a [MapInput] carrying the supplied
/// option / argument values. Mirrors the test pattern other installer tests
/// use to drive command-side option parsing without a real argv parse.
ArtisanContext _ctxWith(
  Map<String, dynamic> options, {
  List<String> positional = const [],
  CommandSignature? signature,
}) {
  return ArtisanContext.bare(
    MapInput(options, positional: positional, signature: signature),
    BufferedOutput(),
  );
}

void main() {
  group('ArtisanInstallCommand — signature DSL', () {
    test('baseFlags interpolation parses into 4 standard option specs', () {
      final cmd = _TestInstallCommand();
      final parsed = cmd.parsedSignature;

      expect(parsed, isNotNull);
      expect(parsed!.name, 'test:install');

      final optionNames = parsed.options.map((o) => o.name).toSet();
      expect(
          optionNames,
          containsAll(
              <String>['force', 'dry-run', 'non-interactive', 'no-bootstrap']));

      // Every standard flag is a boolean switch (no value), not a value option.
      for (final name in <String>[
        'force',
        'dry-run',
        'non-interactive',
        'no-bootstrap'
      ]) {
        final spec = parsed.options.firstWhere((o) => o.name == name);
        expect(spec.isFlag, isTrue, reason: '--$name must be a flag');
      }
    });

    test('subclasses can append plugin-specific tokens after baseFlags', () {
      final cmd = _ArgDrivenInstallCommand();
      final parsed = cmd.parsedSignature;

      expect(parsed, isNotNull);
      expect(parsed!.name, 'plugin:install');
      expect(parsed.arguments.map((a) => a.name), contains('name'));
      // Plus the 4 base flags.
      expect(parsed.options.length, 4);
    });
  });

  group('ArtisanInstallCommand — boot', () {
    test('boot is CommandBoot.none — install commands run pre-app-launch', () {
      final cmd = _TestInstallCommand();
      expect(cmd.boot, CommandBoot.none);
    });
  });

  group('ArtisanInstallCommand — buildContext(ctx)', () {
    test('returns an InstallContext.real wrapping the input ArtisanContext',
        () {
      final cmd = _TestInstallCommand();
      final artisanCtx = _ctxWith(const <String, dynamic>{});

      final installCtx = cmd.buildContext(artisanCtx);

      expect(installCtx, isA<InstallContext>());
      expect(identical(installCtx.artisanContext, artisanCtx), isTrue,
          reason: 'InstallContext must reuse the supplied ArtisanContext');
    });
  });

  group('ArtisanInstallCommand — boolean flag helpers', () {
    test('isDryRun reads the --dry-run option from ctx.input', () {
      final cmd = _TestInstallCommand();

      expect(cmd.isDryRun(_ctxWith(const {'dry-run': true})), isTrue);
      expect(cmd.isDryRun(_ctxWith(const {'dry-run': false})), isFalse);
    });

    test('isForce reads the --force option from ctx.input', () {
      final cmd = _TestInstallCommand();

      expect(cmd.isForce(_ctxWith(const {'force': true})), isTrue);
      expect(cmd.isForce(_ctxWith(const {'force': false})), isFalse);
    });

    test('isNonInteractive reads the --non-interactive option from ctx.input',
        () {
      final cmd = _TestInstallCommand();

      expect(
        cmd.isNonInteractive(_ctxWith(const {'non-interactive': true})),
        isTrue,
      );
      expect(
        cmd.isNonInteractive(_ctxWith(const {'non-interactive': false})),
        isFalse,
      );
    });

    test('isSkipBootstrap reads the --no-bootstrap option from ctx.input', () {
      final cmd = _TestInstallCommand();

      expect(
        cmd.isSkipBootstrap(_ctxWith(const {'no-bootstrap': true})),
        isTrue,
      );
      expect(
        cmd.isSkipBootstrap(_ctxWith(const {'no-bootstrap': false})),
        isFalse,
      );
    });

    test('all 4 helpers are independent — they read their own option key', () {
      final cmd = _TestInstallCommand();
      final ctx = _ctxWith(const {
        'dry-run': true,
        'force': false,
        'non-interactive': true,
        'no-bootstrap': false,
      });

      expect(cmd.isDryRun(ctx), isTrue);
      expect(cmd.isForce(ctx), isFalse);
      expect(cmd.isNonInteractive(ctx), isTrue);
      expect(cmd.isSkipBootstrap(ctx), isFalse);
    });
  });

  group('ArtisanInstallCommand — pluginName(ctx) override contract', () {
    test('subclass may return a static plugin name', () {
      final cmd = _TestInstallCommand(pluginNameValue: 'magic_logger');
      final ctx = _ctxWith(const <String, dynamic>{});

      expect(cmd.pluginName(ctx), 'magic_logger');
    });

    test('subclass may derive plugin name from a positional argument', () {
      final cmd = _ArgDrivenInstallCommand();
      final ctx = _ctxWith(
        const <String, dynamic>{},
        positional: const ['firebase_messaging'],
        signature: cmd.parsedSignature,
      );

      expect(cmd.pluginName(ctx), 'firebase_messaging');
    });
  });
}
