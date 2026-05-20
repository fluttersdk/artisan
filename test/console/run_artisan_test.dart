import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('runArtisan delegation', () {
    test('delegates to consumer wrapper when the wrapper exists', () async {
      var delegateCalled = false;
      List<String>? receivedArgs;

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => true,
        delegate: (args) async {
          delegateCalled = true;
          receivedArgs = args;
          return 42;
        },
      );

      expect(delegateCalled, isTrue);
      expect(receivedArgs, equals(<String>['list']));
      expect(code, 42);
    });

    test('skips delegation when consumer wrapper is absent', () async {
      var delegateCalled = false;

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        delegate: (args) async {
          delegateCalled = true;
          return 0;
        },
      );

      expect(delegateCalled, isFalse);
      // Standalone path dispatches `list` against the builtins; exit 0.
      expect(code, 0);
    });

    test('bypass list skips delegation for commands:refresh', () async {
      var delegateCalled = false;

      await runArtisan(
        <String>['commands:refresh'],
        wrapperExists: () => true,
        delegate: (args) async {
          delegateCalled = true;
          return 0;
        },
        // Force the standalone branch to terminate without doing real work
        // by stubbing the dispatcher via a base provider that owns the name.
        baseProviders: <ArtisanServiceProvider>[
          _StubProvider(<ArtisanCommand>[_NoopCommand('commands:refresh')]),
        ],
      );

      expect(delegateCalled, isFalse);
    });

    test('bypass list skips delegation for plugins:refresh', () async {
      var delegateCalled = false;

      await runArtisan(
        <String>['plugins:refresh'],
        wrapperExists: () => true,
        delegate: (args) async {
          delegateCalled = true;
          return 0;
        },
        baseProviders: <ArtisanServiceProvider>[
          _StubProvider(<ArtisanCommand>[_NoopCommand('plugins:refresh')]),
        ],
      );

      expect(delegateCalled, isFalse);
    });

    test('delegateToConsumer:false skips delegation regardless', () async {
      var delegateCalled = false;

      final code = await runArtisan(
        <String>['list'],
        delegateToConsumer: false,
        wrapperExists: () => true,
        delegate: (args) async {
          delegateCalled = true;
          return 99;
        },
      );

      expect(delegateCalled, isFalse);
      expect(code, 0);
    });

    test('delegates when args list is empty and wrapper present', () async {
      // Empty args → standalone help would normally fire, but since the
      // consumer wrapper is the canonical surface, empty argv still routes
      // there so the wrapper renders its own help with full provider list.
      var delegateCalled = false;

      await runArtisan(
        <String>[],
        wrapperExists: () => true,
        delegate: (args) async {
          delegateCalled = true;
          return 0;
        },
      );

      expect(delegateCalled, isTrue);
    });
  });

  group('runArtisan standalone', () {
    test('registers base providers alongside builtins', () async {
      final probe = _ProbeCommand('probe:base');
      final provider = _StubProvider(<ArtisanCommand>[probe]);

      final code = await runArtisan(
        <String>['probe:base'],
        wrapperExists: () => false,
        baseProviders: <ArtisanServiceProvider>[provider],
      );

      expect(probe.calls, 1);
      expect(code, 0);
    });

    test('registers auto-discovered providers from the factory', () async {
      final probe = _ProbeCommand('probe:auto');

      final code = await runArtisan(
        <String>['probe:auto'],
        wrapperExists: () => false,
        autoProviders: () => <ArtisanServiceProvider>[
          _StubProvider(<ArtisanCommand>[probe]),
        ],
      );

      expect(probe.calls, 1);
      expect(code, 0);
    });

    test('builtins always include list + refresh commands', () async {
      // `list` is a builtin — without it, this would exit 1 (unknown command).
      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
      );

      expect(code, 0);
    });
  });

  group('defaultConsumerWrapperExists', () {
    // Post-rename to bin/dispatcher.dart, the default wrapper-presence helper
    // must accept BOTH the legacy bin/artisan.dart name (still used by
    // hand-curated wrappers) AND the new canonical bin/dispatcher.dart name
    // (emitted by `dart run fluttersdk_artisan install`). Either filename
    // qualifies the consumer for auto-delegation.

    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('default_wrapper_');
      Directory(p.join(tempRoot.path, 'bin')).createSync(recursive: true);
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('returns true when bin/dispatcher.dart is present', () {
      File(p.join(tempRoot.path, 'bin', 'dispatcher.dart'))
          .writeAsStringSync('void main() {}\n');

      expect(defaultConsumerWrapperExists(cwd: tempRoot.path), isTrue);
    });

    test('returns true when bin/artisan.dart is present (legacy filename)', () {
      File(p.join(tempRoot.path, 'bin', 'artisan.dart'))
          .writeAsStringSync('void main() {}\n');

      expect(defaultConsumerWrapperExists(cwd: tempRoot.path), isTrue);
    });

    test('returns true when both wrappers are present', () {
      File(p.join(tempRoot.path, 'bin', 'dispatcher.dart'))
          .writeAsStringSync('void main() {}\n');
      File(p.join(tempRoot.path, 'bin', 'artisan.dart'))
          .writeAsStringSync('void main() {}\n');

      expect(defaultConsumerWrapperExists(cwd: tempRoot.path), isTrue);
    });

    test('returns false when neither wrapper is present', () {
      expect(defaultConsumerWrapperExists(cwd: tempRoot.path), isFalse);
    });
  });

  group('runArtisan failure modes', () {
    test('ArtisanCommandCollisionException returns exit 2', () async {
      // Same command name from two providers; registry throws on the
      // second `register()`.
      final collidingProvider = _StubProvider(
        <ArtisanCommand>[_NoopCommand('list')],
        providerName: 'colliding',
      );

      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        baseProviders: <ArtisanServiceProvider>[collidingProvider],
      );

      expect(code, 2);
    });

    test('generic exception during registration returns exit 3', () async {
      final code = await runArtisan(
        <String>['list'],
        wrapperExists: () => false,
        autoProviders: () => throw StateError('autoProviders blew up'),
      );

      expect(code, 3);
    });
  });
}

class _StubProvider extends ArtisanServiceProvider {
  _StubProvider(this._commands, {String? providerName})
      : _providerName = providerName ?? 'stub';

  final List<ArtisanCommand> _commands;
  final String _providerName;

  @override
  String get providerName => _providerName;

  @override
  List<ArtisanCommand> commands() => _commands;
}

class _NoopCommand extends ArtisanCommand {
  _NoopCommand(this._name);
  final String _name;

  @override
  String get name => _name;

  @override
  String get description => 'noop';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _ProbeCommand extends ArtisanCommand {
  _ProbeCommand(this._name);
  final String _name;
  int calls = 0;

  @override
  String get name => _name;

  @override
  String get description => 'probe';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    calls++;
    return 0;
  }
}
