import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Verifies that a caller can reach `flutter run` through `start`.
///
/// `start` assembled its argv from a fixed literal, so the only way to pass
/// `--dart-define`, `--flavor`, `--web-renderer` or any other `flutter run`
/// flag was to stop using `start` and lose the session record with it: the
/// state file is what gives `stop`, `status`, `hot-restart` and every MCP tool
/// something to act on, and nothing else writes it.
///
/// Reported from a consumer that needed a compile-time define to switch a
/// fixture size for a performance run, and had to move the switch to a URL
/// query parameter because no define could reach the app through the tooling
/// that also gives the driver its session state.
///
/// The argv builder is a pure function precisely so this can be asserted
/// without spawning a real `flutter run`, the same reason `bootingState` and
/// `RestartCommand.sessionOverridesFrom` are exposed.
void main() {
  group('StartCommand.flutterArgsFor', () {
    test('carries the settings every start has always sent', () {
      final List<String> args = StartCommand.flutterArgsFor(
        device: 'chrome',
        webPort: 3100,
        vmServicePort: 8181,
        ddsOn: false,
        isChromeTarget: true,
      );

      expect(args.first, 'run');
      expect(args, containsAllInOrder(<String>['-d', 'chrome']));
      expect(args, contains('--web-port=3100'));
      expect(args, contains('--host-vmservice-port=8181'));
      expect(args, contains('--no-dds'));
      expect(args, contains('--dart-define=AI_TEST=1'));
    });

    test('omits the web port when the target is not a browser', () {
      final List<String> args = StartCommand.flutterArgsFor(
        device: 'macos',
        webPort: 3100,
        vmServicePort: 8181,
        ddsOn: false,
        isChromeTarget: false,
      );

      expect(args.any((String a) => a.startsWith('--web-port=')), isFalse);
    });

    test('keeps DDS when it was asked for', () {
      final List<String> args = StartCommand.flutterArgsFor(
        device: 'chrome',
        webPort: 3100,
        vmServicePort: 8181,
        ddsOn: true,
        isChromeTarget: true,
      );

      expect(args, isNot(contains('--no-dds')));
    });

    test('adds the web-server hot reload flag when asked', () {
      final List<String> args = StartCommand.flutterArgsFor(
        device: 'web-server',
        webPort: 3100,
        vmServicePort: 8181,
        ddsOn: false,
        isChromeTarget: true,
        webExperimentalHotReload: true,
      );

      expect(args, contains('--web-experimental-hot-reload'));
    });

    test('forwards every extra argument, in order, after its own', () {
      final List<String> args = StartCommand.flutterArgsFor(
        device: 'chrome',
        webPort: 3100,
        vmServicePort: 8181,
        ddsOn: false,
        isChromeTarget: true,
        extra: <String>[
          '--dart-define=SCALE=5000',
          '--flavor=staging',
        ],
      );

      expect(args, contains('--dart-define=SCALE=5000'));
      expect(args, contains('--flavor=staging'));
      // After the built-in set, so a caller can override a default artisan
      // chose: `flutter run` takes the last occurrence of a repeated flag.
      expect(
        args.indexOf('--dart-define=SCALE=5000'),
        greaterThan(args.indexOf('--dart-define=AI_TEST=1')),
      );
      expect(
        args.indexOf('--flavor=staging'),
        greaterThan(args.indexOf('--dart-define=SCALE=5000')),
      );
    });

    test('an empty extra list changes nothing', () {
      final List<String> withNone = StartCommand.flutterArgsFor(
        device: 'chrome',
        webPort: 3100,
        vmServicePort: 8181,
        ddsOn: false,
        isChromeTarget: true,
      );
      final List<String> withEmpty = StartCommand.flutterArgsFor(
        device: 'chrome',
        webPort: 3100,
        vmServicePort: 8181,
        ddsOn: false,
        isChromeTarget: true,
        extra: const <String>[],
      );

      expect(withEmpty, withNone);
    });
  });

  group('StartCommand.bootingState', () {
    test('records the extra arguments so a restart can replay them', () {
      final Map<String, dynamic> state = StartCommand.bootingState(
        pid: 1,
        stdinPipe: '/tmp/fifo',
        stdinHolderPid: 2,
        webPort: 3100,
        vmServicePort: 8181,
        profileStatic: false,
        device: 'chrome',
        chromePid: null,
        tmpProfileDir: null,
        cdpPort: null,
        flutterArgs: const <String>['--dart-define=SCALE=5000'],
      );

      expect(state['flutterArgs'], <String>['--dart-define=SCALE=5000']);
    });

    test(
        'omits the key when there were none, rather than writing an empty '
        'list a reader has to interpret', () {
      final Map<String, dynamic> state = StartCommand.bootingState(
        pid: 1,
        stdinPipe: '/tmp/fifo',
        stdinHolderPid: 2,
        webPort: 3100,
        vmServicePort: 8181,
        profileStatic: false,
        device: 'chrome',
        chromePid: null,
        tmpProfileDir: null,
        cdpPort: null,
      );

      expect(state.containsKey('flutterArgs'), isFalse);
    });
  });

  group('RestartCommand.sessionOverridesFrom', () {
    test('carries the extra arguments across a restart', () {
      final Map<String, Object?> carried = RestartCommand.sessionOverridesFrom(
        <String, dynamic>{
          'device': 'chrome',
          'webPort': 3100,
          'flutterArgs': <String>['--dart-define=SCALE=5000'],
        },
      );

      expect(carried['flutterArgs'], <String>['--dart-define=SCALE=5000']);
    });
  });
}
