import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('StartCommand', () {
    test('metadata: name=start, boot=none', () {
      final command = StartCommand();

      expect(command.name, 'start');
      expect(command.boot, CommandBoot.none);
      expect(command.description, isNotEmpty);
    });

    test('configure declares device / port / vm-service-port / dds / static',
        () {
      final command = StartCommand();
      final parser = ArgParser();

      command.configure(parser);

      expect(parser.options.containsKey('device'), isTrue);
      expect(parser.options.containsKey('port'), isTrue);
      expect(parser.options.containsKey('vm-service-port'), isTrue);
      expect(parser.options.containsKey('dds'), isTrue);
      expect(parser.options.containsKey('profile-static'), isTrue);
    });

    test('--device defaults to chrome', () {
      final command = StartCommand();
      final parser = ArgParser();
      command.configure(parser);

      final results = parser.parse(<String>[]);

      expect(results['device'], 'chrome');
      expect(results['port'], '3100');
      expect(results['dds'], isFalse);
    });

    test('--device override is honored', () {
      final command = StartCommand();
      final parser = ArgParser();
      command.configure(parser);

      final results = parser.parse(<String>['--device=macos']);

      expect(results['device'], 'macos');
    });

    test('normalizeVmServiceUri converts http:// to ws:// and appends /ws', () {
      expect(
        StartCommand.normalizeVmServiceUri('http://127.0.0.1:8181/abc'),
        'ws://127.0.0.1:8181/abc/ws',
      );
    });

    test('normalizeVmServiceUri keeps existing /ws suffix', () {
      expect(
        StartCommand.normalizeVmServiceUri('ws://127.0.0.1:8181/abc/ws'),
        'ws://127.0.0.1:8181/abc/ws',
      );
    });

    test('normalizeVmServiceUri normalizes https:// to wss://', () {
      expect(
        StartCommand.normalizeVmServiceUri('https://example.com:443/x/'),
        'wss://example.com:443/x/ws',
      );
    });

    test('normalizeVmServiceUri trims trailing slash before appending ws', () {
      expect(
        StartCommand.normalizeVmServiceUri('ws://host:1/token/ws/'),
        'ws://host:1/token/ws',
      );
    });

    test('normalizeVmServiceUri leaves unrecognised schemes alone (only /ws)',
        () {
      expect(
        StartCommand.normalizeVmServiceUri('foo://bar/baz'),
        'foo://bar/baz/ws',
      );
    });
  });
}
