import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds a bare [ArtisanContext] with the given option map and a
/// [BufferedOutput] for assertion.
ArtisanContext _ctx(Map<String, dynamic> options) {
  return ArtisanContext.bare(MapInput(options), BufferedOutput());
}

/// Reads the output captured on [ctx]'s [BufferedOutput].
String _output(ArtisanContext ctx) => (ctx.output as BufferedOutput).content;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mcp_uninstall_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('McpUninstallCommand metadata', () {
    test('signature is mcp:uninstall', () {
      expect(McpUninstallCommand().name, 'mcp:uninstall');
    });

    test('boot is none', () {
      expect(McpUninstallCommand().boot, CommandBoot.none);
    });

    test('description is non-empty', () {
      expect(McpUninstallCommand().description, isNotEmpty);
    });
  });

  group('McpUninstallCommand handle — new entry shape (fluttersdk_artisan:mcp)',
      () {
    test(
        'removes fluttersdk entry that uses the post-fix fsa shape (./bin/fsa mcp:serve)',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed the post-fix fsa entry shape.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'fluttersdk': {
            'command': './bin/fsa',
            'args': ['mcp:serve'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = (decoded['mcpServers'] as Map<String, dynamic>?) ?? {};
      expect(servers, isNot(contains('fluttersdk')));
    });

    test(
        'removes fluttersdk entry that uses the post-fix dart fallback shape (dart run :dispatcher mcp:serve)',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed the post-fix dart-fallback entry shape.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', ':dispatcher', 'mcp:serve'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = (decoded['mcpServers'] as Map<String, dynamic>?) ?? {};
      expect(servers, isNot(contains('fluttersdk')));
    });

    test('removes fluttersdk entry that uses the new artisan args shape',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed new-shape entry.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_artisan:mcp'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = (decoded['mcpServers'] as Map<String, dynamic>?) ?? {};
      expect(servers, isNot(contains('fluttersdk')));
    });

    test(
        'preserves laravel-boost entry when removing new-shape fluttersdk entry',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed both entries.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'laravel-boost': {
            'command': 'npx',
            'args': ['-y', 'laravel-boost'],
          },
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_artisan:mcp'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = decoded['mcpServers'] as Map<String, dynamic>;
      expect(servers, containsPair('laravel-boost', isA<Map>()));
      expect(servers, isNot(contains('fluttersdk')));
    });
  });

  group(
      'McpUninstallCommand handle — legacy entry shape (fluttersdk_mcp:server)',
      () {
    test('removes fluttersdk entry that uses the legacy mcp args shape',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed legacy-shape entry.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_mcp:server'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = (decoded['mcpServers'] as Map<String, dynamic>?) ?? {};
      expect(servers, isNot(contains('fluttersdk')));
    });

    test(
        'preserves laravel-boost entry when removing legacy-shape fluttersdk entry',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed both entries.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'laravel-boost': {
            'command': 'npx',
            'args': ['-y', 'laravel-boost'],
          },
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_mcp:server'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = decoded['mcpServers'] as Map<String, dynamic>;
      expect(servers, containsPair('laravel-boost', isA<Map>()));
      expect(servers, isNot(contains('fluttersdk')));
    });
  });

  group('McpUninstallCommand handle — idempotency', () {
    test('running twice does not error when entry already removed', () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_artisan:mcp'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      // First run removes the entry.
      await command.handle(_ctx({'path': mcpPath}));
      // Second run must return 0 with a warning, never throw.
      final ctx2 = _ctx({'path': mcpPath});
      final code2 = await command.handle(ctx2);

      expect(code2, 0);
      expect(_output(ctx2).toLowerCase(), contains('nothing to uninstall'));
    });
  });

  group('McpUninstallCommand handle — missing entry', () {
    test('warns and returns 0 when fluttersdk key is absent from mcpServers',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed .mcp.json without a fluttersdk entry.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'laravel-boost': {
            'command': 'npx',
            'args': ['-y', 'laravel-boost'],
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      expect(_output(ctx).toLowerCase(), contains('nothing to uninstall'));
    });

    test('warns and returns 0 when .mcp.json file does not exist', () async {
      final mcpPath = p.join(tempDir.path, 'nonexistent.json');

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      expect(_output(ctx).toLowerCase(), contains('does not exist'));
    });
  });

  group('McpUninstallCommand handle — file preservation', () {
    test(
        'does NOT delete the .mcp.json file even when mcpServers becomes empty',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // Only entry is fluttersdk — after removal mcpServers is empty.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_artisan:mcp'],
            'cwd': '.',
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      await command.handle(ctx);

      // File must still exist with an empty mcpServers map.
      expect(File(mcpPath).existsSync(), isTrue);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['mcpServers'], isEmpty);
    });

    test('does NOT touch non-mcpServers keys', () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      File(mcpPath).writeAsStringSync(jsonEncode({
        'version': 1,
        'mcpServers': {
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_artisan:mcp'],
          },
        },
      }));

      final command = McpUninstallCommand();
      final ctx = _ctx({'path': mcpPath});
      await command.handle(ctx);

      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['version'], 1);
    });
  });

  group('McpUninstallCommand handle — default path', () {
    test('default path option is .mcp.json', () {
      // Verify the configure() default without invoking file I/O.
      final command = McpUninstallCommand();
      final parser = ArgParser();
      command.configure(parser);
      final result = parser.parse(const []);
      expect(result.option('path'), '.mcp.json');
    });
  });
}
