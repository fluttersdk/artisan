import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('CommandSignature.parse — name', () {
    test('single-word kebab name', () {
      final s = CommandSignature.parse('start');
      expect(s.name, 'start');
      expect(s.arguments, isEmpty);
      expect(s.options, isEmpty);
    });

    test('kebab name with hyphen', () {
      final s = CommandSignature.parse('sync-monitors');
      expect(s.name, 'sync-monitors');
    });

    test('colon-namespaced name', () {
      final s = CommandSignature.parse('mail:send');
      expect(s.name, 'mail:send');
    });

    test('namespace + kebab', () {
      final s = CommandSignature.parse('mail:send-digest');
      expect(s.name, 'mail:send-digest');
    });

    test('trims surrounding whitespace', () {
      final s = CommandSignature.parse('   start   ');
      expect(s.name, 'start');
    });

    test('rejects empty signature', () {
      expect(() => CommandSignature.parse(''), throwsFormatException);
      expect(() => CommandSignature.parse('   '), throwsFormatException);
    });

    test('rejects uppercase letters in name', () {
      expect(
          () => CommandSignature.parse('SyncMonitors'), throwsFormatException);
    });

    test('accepts underscore in name (snake_case plugins)', () {
      // Snake_case package names (e.g. magic_logger) produce snake_case
      // command names via the make:plugin scaffold; the regex relaxation
      // landed in make-plugin-modes plan to support nested workspace plugins.
      final s = CommandSignature.parse('sync_monitors');
      expect(s.name, 'sync_monitors');
    });

    test('rejects starting hyphen / colon', () {
      expect(() => CommandSignature.parse('-foo'), throwsFormatException);
      expect(() => CommandSignature.parse(':foo'), throwsFormatException);
    });
  });

  group('CommandSignature.parse — arguments', () {
    test('single required positional', () {
      final s = CommandSignature.parse('sync {team}');
      expect(s.arguments, hasLength(1));
      expect(s.arguments.first.name, 'team');
      expect(s.arguments.first.isOptional, isFalse);
      expect(s.arguments.first.isVariadic, isFalse);
      expect(s.arguments.first.defaultValue, isNull);
    });

    test('optional positional with `?`', () {
      final s = CommandSignature.parse('sync {team?}');
      expect(s.arguments.first.isOptional, isTrue);
      expect(s.arguments.first.defaultValue, isNull);
    });

    test('positional with default `name=value`', () {
      final s = CommandSignature.parse('sync {scope=all}');
      expect(s.arguments.first.isOptional, isTrue);
      expect(s.arguments.first.defaultValue, 'all');
    });

    test('variadic with `*`', () {
      final s = CommandSignature.parse('sync {files*}');
      expect(s.arguments.first.isVariadic, isTrue);
      expect(s.arguments.first.isOptional, isFalse);
    });

    test('optional variadic with `?*`', () {
      final s = CommandSignature.parse('sync {files?*}');
      expect(s.arguments.first.isVariadic, isTrue);
      expect(s.arguments.first.isOptional, isTrue);
    });

    test('preserves declaration order', () {
      final s = CommandSignature.parse('sync {team} {scope} {target}');
      expect(s.arguments.map((a) => a.name), ['team', 'scope', 'target']);
    });

    test('mixed required + optional + default', () {
      final s = CommandSignature.parse(
        'sync {team} {scope?} {limit=10}',
      );
      expect(s.arguments[0].isOptional, isFalse);
      expect(s.arguments[1].isOptional, isTrue);
      expect(s.arguments[1].defaultValue, isNull);
      expect(s.arguments[2].isOptional, isTrue);
      expect(s.arguments[2].defaultValue, '10');
    });

    test('captures description after ` : `', () {
      final s = CommandSignature.parse('sync {team : Team slug}');
      expect(s.arguments.first.description, 'Team slug');
    });

    test('description with embedded colon survives', () {
      final s = CommandSignature.parse(
        'sync {team : Format like "ns:slug"}',
      );
      expect(s.arguments.first.description, 'Format like "ns:slug"');
    });
  });

  group('CommandSignature.parse — options / flags', () {
    test('boolean flag with `--`', () {
      final s = CommandSignature.parse('sync {--force}');
      expect(s.options, hasLength(1));
      expect(s.options.first.name, 'force');
      expect(s.options.first.isFlag, isTrue);
      expect(s.options.first.defaultValue, isNull);
    });

    test('value option without default', () {
      final s = CommandSignature.parse('sync {--port=}');
      expect(s.options.first.isFlag, isFalse);
      expect(s.options.first.defaultValue, isNull);
    });

    test('value option with default', () {
      final s = CommandSignature.parse('sync {--limit=10}');
      expect(s.options.first.name, 'limit');
      expect(s.options.first.isFlag, isFalse);
      expect(s.options.first.defaultValue, '10');
    });

    test('option with description', () {
      final s = CommandSignature.parse('sync {--force : Skip prompts}');
      expect(s.options.first.description, 'Skip prompts');
    });

    test('preserves declaration order alongside arguments', () {
      final s = CommandSignature.parse(
        'sync {team} {--force} {scope?} {--limit=10}',
      );
      expect(s.arguments.map((a) => a.name), ['team', 'scope']);
      expect(s.options.map((o) => o.name), ['force', 'limit']);
    });

    test('rejects uppercase option name', () {
      expect(
        () => CommandSignature.parse('sync {--FORCE}'),
        throwsFormatException,
      );
    });
  });

  group('CommandSignature.applyTo(ArgParser)', () {
    test('registers boolean flag', () {
      final s = CommandSignature.parse('sync {--force}');
      final parser = ArgParser();
      s.applyTo(parser);
      final r = parser.parse(['--force']);
      expect(r['force'], isTrue);
    });

    test('registers option with default', () {
      final s = CommandSignature.parse('sync {--limit=10}');
      final parser = ArgParser();
      s.applyTo(parser);
      expect(parser.parse([])['limit'], '10');
      expect(parser.parse(['--limit=99'])['limit'], '99');
    });

    test('registers option without default (null)', () {
      final s = CommandSignature.parse('sync {--port=}');
      final parser = ArgParser();
      s.applyTo(parser);
      expect(parser.parse([])['port'], isNull);
    });

    test('option help text flows through', () {
      final s = CommandSignature.parse('sync {--force : Skip prompts}');
      final parser = ArgParser();
      s.applyTo(parser);
      expect(parser.usage, contains('Skip prompts'));
    });

    test('positional arguments are NOT added to ArgParser', () {
      // Positional args live in parser.rest; signature only registers
      // options/flags into ArgParser. Verify arguments do not appear.
      final s = CommandSignature.parse('sync {team} {scope?}');
      final parser = ArgParser();
      s.applyTo(parser);
      expect(parser.options.keys, isEmpty);
    });
  });

  group('ArtisanCommand integration', () {
    test('name derives from signature when not overridden', () {
      final cmd = _SignatureOnlyCommand();
      expect(cmd.name, 'sync:monitors');
    });

    test('argument lookup by name via signature', () {
      final sig = CommandSignature.parse('sync {team} {scope?}');
      final input = MapInput({}, positional: ['acme'], signature: sig);
      expect(input.argument('team'), 'acme');
      expect(input.argument('scope'), isNull);
      expect(input.argument(0), 'acme');
      expect(input.argument(1), isNull);
    });

    test('argument default fallback from signature', () {
      final sig = CommandSignature.parse('sync {team} {scope=all}');
      final input = MapInput({}, positional: ['acme'], signature: sig);
      expect(input.argument('scope'), 'all');
    });

    test('option default from signature applied via ArgParser', () {
      final cmd = _SignatureOnlyCommand();
      final parser = ArgParser();
      cmd.configure(parser);
      final result = parser.parse([]);
      expect(result['limit'], '50');
    });

    test('name override wins over signature', () {
      final cmd = _NameOverrideCommand();
      expect(cmd.name, 'overridden');
    });

    test('without signature, name without override throws StateError', () {
      expect(() => _BareCommand().name, throwsStateError);
    });
  });
}

class _SignatureOnlyCommand extends ArtisanCommand {
  @override
  String get signature =>
      'sync:monitors {team} {scope=all} {--force} {--limit=50}';

  @override
  String get description => 'demo';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _NameOverrideCommand extends ArtisanCommand {
  @override
  String get name => 'overridden';

  @override
  String get description => 'demo';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}

class _BareCommand extends ArtisanCommand {
  @override
  String get description => 'no name, no signature → should throw';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async => 0;
}
