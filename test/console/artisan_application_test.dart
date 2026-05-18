import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanApplication.dispatch', () {
    test('empty args prints root help and exits 0', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      final code = await app.dispatch(<String>[]);

      expect(code, 0);
    });

    test('--help prints root help and exits 0', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      expect(await app.dispatch(<String>['--help']), 0);
      expect(await app.dispatch(<String>['-h']), 0);
    });

    test('--version prints version and exits 0', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      expect(await app.dispatch(<String>['--version']), 0);
      expect(await app.dispatch(<String>['-V']), 0);
    });

    test('unknown command exits 1', () async {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      final code = await app.dispatch(<String>['no-such-command']);

      expect(code, 1);
    });

    test('dispatches to a registered bare command and propagates exit code',
        () async {
      final registry = ArtisanRegistry();
      registry.register(_FixedExitCommand('exit-7', 7));
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['exit-7']);

      expect(code, 7);
    });

    test('FormatException from arg parser surfaces as exit 1', () async {
      final registry = ArtisanRegistry();
      registry.register(_OptionCommand());
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['has-option', '--unknown']);

      expect(code, 1);
    });

    test('command --help (per-command) returns 0 without running handle',
        () async {
      final command = _RecordingCommand();
      final registry = ArtisanRegistry();
      registry.register(command);
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['recording', '--help']);

      expect(code, 0);
      expect(command.calls, 0);
    });

    test('exception from handle returns exit 3', () async {
      final registry = ArtisanRegistry();
      registry.register(_ThrowingCommand());
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['throws']);

      expect(code, 3);
    });

    test('connected-mode command without state.json returns 1', () async {
      StateFile.debugHomeOverride =
          '/tmp/artisan_app_test_${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() => StateFile.debugHomeOverride = null);

      final registry = ArtisanRegistry();
      registry.register(_ConnectedCommand());
      final app = ArtisanApplication(registry: registry);

      final code = await app.dispatch(<String>['connected']);

      expect(code, 1);
    });

    test('default version is the published alpha tag', () {
      final app = ArtisanApplication(registry: ArtisanRegistry());

      expect(app.version, ArtisanApplication.defaultVersion);
    });

    test('custom version is honored', () {
      final app = ArtisanApplication(
        registry: ArtisanRegistry(),
        version: '9.9.9',
      );

      expect(app.version, '9.9.9');
    });

    test('dispatch threads its registry into the context', () async {
      final registry = ArtisanRegistry();
      final capturingCommand = _RegistryCapturingCommand();
      registry.register(capturingCommand);
      final app = ArtisanApplication(registry: registry);

      await app.dispatch(<String>['capture-registry']);

      expect(capturingCommand.capturedRegistry, same(registry));
    });
  });
}

class _FixedExitCommand extends ArtisanCommand {
  _FixedExitCommand(this._name, this._exit);
  final String _name;
  final int _exit;

  @override
  String get name => _name;

  @override
  String get description => 'fixed exit';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => _exit;
}

class _OptionCommand extends ArtisanCommand {
  @override
  String get name => 'has-option';

  @override
  String get description => 'declares no options';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _RecordingCommand extends ArtisanCommand {
  int calls = 0;

  @override
  String get name => 'recording';

  @override
  String get description => 'records handle calls';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    calls++;
    return 0;
  }
}

class _ThrowingCommand extends ArtisanCommand {
  @override
  String get name => 'throws';

  @override
  String get description => 'always throws';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => throw StateError('boom');
}

class _ConnectedCommand extends ArtisanCommand {
  @override
  String get name => 'connected';

  @override
  String get description => 'requires a connected context';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _RegistryCapturingCommand extends ArtisanCommand {
  ArtisanRegistry? capturedRegistry;

  @override
  String get name => 'capture-registry';

  @override
  String get description => 'captures ctx.registry for assertion';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    capturedRegistry = ctx.registry;
    return 0;
  }
}
