import 'dart:convert';
import 'dart:io';

import 'mcp_tool_descriptor.dart';

/// Three-layer filter configuration for MCP tool discovery.
///
/// ### Axes
///
/// | Field | null means | non-null means |
/// |-------|-----------|----------------|
/// | [packagesAllow] | accept every package | accept only listed packages |
/// | [packagesDeny] | deny no package | deny listed packages (wins over allow) |
/// | [toolsAllow] | accept every tool name | accept only listed tool names |
/// | [toolsDeny] | deny no tool name | deny listed tool names (wins over allow) |
///
/// ### Precedence (Cargo-style replace)
///
/// Allow lists: CLI replaces env which replaces file. A non-null layer REPLACES
/// the lower layer entirely for the allow axis. When a layer carries a null
/// allow list it means "I have no opinion" and the next lower layer's opinion
/// is used. Repeated flags within one layer accumulate into a set.
///
/// Deny lists: the union of all three layers. A tool denied in any layer is
/// denied in the result; there is no way to un-deny at a higher layer.
///
/// ### Deny wins over allow
///
/// When a package (or tool) appears in both the effective allow set and the
/// effective deny set the deny wins. This matches Cargo's `--exclude` > `--features`
/// semantics and prevents an accidental allow from opening a blocked package.
///
/// Construct directly for testing, or via the three factory methods
/// ([fromFile], [fromEnv], [fromCli]) and then [merge].
final class McpFilterConfig {
  /// Creates a filter config with explicit field values.
  ///
  /// Pass `null` for [packagesAllow] or [toolsAllow] to mean "allow all".
  const McpFilterConfig({
    required this.packagesAllow,
    required this.packagesDeny,
    required this.toolsAllow,
    required this.toolsDeny,
  });

  /// Returns a "no filter" sentinel that passes every tool through [apply].
  ///
  /// All allow lists are null (allow all) and all deny lists are empty (deny
  /// none). Useful as the empty identity element in [merge].
  static McpFilterConfig empty() => const McpFilterConfig(
        packagesAllow: null,
        packagesDeny: {},
        toolsAllow: null,
        toolsDeny: {},
      );

  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  /// Package names to include. Null means include all packages.
  ///
  /// Evaluated against the result of `providerNameLookup(tool)` in [apply].
  final Set<String>? packagesAllow;

  /// Package names that are always excluded, even if they appear in [packagesAllow].
  ///
  /// Deny wins over allow; this set is UNIONed across all three layers by [merge].
  final Set<String> packagesDeny;

  /// Tool names to include. Null means include all tools.
  ///
  /// Evaluated against [McpToolDescriptor.name] in [apply].
  final Set<String>? toolsAllow;

  /// Tool names that are always excluded, even if they appear in [toolsAllow].
  ///
  /// Deny wins over allow; this set is UNIONed across all three layers by [merge].
  final Set<String> toolsDeny;

  // ---------------------------------------------------------------------------
  // Factory: fromFile
  // ---------------------------------------------------------------------------

  /// Parses `.artisan/mcp.json` at [path] synchronously.
  ///
  /// Expected JSON shape:
  /// ```json
  /// {
  ///   "packages": { "allow": null | [...], "deny": [...] },
  ///   "tools":    { "allow": null | [...], "deny": [...] }
  /// }
  /// ```
  ///
  /// Throws [FormatException] when the file does not exist, is not valid JSON,
  /// or does not match the expected shape.
  static McpFilterConfig fromFile(String path) {
    // 1. Read the file; missing file surfaces as a FormatException to callers.
    final raw = _readFileOrThrow(path);

    // 2. Decode JSON; malformed JSON also surfaces as FormatException.
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException(
          'McpFilterConfig: invalid JSON at $path: ${e.message}');
    }

    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'McpFilterConfig: expected a JSON object at $path, got ${decoded.runtimeType}.',
      );
    }

    // 3. Extract the two top-level sections.
    final packages = decoded['packages'];
    final tools = decoded['tools'];

    if (packages is! Map<String, dynamic>) {
      throw FormatException(
        'McpFilterConfig: "packages" key must be an object in $path.',
      );
    }
    if (tools is! Map<String, dynamic>) {
      throw FormatException(
        'McpFilterConfig: "tools" key must be an object in $path.',
      );
    }

    return McpFilterConfig(
      packagesAllow: _parseJsonAllow(packages['allow'], 'packages.allow', path),
      packagesDeny: _parseJsonDeny(packages['deny'], 'packages.deny', path),
      toolsAllow: _parseJsonAllow(tools['allow'], 'tools.allow', path),
      toolsDeny: _parseJsonDeny(tools['deny'], 'tools.deny', path),
    );
  }

  // ---------------------------------------------------------------------------
  // Factory: fromEnv
  // ---------------------------------------------------------------------------

  /// Parses filter configuration from environment variables.
  ///
  /// Recognised variables (all optional):
  ///
  /// | Variable | Effect |
  /// |----------|--------|
  /// | `ARTISAN_MCP_PACKAGES_ALLOW` | CSV of package names to include |
  /// | `ARTISAN_MCP_PACKAGES_DENY`  | CSV of package names to exclude |
  /// | `ARTISAN_MCP_TOOLS_ALLOW`    | CSV of tool names to include |
  /// | `ARTISAN_MCP_TOOLS_DENY`     | CSV of tool names to exclude |
  ///
  /// An absent or blank variable is treated as "no opinion" (null for allow
  /// lists, empty set for deny lists).
  static McpFilterConfig fromEnv(Map<String, String> env) => McpFilterConfig(
        packagesAllow: _parseCsvAllow(env['ARTISAN_MCP_PACKAGES_ALLOW']),
        packagesDeny: _parseCsvDeny(env['ARTISAN_MCP_PACKAGES_DENY']),
        toolsAllow: _parseCsvAllow(env['ARTISAN_MCP_TOOLS_ALLOW']),
        toolsDeny: _parseCsvDeny(env['ARTISAN_MCP_TOOLS_DENY']),
      );

  // ---------------------------------------------------------------------------
  // Factory: fromCli
  // ---------------------------------------------------------------------------

  /// Builds a filter config from parsed CLI option lists.
  ///
  /// Each parameter corresponds to a repeatable option flag:
  ///
  /// | Parameter | Flag (example) |
  /// |-----------|---------------|
  /// | [includePackage] | `--include-package=fluttersdk_dusk` |
  /// | [excludePackage] | `--exclude-package=fluttersdk_telescope` |
  /// | [includeTool] | `--include-tool=dusk_snap` |
  /// | [excludeTool] | `--exclude-tool=telescope_http` |
  ///
  /// An empty or absent list is treated as "no opinion" for allow, empty set
  /// for deny. Repeated flags within the same layer accumulate into a set.
  static McpFilterConfig fromCli({
    List<String>? includePackage,
    List<String>? excludePackage,
    List<String>? includeTool,
    List<String>? excludeTool,
  }) =>
      McpFilterConfig(
        packagesAllow: _listToAllow(includePackage),
        packagesDeny: _listToDeny(excludePackage),
        toolsAllow: _listToAllow(includeTool),
        toolsDeny: _listToDeny(excludeTool),
      );

  // ---------------------------------------------------------------------------
  // Merge
  // ---------------------------------------------------------------------------

  /// Merges three layers into a single effective filter using Cargo-style semantics.
  ///
  /// ### Allow precedence (replace, highest wins)
  ///
  /// CLI > env > file. The first non-null allow list in that order becomes the
  /// effective allow list; lower layers are ignored for allow. When all layers
  /// are null the effective allow is null (allow all).
  ///
  /// ### Deny union
  ///
  /// Deny sets from all three layers are UNIONed. A name denied by any layer is
  /// denied in the result.
  ///
  /// @param file Config parsed from `.artisan/mcp.json`.
  /// @param env Config parsed from environment variables.
  /// @param cli Config parsed from CLI flags.
  static McpFilterConfig merge(
    McpFilterConfig file,
    McpFilterConfig env,
    McpFilterConfig cli,
  ) =>
      McpFilterConfig(
        // 1. Allow lists: CLI replaces env replaces file (first non-null wins).
        packagesAllow:
            cli.packagesAllow ?? env.packagesAllow ?? file.packagesAllow,
        toolsAllow: cli.toolsAllow ?? env.toolsAllow ?? file.toolsAllow,

        // 2. Deny lists: UNION of all three layers (deny wins everywhere).
        packagesDeny: {
          ...file.packagesDeny,
          ...env.packagesDeny,
          ...cli.packagesDeny,
        },
        toolsDeny: {
          ...file.toolsDeny,
          ...env.toolsDeny,
          ...cli.toolsDeny,
        },
      );

  // ---------------------------------------------------------------------------
  // Apply
  // ---------------------------------------------------------------------------

  /// Filters [tools] according to this config, returning only the tools that
  /// pass all four axes.
  ///
  /// [providerNameLookup] is called once per tool to resolve its contributing
  /// package name. The resolved name is compared case-sensitively against
  /// [packagesAllow] and [packagesDeny].
  ///
  /// ### Evaluation order
  ///
  /// 1. If the tool's package is in [packagesDeny]: exclude (deny wins).
  /// 2. If [packagesAllow] is non-null and the package is NOT in it: exclude.
  /// 3. If the tool's [McpToolDescriptor.name] is in [toolsDeny]: exclude.
  /// 4. If [toolsAllow] is non-null and the name is NOT in it: exclude.
  /// 5. Otherwise: include.
  List<McpToolDescriptor> apply(
    List<McpToolDescriptor> tools,
    String Function(McpToolDescriptor) providerNameLookup,
  ) =>
      tools.where((tool) {
        final provider = providerNameLookup(tool);

        // 1. Package deny wins unconditionally.
        if (packagesDeny.contains(provider)) return false;

        // 2. Package allow-list gating (null = allow all).
        final allow = packagesAllow;
        if (allow != null && !allow.contains(provider)) return false;

        // 3. Tool name deny wins unconditionally.
        if (toolsDeny.contains(tool.name)) return false;

        // 4. Tool name allow-list gating (null = allow all).
        final toolAllow = toolsAllow;
        if (toolAllow != null && !toolAllow.contains(tool.name)) return false;

        return true;
      }).toList();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _readFileOrThrow(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FormatException(
        'McpFilterConfig: file not found at $path.',
      );
    }
    return file.readAsStringSync();
  }

  /// Parses a JSON `allow` field: `null` -> null (allow all), `List` -> Set.
  static Set<String>? _parseJsonAllow(
    Object? value,
    String fieldName,
    String path,
  ) {
    if (value == null) return null;
    if (value is! List) {
      throw FormatException(
        'McpFilterConfig: "$fieldName" must be null or an array in $path.',
      );
    }
    return value.whereType<String>().toSet();
  }

  /// Parses a JSON `deny` field: missing/null -> empty set, `List` -> Set.
  static Set<String> _parseJsonDeny(
    Object? value,
    String fieldName,
    String path,
  ) {
    if (value == null) return const {};
    if (value is! List) {
      throw FormatException(
        'McpFilterConfig: "$fieldName" must be null or an array in $path.',
      );
    }
    return value.whereType<String>().toSet();
  }

  /// Parses a CSV string into a nullable allow set.
  ///
  /// Returns null (allow all) when [raw] is absent or blank. Trims whitespace
  /// around each entry and drops empty entries.
  static Set<String>? _parseCsvAllow(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final entries =
        raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
    return entries.isEmpty ? null : entries;
  }

  /// Parses a CSV string into a deny set.
  ///
  /// Returns an empty set when [raw] is absent or blank.
  static Set<String> _parseCsvDeny(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  /// Converts a nullable CLI list to a nullable allow set.
  ///
  /// Returns null (allow all) when the list is absent or empty.
  static Set<String>? _listToAllow(List<String>? list) {
    if (list == null || list.isEmpty) return null;
    return list.toSet();
  }

  /// Converts a nullable CLI list to a deny set.
  static Set<String> _listToDeny(List<String>? list) {
    if (list == null || list.isEmpty) return const {};
    return list.toSet();
  }
}
