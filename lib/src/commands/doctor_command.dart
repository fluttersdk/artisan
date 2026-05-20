import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';

/// Advisory warning emitted when `.mcp.json` still references the removed
/// `fluttersdk_mcp` package. Instructs the user to run `mcp:install` to fix.
const _staleMcpWarning =
    'WARN: Stale MCP entry detected. Pre-upgrade .mcp.json points at the '
    'removed fluttersdk_mcp package. Run: dart run fluttersdk_artisan:artisan '
    'mcp:install';

/// Minimum Flutter SDK version required for the WebSocket hot reload fix that
/// enables CDP commands (flutter/flutter#170612).
const _minSdkVersion = '3.30.0';

/// Advisory warning emitted when the detected Flutter SDK is older than
/// [_minSdkVersion]. Instructs the user to run `flutter upgrade`.
const _cdpUpgradeWarning =
    'WARN: Flutter SDK is older than $_minSdkVersion. CDP commands '
    '(dusk:resize, dusk:device, artisan start --cdp-port) require the '
    'WebSocket hot reload fix from flutter/flutter#170612. '
    'Run `flutter upgrade` and re-check.';

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

  /// Test seam: swap this to inject a fake [ProcessResult] in unit tests.
  ///
  /// Production code keeps the default ([Process.run]). Tests replace it with
  /// a closure that returns a pre-built [ProcessResult] without spawning a
  /// real process.
  @visibleForTesting
  static Future<ProcessResult> Function(String, List<String>)
      doctorFlutterRunner = Process.run;

  /// Exposes [_cdpUpgradeWarning] for assertion in unit tests.
  @visibleForTesting
  static String get cdpUpgradeWarningForTest => _cdpUpgradeWarning;

  /// Exposes [_checkFlutterSdkVersion] for direct invocation in unit tests.
  @visibleForTesting
  static Future<bool> checkFlutterSdkVersionForTest() =>
      _checkFlutterSdkVersion();

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Run hard preflight checks.
    final checks = <_Check>[
      _Check('flutter --version', _checkFlutter),
      _Check('dart --version', _checkDart),
      _Check('port 3100 free', _checkPort3100),
      _Check('flutter sdk >= $_minSdkVersion (for --cdp-port)',
          _checkFlutterSdkVersion),
    ];
    var allPass = true;
    for (final c in checks) {
      final pass = await c.run();
      if (!pass) allPass = false;
      ctx.output.writeln('  ${pass ? '✓' : '✗'} ${c.label}');
    }

    // 2. Advisory: warn if .mcp.json still targets the removed fluttersdk_mcp.
    _checkStaleMcpJson(_workingDir ?? Directory.current.path, ctx);

    // 3. Advisory: warn when Flutter SDK is too old for CDP commands.
    await _checkCdpReadiness(ctx);

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

  /// Emits [_cdpUpgradeWarning] to [ctx] when [_checkFlutterSdkVersion]
  /// returns false. Advisory only; never influences the exit code.
  static Future<void> _checkCdpReadiness(ArtisanContext ctx) async {
    final sdkOk = await _checkFlutterSdkVersion();
    if (!sdkOk) {
      ctx.output.writeln(_cdpUpgradeWarning);
    }
  }

  /// Returns true when the installed Flutter SDK is at or above
  /// [_minSdkVersion], false otherwise.
  ///
  /// Runs `flutter --version --machine` and parses `frameworkVersion` from the
  /// JSON output. On parse failure or when `flutter` is not found, returns
  /// false so the check label surfaces the issue to the user.
  static Future<bool> _checkFlutterSdkVersion() async {
    try {
      final r = await doctorFlutterRunner(
          'flutter', <String>['--version', '--machine']);
      if (r.exitCode != 0) return false;

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      } catch (_) {
        return false;
      }

      final version = json['frameworkVersion'];
      if (version is! String) return false;

      return _isSdkVersionSufficient(version, _minSdkVersion);
    } catch (_) {
      return false;
    }
  }

  /// Compares two three-segment semver strings (e.g. "3.30.0") numerically.
  ///
  /// Returns true when [detected] is greater than or equal to [minimum].
  /// Malformed version strings (fewer than 3 segments or non-numeric segments)
  /// return false.
  static bool _isSdkVersionSufficient(String detected, String minimum) {
    final detectedParts = _parseVersion(detected);
    final minimumParts = _parseVersion(minimum);
    if (detectedParts == null || minimumParts == null) return false;

    for (var i = 0; i < 3; i++) {
      if (detectedParts[i] > minimumParts[i]) return true;
      if (detectedParts[i] < minimumParts[i]) return false;
    }
    return true; // equal
  }

  /// Parses a three-segment semver string into an integer list, or returns
  /// null when the string does not conform to `major.minor.patch`.
  static List<int>? _parseVersion(String version) {
    final parts = version.split('.');
    if (parts.length != 3) return null;
    final segments = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null) return null;
      segments.add(n);
    }
    return segments;
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
