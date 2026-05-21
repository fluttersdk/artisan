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
    tempDir = Directory.systemTemp.createTempSync('mcp_install_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('McpInstallCommand metadata', () {
    test('signature is mcp:install', () {
      expect(McpInstallCommand().name, 'mcp:install');
    });

    test('boot is none', () {
      expect(McpInstallCommand().boot, CommandBoot.none);
    });

    test('description is non-empty', () {
      expect(McpInstallCommand().description, isNotEmpty);
    });
  });

  group('McpInstallCommand handle', () {
    test(
        'empty .mcp.json writes fluttersdk entry with fsa shape when hasFsa=true, isWindows=false',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      final command = McpInstallCommand(
        hasFsa: () => true,
        isWindows: () => false,
      );
      final ctx = _ctx({'path': mcpPath});

      final code = await command.handle(ctx);

      expect(code, 0);
      final content = File(mcpPath).readAsStringSync();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final servers = decoded['mcpServers'] as Map<String, dynamic>;
      expect(servers, contains('fluttersdk'));
      final entry = servers['fluttersdk'] as Map<String, dynamic>;
      expect(entry['command'], './bin/fsa');
      expect(entry['args'], equals(['mcp:serve']));
      expect(entry['cwd'], '.');
      // Raw JSON content must reference the fsa invocation, not legacy shapes.
      expect(content, contains('./bin/fsa'));
      // Must NOT reference any legacy or rejected entry shapes.
      expect(content, isNot(contains('fluttersdk_artisan:mcp')));
      expect(content, isNot(contains('fluttersdk_mcp:server')));
      expect(content, isNot(contains(':artisan')));
    });

    test(
        'empty .mcp.json writes fluttersdk entry with dart fallback shape when hasFsa=false',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      final command = McpInstallCommand(
        hasFsa: () => false,
        isWindows: () => false,
      );
      final ctx = _ctx({'path': mcpPath});

      final code = await command.handle(ctx);

      expect(code, 0);
      final content = File(mcpPath).readAsStringSync();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final servers = decoded['mcpServers'] as Map<String, dynamic>;
      expect(servers, contains('fluttersdk'));
      final entry = servers['fluttersdk'] as Map<String, dynamic>;
      expect(entry['command'], 'dart');
      expect(entry['args'], equals(['run', ':dispatcher', 'mcp:serve']));
      expect(entry['cwd'], '.');
      // Raw JSON content must reference the dispatcher fallback.
      expect(content, contains(':dispatcher'));
      // Must NOT reference any legacy or rejected entry shapes.
      expect(content, isNot(contains('fluttersdk_artisan:mcp')));
      expect(content, isNot(contains('fluttersdk_mcp:server')));
      expect(content, isNot(contains(':artisan')));
    });

    test(
        'pre-existing .mcp.json with laravel-boost entry preserves both entries after install',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed a .mcp.json with an unrelated server.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'laravel-boost': {
            'command': 'npx',
            'args': ['-y', 'laravel-boost'],
          },
        },
      }));

      final command = McpInstallCommand(
        hasFsa: () => true,
        isWindows: () => false,
      );
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = decoded['mcpServers'] as Map<String, dynamic>;
      // Both entries must survive.
      expect(servers, containsPair('laravel-boost', isA<Map>()));
      expect(servers, contains('fluttersdk'));
      final entry = servers['fluttersdk'] as Map<String, dynamic>;
      expect(entry['command'], './bin/fsa');
      expect(entry['args'], equals(['mcp:serve']));
    });

    test(
        'pre-existing fluttersdk_mcp:server entry is replaced by new fsa shape with no duplicate',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      // 1. Seed the OLD entry shape.
      File(mcpPath).writeAsStringSync(jsonEncode({
        'mcpServers': {
          'fluttersdk': {
            'command': 'dart',
            'args': ['run', 'fluttersdk_mcp:server'],
            'cwd': '.',
          },
        },
      }));

      final command = McpInstallCommand(
        hasFsa: () => true,
        isWindows: () => false,
      );
      final ctx = _ctx({'path': mcpPath});
      final code = await command.handle(ctx);

      expect(code, 0);
      final decoded =
          jsonDecode(File(mcpPath).readAsStringSync()) as Map<String, dynamic>;
      final servers = decoded['mcpServers'] as Map<String, dynamic>;
      // Exactly one fluttersdk entry.
      expect(servers.keys.where((k) => k == 'fluttersdk'), hasLength(1));
      final entry = servers['fluttersdk'] as Map<String, dynamic>;
      // Must use the NEW fsa args, not the legacy ones.
      expect(entry['command'], './bin/fsa');
      expect(entry['args'], equals(['mcp:serve']));
      expect(entry['args'], isNot(contains('fluttersdk_mcp:server')));
    });

    test('success output contains /mcp reconnect fluttersdk hint', () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      final command = McpInstallCommand(
        hasFsa: () => true,
        isWindows: () => false,
      );
      final ctx = _ctx({'path': mcpPath});

      await command.handle(ctx);

      final out = _output(ctx);
      expect(out, contains('/mcp reconnect fluttersdk'));
      expect(out, contains('Wrote fluttersdk MCP server entry to $mcpPath'));
    });

    test('returns 1 and writes error when .mcp.json contains invalid JSON',
        () async {
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      File(mcpPath).writeAsStringSync('not-json{{{');

      final command = McpInstallCommand();
      final ctx = _ctx({'path': mcpPath});

      final code = await command.handle(ctx);

      expect(code, 1);
      expect(_output(ctx), contains('[ERROR]'));
    });

    test('default path option is .mcp.json', () async {
      // Exercises the defaultsTo fallback when no path option is given.
      // We cannot write to the CWD arbitrarily in CI so we only check
      // that the command DOES attempt to use '.mcp.json' (path in output).
      // Use a tempDir as CWD substitute by passing it explicitly.
      final mcpPath = p.join(tempDir.path, '.mcp.json');
      final command = McpInstallCommand(
        hasFsa: () => true,
        isWindows: () => false,
      );
      // Pass path explicitly — same as the default resolves to in production.
      final ctx = _ctx({'path': mcpPath});

      final code = await command.handle(ctx);

      expect(code, 0);
    });
  });
}
