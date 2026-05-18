import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:fluttersdk_artisan/artisan.dart';

/// Helper: build a [McpToolDescriptor] with a given [name] and provider prefix.
McpToolDescriptor _tool(String name, String extensionMethod) =>
    McpToolDescriptor(
      name: name,
      description: 'Test tool $name.',
      inputSchema: const {'type': 'object', 'properties': {}},
      extensionMethod: extensionMethod,
    );

void main() {
  // ---------------------------------------------------------------------------
  // McpFilterConfig.fromFile
  // ---------------------------------------------------------------------------
  group('McpFilterConfig.fromFile', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mcp_filter_config_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('parses null allow-list as "allow all" (packagesAllow is null)', () {
      final file = File('${tempDir.path}/mcp.json');
      file.writeAsStringSync(jsonEncode({
        'packages': {'allow': null, 'deny': []},
        'tools': {'allow': null, 'deny': []},
      }));

      final config = McpFilterConfig.fromFile(file.path);

      expect(config.packagesAllow, isNull);
      expect(config.toolsAllow, isNull);
    });

    test('parses empty deny list as "deny none"', () {
      final file = File('${tempDir.path}/mcp.json');
      file.writeAsStringSync(jsonEncode({
        'packages': {'allow': null, 'deny': []},
        'tools': {'allow': null, 'deny': []},
      }));

      final config = McpFilterConfig.fromFile(file.path);

      expect(config.packagesDeny, isEmpty);
      expect(config.toolsDeny, isEmpty);
    });

    test('parses explicit allow list as a Set<String>', () {
      final file = File('${tempDir.path}/mcp.json');
      file.writeAsStringSync(jsonEncode({
        'packages': {
          'allow': ['x', 'y'],
          'deny': ['z'],
        },
        'tools': {
          'allow': ['dusk_snap'],
          'deny': ['telescope_tail'],
        },
      }));

      final config = McpFilterConfig.fromFile(file.path);

      expect(config.packagesAllow, equals({'x', 'y'}));
      expect(config.packagesDeny, equals({'z'}));
      expect(config.toolsAllow, equals({'dusk_snap'}));
      expect(config.toolsDeny, equals({'telescope_tail'}));
    });

    test('throws FormatException for missing file', () {
      expect(
        () => McpFilterConfig.fromFile('${tempDir.path}/nonexistent.json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // McpFilterConfig.fromEnv
  // ---------------------------------------------------------------------------
  group('McpFilterConfig.fromEnv', () {
    test('empty map produces empty config (all-pass sentinel)', () {
      final config = McpFilterConfig.fromEnv({});

      expect(config.packagesAllow, isNull);
      expect(config.packagesDeny, isEmpty);
      expect(config.toolsAllow, isNull);
      expect(config.toolsDeny, isEmpty);
    });

    test('CSV parsing: single value', () {
      final config = McpFilterConfig.fromEnv({
        'ARTISAN_MCP_PACKAGES_ALLOW': 'fluttersdk_dusk',
      });

      expect(config.packagesAllow, equals({'fluttersdk_dusk'}));
    });

    test('CSV parsing: multiple values', () {
      final config = McpFilterConfig.fromEnv({
        'ARTISAN_MCP_PACKAGES_ALLOW': 'fluttersdk_dusk,fluttersdk_telescope',
        'ARTISAN_MCP_PACKAGES_DENY': 'fluttersdk_tinker',
        'ARTISAN_MCP_TOOLS_ALLOW': 'dusk_snap,dusk_tap',
        'ARTISAN_MCP_TOOLS_DENY': 'telescope_http',
      });

      expect(
        config.packagesAllow,
        equals({'fluttersdk_dusk', 'fluttersdk_telescope'}),
      );
      expect(config.packagesDeny, equals({'fluttersdk_tinker'}));
      expect(config.toolsAllow, equals({'dusk_snap', 'dusk_tap'}));
      expect(config.toolsDeny, equals({'telescope_http'}));
    });

    test('CSV parsing: whitespace around commas is trimmed', () {
      final config = McpFilterConfig.fromEnv({
        'ARTISAN_MCP_PACKAGES_ALLOW': ' pkg_a , pkg_b ',
      });

      expect(config.packagesAllow, equals({'pkg_a', 'pkg_b'}));
    });

    test('CSV parsing: empty string yields null allow-list', () {
      final config = McpFilterConfig.fromEnv({
        'ARTISAN_MCP_PACKAGES_ALLOW': '',
      });

      expect(config.packagesAllow, isNull);
    });

    test('CSV parsing: whitespace-only string yields null allow-list', () {
      final config = McpFilterConfig.fromEnv({
        'ARTISAN_MCP_PACKAGES_ALLOW': '   ',
      });

      expect(config.packagesAllow, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // McpFilterConfig.fromCli
  // ---------------------------------------------------------------------------
  group('McpFilterConfig.fromCli', () {
    test('null args produce empty config', () {
      final config = McpFilterConfig.fromCli();

      expect(config.packagesAllow, isNull);
      expect(config.packagesDeny, isEmpty);
      expect(config.toolsAllow, isNull);
      expect(config.toolsDeny, isEmpty);
    });

    test('repeated flags accumulate into allow/deny sets', () {
      final config = McpFilterConfig.fromCli(
        includePackage: ['fluttersdk_dusk', 'fluttersdk_telescope'],
        excludePackage: ['fluttersdk_tinker'],
        includeTool: ['dusk_snap'],
        excludeTool: ['telescope_http'],
      );

      expect(
        config.packagesAllow,
        equals({'fluttersdk_dusk', 'fluttersdk_telescope'}),
      );
      expect(config.packagesDeny, equals({'fluttersdk_tinker'}));
      expect(config.toolsAllow, equals({'dusk_snap'}));
      expect(config.toolsDeny, equals({'telescope_http'}));
    });

    test('empty list args produce null allow-list', () {
      final config = McpFilterConfig.fromCli(
        includePackage: [],
        includeTool: [],
      );

      expect(config.packagesAllow, isNull);
      expect(config.toolsAllow, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // McpFilterConfig.empty
  // ---------------------------------------------------------------------------
  group('McpFilterConfig.empty', () {
    test('empty() has no allow or deny constraints', () {
      final config = McpFilterConfig.empty();

      expect(config.packagesAllow, isNull);
      expect(config.packagesDeny, isEmpty);
      expect(config.toolsAllow, isNull);
      expect(config.toolsDeny, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // McpFilterConfig.merge (Cargo-style replace + deny-wins)
  // ---------------------------------------------------------------------------
  group('McpFilterConfig.merge', () {
    test('CLI allow-list replaces env and file allow-lists (Cargo precedence)',
        () {
      final file = McpFilterConfig(
        packagesAllow: const {'x', 'y'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );
      final env = McpFilterConfig(
        packagesAllow: const {'z'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );
      final cli = McpFilterConfig(
        packagesAllow: const {'a', 'b'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );

      final merged = McpFilterConfig.merge(file, env, cli);

      // CLI replaces both env and file: only {a, b} survive.
      expect(merged.packagesAllow, equals({'a', 'b'}));
    });

    test('env allow-list replaces file allow-list when no CLI allow-list', () {
      final file = McpFilterConfig(
        packagesAllow: const {'x', 'y'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );
      final env = McpFilterConfig(
        packagesAllow: const {'z'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );

      final merged = McpFilterConfig.merge(file, env, McpFilterConfig.empty());

      expect(merged.packagesAllow, equals({'z'}));
    });

    test('file allow-list used when env and CLI are both empty', () {
      final file = McpFilterConfig(
        packagesAllow: const {'x', 'y'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );

      final merged = McpFilterConfig.merge(
        file,
        McpFilterConfig.empty(),
        McpFilterConfig.empty(),
      );

      expect(merged.packagesAllow, equals({'x', 'y'}));
    });

    test(
        'null allow-list cascades: if CLI is null, env wins; if env null, file wins',
        () {
      final file = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );
      final env = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );

      final merged = McpFilterConfig.merge(file, env, McpFilterConfig.empty());

      // All layers are null ("allow all") so merged is also null.
      expect(merged.packagesAllow, isNull);
    });

    test('deny lists from all layers UNION (deny wins over allow)', () {
      final file = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {'pkg_a'},
        toolsAllow: null,
        toolsDeny: const {'tool_1'},
      );
      final env = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {'pkg_b'},
        toolsAllow: null,
        toolsDeny: const {'tool_2'},
      );
      final cli = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {'pkg_c'},
        toolsAllow: null,
        toolsDeny: const {'tool_3'},
      );

      final merged = McpFilterConfig.merge(file, env, cli);

      expect(merged.packagesDeny, equals({'pkg_a', 'pkg_b', 'pkg_c'}));
      expect(merged.toolsDeny, equals({'tool_1', 'tool_2', 'tool_3'}));
    });

    // -------------------------------------------------------------------------
    // Oracle I6 LOAD-BEARING worked example
    // -------------------------------------------------------------------------
    test(
        'Oracle I6: file={x,y} env={z} cli={a,b} -> packagesAllow={a,b}; '
        'env deny={a} -> apply returns only tools from package {b}', () {
      // Step 1: build the three layers exactly as specified in Oracle I6.
      final fileConfig = McpFilterConfig(
        packagesAllow: const {'x', 'y'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );
      final envConfig = McpFilterConfig(
        packagesAllow: const {'z'},
        packagesDeny: const {'a'}, // deny package 'a'
        toolsAllow: null,
        toolsDeny: const {},
      );
      final cliConfig = McpFilterConfig(
        packagesAllow: const {'a', 'b'}, // repeated flags accumulated
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );

      // Step 2: merge; CLI wins for allow; deny UNION.
      final merged = McpFilterConfig.merge(fileConfig, envConfig, cliConfig);

      expect(
        merged.packagesAllow,
        equals({'a', 'b'}),
        reason: 'CLI replaces env+file for allow list',
      );
      expect(
        merged.packagesDeny,
        equals({'a'}),
        reason: 'deny lists UNION across layers',
      );

      // Step 3: apply with a providerNameLookup that maps tool names to packages.
      final tools = [
        _tool('tool_from_a', 'ext.a.something'),
        _tool('tool_from_b', 'ext.b.something'),
        _tool('tool_from_x', 'ext.x.something'),
      ];

      String providerLookup(McpToolDescriptor t) {
        if (t.name.contains('_from_a')) return 'a';
        if (t.name.contains('_from_b')) return 'b';
        return 'x';
      }

      final result = merged.apply(tools, providerLookup);

      // 'a' is in packagesAllow but also in packagesDeny; deny wins.
      // 'b' is in packagesAllow and NOT in packagesDeny; survives.
      // 'x' is NOT in packagesAllow; excluded.
      expect(
        result.map((t) => t.name).toList(),
        equals(['tool_from_b']),
        reason: 'deny wins over allow; only package b survives',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // McpFilterConfig.apply
  // ---------------------------------------------------------------------------
  group('McpFilterConfig.apply', () {
    final allTools = [
      _tool('dusk_snap', 'ext.dusk.snap'),
      _tool('dusk_tap', 'ext.dusk.tap'),
      _tool('telescope_http', 'ext.telescope.http'),
      _tool('telescope_exceptions', 'ext.telescope.exceptions'),
      _tool('tinker_evaluate', 'ext.tinker.evaluate'),
    ];

    String packageOf(McpToolDescriptor t) {
      if (t.name.startsWith('dusk_')) return 'fluttersdk_dusk';
      if (t.name.startsWith('telescope_')) return 'fluttersdk_telescope';
      return 'magic_tinker';
    }

    test('empty() config passes all tools through unfiltered', () {
      final result = McpFilterConfig.empty().apply(allTools, packageOf);

      expect(result, hasLength(allTools.length));
      expect(
          result.map((t) => t.name), containsAll(allTools.map((t) => t.name)));
    });

    test('packagesDeny=[fluttersdk_telescope] removes all telescope tools', () {
      final config = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {'fluttersdk_telescope'},
        toolsAllow: null,
        toolsDeny: const {},
      );

      final result = config.apply(allTools, packageOf);

      expect(result.any((t) => t.name.startsWith('telescope_')), isFalse);
      expect(result, hasLength(3)); // dusk x2 + tinker x1
    });

    test('toolsAllow=[dusk_snap] keeps only that one tool', () {
      final config = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {},
        toolsAllow: const {'dusk_snap'},
        toolsDeny: const {},
      );

      final result = config.apply(allTools, packageOf);

      expect(result, hasLength(1));
      expect(result.first.name, 'dusk_snap');
    });

    test('toolsDeny removes specific tools regardless of package allow', () {
      final config = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {'dusk_tap', 'tinker_evaluate'},
      );

      final result = config.apply(allTools, packageOf);

      expect(result.map((t) => t.name), isNot(contains('dusk_tap')));
      expect(result.map((t) => t.name), isNot(contains('tinker_evaluate')));
      expect(result, hasLength(3));
    });

    test(
        'packagesAllow restricts to named packages; tools from others excluded',
        () {
      final config = McpFilterConfig(
        packagesAllow: const {'fluttersdk_dusk'},
        packagesDeny: const {},
        toolsAllow: null,
        toolsDeny: const {},
      );

      final result = config.apply(allTools, packageOf);

      expect(result.every((t) => t.name.startsWith('dusk_')), isTrue);
      expect(result, hasLength(2));
    });

    test('toolsDeny wins over toolsAllow when same tool is in both', () {
      final config = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {},
        toolsAllow: const {'dusk_snap'},
        toolsDeny: const {'dusk_snap'},
      );

      final result = config.apply(allTools, packageOf);

      // toolsDeny wins: result is empty.
      expect(result, isEmpty);
    });

    test('packagesDeny wins over packagesAllow when same package is in both',
        () {
      final config = McpFilterConfig(
        packagesAllow: const {'fluttersdk_dusk'},
        packagesDeny: const {'fluttersdk_dusk'},
        toolsAllow: null,
        toolsDeny: const {},
      );

      final result = config.apply(allTools, packageOf);

      expect(result.any((t) => t.name.startsWith('dusk_')), isFalse);
    });

    test('name matching is case-sensitive', () {
      final config = McpFilterConfig(
        packagesAllow: null,
        packagesDeny: const {},
        toolsAllow: const {'Dusk_Snap'}, // wrong case
        toolsDeny: const {},
      );

      // No tool named 'Dusk_Snap' exists; result is empty.
      final result = config.apply(allTools, packageOf);

      expect(result, isEmpty);
    });
  });
}
