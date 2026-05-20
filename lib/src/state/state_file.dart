import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Atomic JSON read/write for the artisan state file at `~/.artisan/state.json`.
///
/// Written by `artisan start` after a successful `flutter run` spawn; consumed
/// by `stop`, `status`, `logs`, `doctor`, `restart`, and every connected-mode
/// command (dusk:*, telescope:*, tinker) to locate the running app's VM
/// Service WebSocket URI.
///
/// Schema:
/// - `pid` (int, required): the flutter run process PID
/// - `vmServiceUri` (string, required): canonical `ws://host:port/<token>/ws`
/// - `webPort` (int, required): `--web-port` passed to flutter
/// - `vmServicePort` (int, optional, informational, default 8181)
/// - `startedAt` (ISO 8601 UTC string, required)
/// - `profile` (string, required, `debug` | `static`)
/// - `projectRoot` (string, required)
/// - `device` (string, required, `chrome` | `macos` | `linux` | `windows` |
///   device UDID)
/// - `chromePid` (int | null, D6 Chrome capture outcome)
/// - `tmpProfileDir` (string | null, D6 Chrome capture outcome)
/// - `cdpPort` (int | null, --cdp-port value passed to start; null when CDP not enabled)
class StateFile {
  StateFile._();

  /// Test injection seam: overrides the resolved home directory.
  /// Production code never sets this.
  @visibleForTesting
  static String? debugHomeOverride;

  /// Absolute path to the state file.
  static String get path => '${_homePath()}/.artisan/state.json';

  /// Read the state file. Returns null when absent.
  static Future<Map<String, dynamic>?> read() async {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Write atomically via .tmp + rename (no partial-state windows).
  static Future<void> write(Map<String, dynamic> data) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(file.path);
  }

  /// Delete the state file. Idempotent.
  static Future<void> delete() async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  static String _homePath() {
    final override = debugHomeOverride;
    if (override != null) return override;
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
  }
}
