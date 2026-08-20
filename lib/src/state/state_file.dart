import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Atomic JSON read/write for the artisan state file.
///
/// The file is PER PROJECT: `~/.artisan/sessions/<hash>/state.json`, keyed by
/// the project root. It used to be one global `~/.artisan/state.json`, which
/// meant a second project's `artisan start` silently took the slot and every
/// connected command from the first project then drove the second app,
/// succeeding each time. The measured case had a worktree in another
/// repository rewrite it mid-session, and two commands later produced a
/// screenshot of an entirely different product.
///
/// `~/.artisan/state.json` is still written, as a pointer to whichever
/// session started last. That is an interop contract rather than a shim:
/// the documented recovery recipe when `artisan start` cannot boot an app
/// is to hand-write that file, and external tooling reads it.
///
/// Written by `artisan start` after a successful `flutter run` spawn; consumed
/// by `stop`, `status`, `logs`, `doctor`, `restart`, and every connected-mode
/// command (dusk:*, telescope:*, tinker) to locate the running app's VM
/// Service WebSocket URI.
///
/// Schema:
/// - `pid` (int, required): the flutter run process PID
/// - `stdinPipe` (string, required): path to the FIFO `flutter run`'s stdin
///   reads from. `reload` and `hot-restart` write `r` / `R` into it, so a
///   hand-written state without this key cannot hot restart
/// - `stdinHolderPid` (int, required): PID of the process holding the FIFO
///   open for writing, reaped by `stop`
/// - `booting` (bool, optional): present and true only between the spawn and
///   the VM Service URI landing. A caller that gave up in that window left
///   the app running, and this says the record is incomplete rather than
///   wrong
/// - `vmServiceUri` (string, null while `booting`): canonical
///   `ws://host:port/<token>/ws`
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

  /// Test injection seam: overrides the resolved project root.
  @visibleForTesting
  static String? debugProjectRootOverride;

  /// Explicit path override, set from `--state=<path>`. Null means "resolve
  /// from the project root", subject to [explicitPath].
  static String? pathOverride;

  /// The session the caller NAMED, by flag or by environment, or null when
  /// they named none.
  ///
  /// The ownership check reads this rather than [pathOverride] alone. Both
  /// spellings are documented as equivalent and [path] honours both, so a
  /// guard that saw only the flag refused to drive the very session
  /// `ARTISAN_STATE_FILE` had just pointed it at.
  static String? explicitPath() {
    final String? flag = pathOverride;
    if (flag != null && flag.isNotEmpty) return flag;
    final String? env = _envPathOverride();
    return (env != null && env.isNotEmpty) ? env : null;
  }

  /// The single global file every version before session isolation used.
  static String get legacyPointerPath => '${_homePath()}/.artisan/state.json';

  /// Absolute path to the state file this process reads and writes.
  ///
  /// Resolution order: the explicit [pathOverride] (`--state=<path>` or
  /// `ARTISAN_STATE_FILE`), then the per-project session file.
  static String get path {
    final String? override = explicitPath();
    if (override != null) return override;
    return sessionPathFor(_projectRoot());
  }

  /// The session file for [projectRoot].
  ///
  /// A DIRECTORY per session, not just a file: the log and the FIFO are
  /// derived from the state file's parent in a single hop, and they collide
  /// between two running apps for exactly the same reason the state file
  /// did. Putting all three under one per-project directory fixes the set
  /// rather than one member of it.
  ///
  /// Keyed by a truncated SHA-256 of the root rather than a slugified path:
  /// a project path can contain separators, spaces and non-ASCII, and a
  /// digest sidesteps every one of those without a sanitiser to get wrong.
  /// Twelve hex characters is 48 bits, which is far more than enough for the
  /// handful of projects one developer drives at once.
  static String sessionPathFor(String projectRoot) =>
      '${sessionDirFor(projectRoot)}/state.json';

  /// The directory holding one session's state, log and FIFO.
  static String sessionDirFor(String projectRoot) {
    final String key = _canonicalPath(projectRoot);
    final String digest =
        sha256.convert(utf8.encode(key)).toString().substring(0, 12);
    return '${_homePath()}/.artisan/sessions/$digest';
  }

  /// The directory every artisan artifact lives under, session or not.
  static String get homeDir => '${_homePath()}/.artisan';

  static String? _envPathOverride() =>
      Platform.environment['ARTISAN_STATE_FILE'];

  static String _projectRoot() =>
      projectRootFor(debugProjectRootOverride ?? Directory.current.path);

  /// The package root [from] belongs to: the nearest ancestor holding a
  /// `pubspec.yaml`, or [from] itself when there is none.
  ///
  /// The session key has to be the PROJECT, not the working directory.
  /// `sessionOwnershipError` blesses running from `backend/` or a package
  /// subdirectory, but keying the file on the cwd meant a command from there
  /// missed its own session, fell back to the shared pointer, and with two
  /// apps up got refused for driving somebody else's. The isolation only
  /// held for callers standing in the repo root.
  ///
  /// The walk stops at the NEAREST pubspec rather than the outermost,
  /// because that is the unit `artisan start` boots: two packages in one
  /// repository are two apps and want two sessions.
  ///
  /// No pubspec anywhere up the chain falls back to [from]. Climbing to the
  /// filesystem root instead would land every such caller in one shared
  /// session, which is the failure this whole file exists to remove.
  static String projectRootFor(String from) {
    Directory dir = Directory(from);
    while (true) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
      final Directory parent = dir.parent;
      if (parent.path == dir.path) return from;
      dir = parent;
    }
  }

  /// Read the state for this project. Returns null when absent.
  ///
  /// Falls back to the legacy pointer when no session file exists, so an app
  /// started by an older artisan, or a hand-written `~/.artisan/state.json`
  /// from the documented recovery recipe, still resolves.
  static Future<Map<String, dynamic>?> read() async {
    return await _readFile(path) ?? await _readFile(legacyPointerPath);
  }

  static Future<Map<String, dynamic>?> _readFile(String at) async {
    final file = File(at);
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Write atomically via .tmp + rename (no partial-state windows).
  ///
  /// Writes the session file, then mirrors to the legacy pointer so the
  /// most recently started app stays reachable through the path external
  /// tooling and the hand-written recovery recipe both use.
  static Future<void> write(Map<String, dynamic> data) async {
    await _writeFile(path, data);
    if (path != legacyPointerPath) {
      await _writeFile(legacyPointerPath, data);
    }
  }

  static Future<void> _writeFile(String at, Map<String, dynamic> data) async {
    final file = File(at);
    await file.parent.create(recursive: true);
    // The temp name carries the pid because the legacy pointer is SHARED:
    // two projects starting at once both staged `state.json.tmp`, and the
    // loser's rename threw after `flutter run` had already been spawned,
    // orphaning the process with no state file to find it by.
    final tmp = File('${file.path}.$pid.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(file.path);
  }

  /// Delete this project's state. Idempotent.
  ///
  /// The legacy pointer goes too, but only while it still describes THIS
  /// project. A sibling that started later owns it by then, and taking it
  /// away would break the connected commands of an app that is still
  /// running.
  static Future<void> delete() async {
    final String sessionPath = path;
    final Map<String, dynamic>? mine = await _readFile(sessionPath);

    final file = File(sessionPath);
    if (file.existsSync()) await file.delete();

    if (sessionPath == legacyPointerPath) return;
    final File pointer = File(legacyPointerPath);
    if (!pointer.existsSync()) return;

    final Map<String, dynamic>? pointed = await _readFile(legacyPointerPath);
    final Object? pointedRoot = pointed?['projectRoot'];
    // A pointer with no recorded root is the hand-written recovery file the
    // read path goes out of its way to honour. Deleting it here took away
    // the escape hatch people reach for precisely when `start` has already
    // failed them, so an unattributed pointer is left alone.
    if (pointedRoot is! String || pointedRoot.isEmpty) return;

    // IS-WITHIN, matching sessionOwnershipError: a `stop` run from a
    // subdirectory has no session file of its own, so `mine` is null and
    // the fallback root is that subdirectory. Comparing exactly left the
    // pointer behind, still advertising a session that had just been
    // stopped.
    final String myRoot = (mine?['projectRoot'] as String?) ?? _projectRoot();
    if (_isWithin(myRoot, pointedRoot)) {
      await pointer.delete();
    }
  }

  static String _homePath() {
    final override = debugHomeOverride;
    if (override != null) return override;
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
  }
}

/// Reports why [state] must not be driven from [workingDirectory], or null
/// when it is safe.
///
/// Per-project session files stop two apps from sharing a slot, but the
/// legacy pointer is still read when this project has no session of its own,
/// and it describes whichever app started last. Without this check a command
/// run from project A while only project B is up connects to B and succeeds,
/// which is the failure that once produced a screenshot of an entirely
/// different product with every command reporting a clean exit.
///
/// Three cases pass deliberately:
///
/// - A working directory INSIDE the project. Running from `backend/` or a
///   package subdirectory is normal.
/// - State with no recorded `projectRoot`. Hand-written state from the
///   documented recovery recipe often omits it, and refusing there would
///   break the escape hatch people reach for precisely when `artisan start`
///   has already failed them.
/// - An explicit [explicitStatePath]. The caller named the session, so they
///   have already answered the question this check asks.
String? sessionOwnershipError({
  required Map<String, dynamic> state,
  required String workingDirectory,
  String? explicitStatePath,
}) {
  if (explicitStatePath != null && explicitStatePath.isNotEmpty) return null;

  final Object? recorded = state['projectRoot'];
  if (recorded is! String || recorded.isEmpty) return null;

  if (_isWithin(workingDirectory, recorded)) return null;

  return 'The running app belongs to another project ($recorded), not this '
      'one ($workingDirectory). `~/.artisan/state.json` is a shared pointer '
      'to whichever app started last, so driving it from here would act on '
      'that app and report success. Run `artisan start` for this project, '
      'or pass --state=<path> to name the session you mean.';
}

/// True when [child] is [parent] or sits beneath it, comparing resolved
/// paths so a symlinked worktree checkout does not read as a mismatch.
bool _isWithin(String child, String parent) {
  final String c = _canonicalPath(child);
  final String p = _canonicalPath(parent);
  return c == p || c.startsWith('$p${Platform.pathSeparator}');
}

/// Normalises a path for comparison and for hashing.
///
/// A trailing separator and a symlinked path (a git worktree checkout is
/// often one) must resolve to the same string, otherwise one project gets
/// two session directories and the ownership check reads its own session as
/// somebody else's.
String _canonicalPath(String raw) {
  final String trimmed = raw.endsWith(Platform.pathSeparator) && raw.length > 1
      ? raw.substring(0, raw.length - 1)
      : raw;
  final Directory dir = Directory(trimmed);
  return dir.existsSync() ? dir.resolveSymbolicLinksSync() : trimmed;
}
