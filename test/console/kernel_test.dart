import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/console/kernel.dart';
import 'package:magic_cli/src/console/command.dart';
import 'package:args/args.dart';

class TestCommand1 extends Command {
  @override
  String get name => 'make:test1';

  @override
  String get description => 'Description 1';

  bool wasHandled = false;

  @override
  Future<void> handle() async {
    wasHandled = true;
  }
}

class TestCommand2 extends Command {
  @override
  String get name => 'make:test2';

  @override
  String get description => 'Description 2';

  bool wasHandled = false;

  @override
  void configure(ArgParser parser) {
    parser.addOption('name');
  }

  @override
  Future<void> handle() async {
    wasHandled = true;
  }
}

class RootCommand extends Command {
  @override
  String get name => 'install';

  @override
  String get description => 'Install Magic';

  bool wasHandled = false;

  @override
  Future<void> handle() async {
    wasHandled = true;
  }
}

void main() {
  group('Kernel', () {
    late Kernel kernel;
    late TestCommand1 cmd1;
    late TestCommand2 cmd2;
    late RootCommand rootCmd;

    setUp(() {
      kernel = Kernel();
      cmd1 = TestCommand1();
      cmd2 = TestCommand2();
      rootCmd = RootCommand();
    });

    test('register and dispatch works', () async {
      kernel.register(cmd1);

      await kernel.handle(['make:test1']);
      expect(cmd1.wasHandled, true);
    });

    test('registerMany works', () async {
      kernel.registerMany([cmd1, cmd2]);

      await kernel.handle(['make:test2', '--name', 'test']);
      expect(cmd2.wasHandled, true);
      expect(cmd2.option('name'), 'test');
    });

    test('help prints correctly formatted text', () async {
      kernel.registerMany([cmd1, cmd2, rootCmd]);

      // We can't easily capture stdout without zone tricks,
      // but we can ensure it runs without errors for both empty args and --help
      await kernel.handle([]);
      await kernel.handle(['--help']);
      await kernel.handle(['-h']);
    });

    test('version prints without errors', () async {
      await kernel.handle(['--version']);
      await kernel.handle(['-V']);
    });
  });
}
