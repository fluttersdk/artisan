import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Capture-only serve stub: records the call and returns immediately without
/// spawning any VM Service connection or blocking on stdio.
Future<void> _noOpServe({
  required ArtisanRegistry registry,
  required McpFilterConfig filter,
}) async {
  // Intentional no-op: unit tests must not block on a live stdio connection.
}

void main() {
  group('McpServeCommand', () {
    // -------------------------------------------------------------------------
    // Metadata
    // -------------------------------------------------------------------------

    test('signature is mcp:serve', () {
      final command = McpServeCommand();

      expect(command.name, 'mcp:serve');
    });

    test('boot is none (pure CLI, no VM Service connect)', () {
      final command = McpServeCommand();

      expect(command.boot, CommandBoot.none);
    });

    test('description is non-empty and mentions MCP server', () {
      final command = McpServeCommand();

      expect(command.description, isNotEmpty);
      expect(command.description, contains('MCP server'));
    });

    // -------------------------------------------------------------------------
    // configure: 4 multi-option flags
    // -------------------------------------------------------------------------

    test('configure registers all 4 multi-option flags', () {
      final command = McpServeCommand();
      final parser = ArgParser();
      command.configure(parser);

      expect(parser.options.containsKey('include-package'), isTrue);
      expect(parser.options.containsKey('exclude-package'), isTrue);
      expect(parser.options.containsKey('include-tool'), isTrue);
      expect(parser.options.containsKey('exclude-tool'), isTrue);
    });

    test('all 4 flags accept multiple values', () {
      final command = McpServeCommand();
      final parser = ArgParser();
      command.configure(parser);

      // `allowMultiple` flags return List<String> from parse.
      final results = parser.parse([
        '--include-package',
        'x',
        '--include-package',
        'y',
        '--exclude-tool',
        'z',
      ]);

      expect(results['include-package'], ['x', 'y']);
      expect(results['exclude-tool'], ['z']);
      expect(results['exclude-package'], <String>[]);
      expect(results['include-tool'], <String>[]);
    });

    // -------------------------------------------------------------------------
    // CLI flag → McpFilterConfig.fromCli round-trip
    // -------------------------------------------------------------------------

    test('--include-package and --exclude-tool populate cliConfig correctly',
        () {
      final command = McpServeCommand();
      final parser = ArgParser();
      command.configure(parser);

      final results = parser.parse([
        '--include-package',
        'x',
        '--include-package',
        'y',
        '--exclude-tool',
        'z',
      ]);

      final includePackage =
          (results['include-package'] as List).cast<String>();
      final excludePackage =
          (results['exclude-package'] as List).cast<String>();
      final includeTool = (results['include-tool'] as List).cast<String>();
      final excludeTool = (results['exclude-tool'] as List).cast<String>();

      final cliConfig = McpFilterConfig.fromCli(
        includePackage: includePackage,
        excludePackage: excludePackage,
        includeTool: includeTool,
        excludeTool: excludeTool,
      );

      expect(cliConfig.packagesAllow, {'x', 'y'});
      expect(cliConfig.toolsDeny, {'z'});
      expect(cliConfig.packagesDeny, isEmpty);
      expect(cliConfig.toolsAllow, isNull);
    });

    // -------------------------------------------------------------------------
    // Help text includes reconnect hint
    // -------------------------------------------------------------------------

    test('description contains reconnect hint', () {
      final command = McpServeCommand();

      // The reconnect hint must appear in the command's description or in the
      // extended help string (plan step: APPEND hint paragraph to description).
      expect(
        command.description,
        contains('/mcp reconnect fluttersdk'),
      );
    });

    // -------------------------------------------------------------------------
    // Environment variable → McpFilterConfig.fromEnv
    // -------------------------------------------------------------------------

    test('env var ARTISAN_MCP_PACKAGES_ALLOW populates envConfig', () {
      final env = <String, String>{
        'ARTISAN_MCP_PACKAGES_ALLOW': 'fluttersdk_dusk,fluttersdk_telescope',
      };

      final envConfig = McpFilterConfig.fromEnv(env);

      expect(
        envConfig.packagesAllow,
        {'fluttersdk_dusk', 'fluttersdk_telescope'},
      );
    });

    test('env var ARTISAN_MCP_TOOLS_DENY populates envConfig', () {
      final env = <String, String>{
        'ARTISAN_MCP_TOOLS_DENY': 'dusk_snap',
      };

      final envConfig = McpFilterConfig.fromEnv(env);

      expect(envConfig.toolsDeny, {'dusk_snap'});
    });

    // -------------------------------------------------------------------------
    // File config → McpFilterConfig.fromFile
    // -------------------------------------------------------------------------

    test('fileConfig populates when .artisan/mcp.json exists', () async {
      final tempDir = Directory.systemTemp.createTempSync('artisan_mcp_serve_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final artisanDir = Directory('${tempDir.path}/.artisan')..createSync();
      final mcpJson = File('${artisanDir.path}/mcp.json');
      mcpJson.writeAsStringSync('''
{
  "packages": { "allow": null, "deny": ["fluttersdk_telescope"] },
  "tools":    { "allow": null, "deny": [] }
}
''');

      final fileConfig = McpFilterConfig.fromFile(mcpJson.path);

      expect(fileConfig.packagesDeny, {'fluttersdk_telescope'});
      expect(fileConfig.packagesAllow, isNull);
    });

    test('fileConfig is empty when file absent', () {
      final fileConfig = McpFilterConfig.empty();

      expect(fileConfig.packagesAllow, isNull);
      expect(fileConfig.packagesDeny, isEmpty);
      expect(fileConfig.toolsAllow, isNull);
      expect(fileConfig.toolsDeny, isEmpty);
    });

    // -------------------------------------------------------------------------
    // Merge precedence (Cargo-style)
    // -------------------------------------------------------------------------

    test(
      'merge: CLI allow replaces env+file allow; deny is union across layers',
      () {
        // file: packagesAllow=null, packagesDeny={a}
        final fileConfig = McpFilterConfig(
          packagesAllow: null,
          packagesDeny: {'a'},
          toolsAllow: null,
          toolsDeny: {},
        );
        // env: packagesAllow={b}, packagesDeny={}
        final envConfig = McpFilterConfig(
          packagesAllow: {'b'},
          packagesDeny: {},
          toolsAllow: null,
          toolsDeny: {},
        );
        // cli: packagesAllow={c}, packagesDeny={}
        final cliConfig = McpFilterConfig(
          packagesAllow: {'c'},
          packagesDeny: {},
          toolsAllow: null,
          toolsDeny: {},
        );

        final merged = McpFilterConfig.merge(fileConfig, envConfig, cliConfig);

        // CLI replaces env+file for allow.
        expect(merged.packagesAllow, {'c'});
        // Deny is union: only file contributed {a}.
        expect(merged.packagesDeny, {'a'});
      },
    );

    test('merge: null cli allow falls through to env allow', () {
      final fileConfig = McpFilterConfig.empty();
      final envConfig = McpFilterConfig(
        packagesAllow: {'env_pkg'},
        packagesDeny: {},
        toolsAllow: null,
        toolsDeny: {},
      );
      final cliConfig = McpFilterConfig.empty();

      final merged = McpFilterConfig.merge(fileConfig, envConfig, cliConfig);

      // CLI is null allow → env's allow wins.
      expect(merged.packagesAllow, {'env_pkg'});
    });

    // -------------------------------------------------------------------------
    // handle: no-op serve path (stub injected to avoid live VM Service)
    // -------------------------------------------------------------------------

    test('handle returns 0 via stub serve when no mcp.json and no env',
        () async {
      final command = McpServeCommand(serveOverride: _noOpServe);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(const {
          'include-package': <String>[],
          'exclude-package': <String>[],
          'include-tool': <String>[],
          'exclude-tool': <String>[],
        }),
        output,
      );

      // Must not throw and must return 0.
      final code = await command.handle(ctx);

      expect(code, 0);
    });
  });
}
