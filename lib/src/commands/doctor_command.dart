import 'dart:convert';
import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';

/// Advisory warning emitted when `.mcp.json` still references the removed
/// `fluttersdk_mcp` package. Instructs the user to run `mcp:install` to fix.
const _staleMcpWarning =
    'WARN: Stale MCP entry detected. Pre-upgrade .mcp.json points at the '
    'removed fluttersdk_mcp package. Run: dart run fluttersdk_artisan:artisan '
    'mcp:install';

/// Runs environment preflight checks (artisan toolchain).
class DoctorCommand extends ArtisanCommand {
  /// Creates a [DoctorCommand].
  ///
  /// [workingDir] pins the directory used for `.mcp.json` detection. Defaults
  /// to [Directory.current.path] when omitted. Inject a temp directory in
  /// tests to avoid depending on the real working directory.
  DoctorCommand({String? workingDir}) : _workingDir = workingDir;

  /// Pinned working directory for `.mcp.json` lookup.
  ///
  /// `null` means "use [Directory.current.path] at call time", which is the
  /// correct production behaviour (the cwd may change between construction and
  /// [handle]).
  final String? _workingDir;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Run environment preflight checks (flutter, dart, port availability).';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Run hard preflight checks.
    final checks = <_Check>[
      _Check('flutter --version', _checkFlutter),
      _Check('dart --version', _checkDart),
      _Check('port 3100 free', _checkPort3100),
    ];
    var allPass = true;
    for (final c in checks) {
      final pass = await c.run();
      if (!pass) allPass = false;
      ctx.output.writeln('  ${pass ? '✓' : '✗'} ${c.label}');
    }

    // 2. Advisory: warn if .mcp.json still targets the removed fluttersdk_mcp.
    _checkStaleMcpJson(_workingDir ?? Directory.current.path, ctx);

    return allPass ? 0 : 1;
  }

  /// Checks whether `.mcp.json` in [dir] contains a `fluttersdk_mcp:server`
  /// reference in any `mcpServers` entry args list. Emits [_staleMcpWarning]
  /// to [ctx] when found. Does nothing when the file is absent or cannot be
  /// parsed. This is advisory only and never influences the exit code.
  static void _checkStaleMcpJson(String dir, ArtisanContext ctx) {
    final file = File('$dir/.mcp.json');
    if (!file.existsSync()) return;

    final Map<String, dynamic> root;
    try {
      root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      // Malformed JSON: skip silently; not our job to validate the schema.
      return;
    }

    final servers = root['mcpServers'];
    if (servers is! Map<String, dynamic>) return;

    for (final entry in servers.values) {
      if (entry is! Map<String, dynamic>) continue;
      final args = entry['args'];
      if (args is! List<dynamic>) continue;
      if (args.contains('fluttersdk_mcp:server')) {
        ctx.output.writeln(_staleMcpWarning);
        return;
      }
    }
  }

  static Future<bool> _checkFlutter() async {
    try {
      final r = await Process.run('flutter', <String>['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkDart() async {
    try {
      final r = await Process.run('dart', <String>['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkPort3100() async {
    if (Platform.isWindows) return true; // skip for V1
    try {
      final r = await Process.run('lsof', <String>['-ti', 'tcp:3100']);
      return r.exitCode != 0 || (r.stdout as String).trim().isEmpty;
    } catch (_) {
      return true;
    }
  }
}

class _Check {
  _Check(this.label, this.run);
  final String label;
  final Future<bool> Function() run;
}
