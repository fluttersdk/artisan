import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Helper that fakes a `lib/app/` directory inside an [InMemoryFs] by
/// pre-writing a sentinel file the test command's `directoryExists` seam can
/// observe via the same fs instance.
///
/// @param fs           In-memory fs that backs the test.
/// @param projectRoot  Project root path used by the command under test.
/// @return The sentinel file path written so callers can pass it through
///         their own predicates if needed.
String _seedLibApp(InMemoryFs fs, String projectRoot) {
  final sentinel = '$projectRoot/lib/app/.keep';
  fs.writeAsString(sentinel, '');
  return sentinel;
}

/// Builds a default [ArtisanContext] with a [BufferedOutput] suitable for
/// inspecting command output in assertions.
///
/// @return A bare [ArtisanContext] with empty input and a buffered output.
ArtisanContext _ctx() {
  return ArtisanContext.bare(
    MapInput(const <String, dynamic>{}),
    BufferedOutput(),
  );
}

/// Wraps construction of the command under test with the in-memory seams the
/// tests need to drive it without touching the host filesystem.
///
/// @param fs           In-memory file system holding plugins.json + generated output.
/// @param projectRoot  Project root the command operates against.
/// @return A configured [PluginsRefreshCommand].
PluginsRefreshCommand _cmd(InMemoryFs fs, String projectRoot) {
  return PluginsRefreshCommand(
    fs: fs,
    projectRoot: projectRoot,
    directoryExists: (absDir) => fs.listSync(absDir).isNotEmpty,
  );
}

void main() {
  group('PluginsRefreshCommand metadata', () {
    final cmd = PluginsRefreshCommand();

    test('declares signature plugins:refresh', () {
      expect(cmd.name, 'plugins:refresh');
    });

    test('declares CommandBoot.none', () {
      expect(cmd.boot, CommandBoot.none);
    });

    test('description mentions lib/app/_plugins.g.dart', () {
      expect(cmd.description, contains('_plugins.g.dart'));
    });

    test('extends ArtisanCommand', () {
      expect(cmd, isA<ArtisanCommand>());
    });
  });

  group('PluginsRefreshCommand.handle()', () {
    test('empty registry emits empty providers list', () async {
      final fs = InMemoryFs();
      _seedLibApp(fs, '/proj');

      final code = await _cmd(fs, '/proj').handle(_ctx());
      final generated = fs.readAsString('/proj/lib/app/_plugins.g.dart');

      expect(code, 0);
      expect(
        generated,
        contains('List<ArtisanServiceProvider> autoDiscoveredProviders()'),
      );
      expect(generated, contains('return <ArtisanServiceProvider>[];'));
      // Header pinned to the regenerate hint so users know what to run.
      expect(generated, contains('GENERATED'));
      expect(generated, contains('plugins:refresh'));
      // Empty registry => no plugin import lines beyond the framework barrel.
      expect(generated,
          contains("import 'package:fluttersdk_artisan/artisan.dart';"));
      // No tmp leftover after atomic rename.
      expect(fs.exists('/proj/lib/app/_plugins.g.dart.tmp'), isFalse);
    });

    test('single plugin emits one import + one constructor call', () async {
      final fs = InMemoryFs();
      _seedLibApp(fs, '/proj');
      fs.writeAsString(
        '/proj/.artisan/plugins.json',
        jsonEncode(<String, dynamic>{
          'version': 1,
          'plugins': [
            <String, dynamic>{
              'name': 'magic_logger',
              'providerImport': 'package:magic_logger/cli.dart',
              'providerClass': 'MagicLoggerArtisanProvider',
              'registeredAt': '2026-05-18T09:00:00.000Z',
            },
          ],
        }),
      );

      final code = await _cmd(fs, '/proj').handle(_ctx());
      final generated = fs.readAsString('/proj/lib/app/_plugins.g.dart');

      expect(code, 0);
      expect(
        generated,
        contains(
          "import 'package:magic_logger/cli.dart' show MagicLoggerArtisanProvider;",
        ),
      );
      expect(generated, contains('MagicLoggerArtisanProvider(),'));
      expect(
        generated,
        contains('return <ArtisanServiceProvider>['),
      );
    });

    test('multiple plugins are sorted alphabetically by providerClass',
        () async {
      final fs = InMemoryFs();
      _seedLibApp(fs, '/proj');
      fs.writeAsString(
        '/proj/.artisan/plugins.json',
        jsonEncode(<String, dynamic>{
          'version': 1,
          'plugins': [
            <String, dynamic>{
              'name': 'z_logger',
              'providerImport': 'package:z_logger/cli.dart',
              'providerClass': 'ZLoggerArtisanProvider',
              'registeredAt': '2026-05-18T09:00:00.000Z',
            },
            <String, dynamic>{
              'name': 'a_logger',
              'providerImport': 'package:a_logger/cli.dart',
              'providerClass': 'ALoggerArtisanProvider',
              'registeredAt': '2026-05-18T09:01:00.000Z',
            },
          ],
        }),
      );

      final code = await _cmd(fs, '/proj').handle(_ctx());
      final generated = fs.readAsString('/proj/lib/app/_plugins.g.dart');

      expect(code, 0);
      final aIdx = generated.indexOf('ALoggerArtisanProvider');
      final zIdx = generated.indexOf('ZLoggerArtisanProvider');
      expect(aIdx, greaterThan(0));
      expect(zIdx, greaterThan(aIdx),
          reason: 'A* must precede Z* in deterministic output');
    });

    test('two plugins sharing providerClass hard-errors with both names',
        () async {
      final fs = InMemoryFs();
      _seedLibApp(fs, '/proj');
      fs.writeAsString(
        '/proj/.artisan/plugins.json',
        jsonEncode(<String, dynamic>{
          'version': 1,
          'plugins': [
            <String, dynamic>{
              'name': 'logger_a',
              'providerImport': 'package:logger_a/cli.dart',
              'providerClass': 'SameClassProvider',
              'registeredAt': '2026-05-18T09:00:00.000Z',
            },
            <String, dynamic>{
              'name': 'logger_b',
              'providerImport': 'package:logger_b/cli.dart',
              'providerClass': 'SameClassProvider',
              'registeredAt': '2026-05-18T09:01:00.000Z',
            },
          ],
        }),
      );

      await expectLater(
        _cmd(fs, '/proj').handle(_ctx()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('SameClassProvider'),
              contains('logger_a'),
              contains('logger_b'),
            ),
          ),
        ),
      );
    });

    test('missing lib/app/ directory hard-errors with bootstrap hint',
        () async {
      final fs = InMemoryFs();
      // NOTE: no _seedLibApp call so lib/app/ does not exist.
      fs.writeAsString(
        '/proj/.artisan/plugins.json',
        jsonEncode(<String, dynamic>{
          'version': 1,
          'plugins': <dynamic>[],
        }),
      );

      await expectLater(
        _cmd(fs, '/proj').handle(_ctx()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('lib/app/'),
              contains('magic:artisan install'),
            ),
          ),
        ),
      );
    });

    test('codegen is byte-identical across two consecutive runs (idempotent)',
        () async {
      final fs = InMemoryFs();
      _seedLibApp(fs, '/proj');
      fs.writeAsString(
        '/proj/.artisan/plugins.json',
        jsonEncode(<String, dynamic>{
          'version': 1,
          'plugins': [
            <String, dynamic>{
              'name': 'b_logger',
              'providerImport': 'package:b_logger/cli.dart',
              'providerClass': 'BLoggerArtisanProvider',
              'registeredAt': '2026-05-18T09:00:00.000Z',
            },
            <String, dynamic>{
              'name': 'a_logger',
              'providerImport': 'package:a_logger/cli.dart',
              'providerClass': 'ALoggerArtisanProvider',
              'registeredAt': '2026-05-18T09:01:00.000Z',
            },
          ],
        }),
      );

      final cmd = _cmd(fs, '/proj');
      await cmd.handle(_ctx());
      final first = fs.readAsString('/proj/lib/app/_plugins.g.dart');
      await cmd.handle(_ctx());
      final second = fs.readAsString('/proj/lib/app/_plugins.g.dart');

      expect(second, first,
          reason: 'codegen must be deterministic across consecutive runs');
    });

    test('malformed providerClass identifier is rejected', () async {
      final fs = InMemoryFs();
      _seedLibApp(fs, '/proj');
      fs.writeAsString(
        '/proj/.artisan/plugins.json',
        jsonEncode(<String, dynamic>{
          'version': 1,
          'plugins': [
            <String, dynamic>{
              'name': 'evil',
              'providerImport': 'package:evil/cli.dart',
              // Injection attempt: not a valid Dart identifier.
              'providerClass': 'Evil(); main() { print("pwned"); class X',
              'registeredAt': '2026-05-18T09:00:00.000Z',
            },
          ],
        }),
      );

      await expectLater(
        _cmd(fs, '/proj').handle(_ctx()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('providerClass'),
              contains('evil'),
            ),
          ),
        ),
      );
    });

    test('emits success summary mentioning count and output path', () async {
      final fs = InMemoryFs();
      _seedLibApp(fs, '/proj');
      fs.writeAsString(
        '/proj/.artisan/plugins.json',
        jsonEncode(<String, dynamic>{
          'version': 1,
          'plugins': [
            <String, dynamic>{
              'name': 'magic_logger',
              'providerImport': 'package:magic_logger/cli.dart',
              'providerClass': 'MagicLoggerArtisanProvider',
              'registeredAt': '2026-05-18T09:00:00.000Z',
            },
          ],
        }),
      );

      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const <String, dynamic>{}),
        output,
      );

      final code = await _cmd(fs, '/proj').handle(ctx);

      expect(code, 0);
      expect(output.content, contains('1'));
      expect(output.content, contains('lib/app/_plugins.g.dart'));
    });
  });
}
