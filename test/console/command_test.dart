import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/console/command.dart';
import 'package:args/args.dart';

class TestCommand extends Command {
  @override
  String get name => 'test:cmd';

  @override
  String get description => 'A test command';

  bool wasHandled = false;

  @override
  void configure(ArgParser parser) {
    parser.addOption('name', abbr: 'n');
    parser.addFlag('force', abbr: 'f');
  }

  @override
  Future<void> handle() async {
    wasHandled = true;
  }
}

void main() {
  group('Command', () {
    late TestCommand cmd;

    setUp(() {
      cmd = TestCommand();
    });

    test('properties return correct values', () {
      expect(cmd.name, 'test:cmd');
      expect(cmd.description, 'A test command');
    });

    test('arguments parsing', () async {
      final parser = ArgParser();
      cmd.configure(parser);

      final results =
          parser.parse(['--name', 'test_user', '--force', 'pos_arg']);
      cmd.arguments = results;

      expect(cmd.option('name'), 'test_user');
      expect(cmd.hasOption('force'), true);
      expect(cmd.option('force'), true);
      expect(cmd.argument(0), 'pos_arg');
      expect(cmd.argument(1), isNull);
    });

    test('handle executes', () async {
      await cmd.handle();
      expect(cmd.wasHandled, true);
    });
  });
}
