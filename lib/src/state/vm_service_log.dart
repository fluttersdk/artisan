import 'dart:convert';
import 'dart:io';

/// Matches the two lines a `flutter run` log announces the VM Service on:
/// `Debug service listening on ws://...` (web, via DWDS) and
/// `A Dart VM Service on <device> is available at: http://...` (everything
/// else).
final RegExp vmServiceUriPattern = RegExp(
  r'(?:Debug service listening on|Dart VM Service on .+? is available at:?)'
  r'\s+(\S+)',
);

/// Rewrites a scraped URI into the canonical `ws://host:port/<token>/ws` the
/// VM Service client dials.
String normalizeVmServiceUriString(String raw) {
  String uri = raw;
  if (uri.startsWith('http://')) {
    uri = 'ws://${uri.substring('http://'.length)}';
  } else if (uri.startsWith('https://')) {
    uri = 'wss://${uri.substring('https://'.length)}';
  }
  if (uri.endsWith('/ws')) return uri;
  // A trailing slash after the suffix is the same URI, not a path segment to
  // append to: `.../ws/` must not become `.../ws/ws`.
  if (uri.endsWith('/ws/')) return uri.substring(0, uri.length - 1);
  return uri.endsWith('/') ? '${uri}ws' : '$uri/ws';
}

/// Reads [logFile] once and returns the LAST VM Service URI it announces, or
/// null when the log has none yet.
///
/// Last rather than first: a hot restart re-announces on a new token, and the
/// stale one no longer accepts a connection.
///
/// This is the recovery path for a `start` that was cut short by its caller.
/// The MCP client kills a tool call at 60s and an iOS build routinely takes
/// longer, so the URI can land in the log after the process that was going to
/// record it is already gone. Reading the log turns that into a session the
/// next command can use, instead of one an operator has to hand-write.
String? vmServiceUriFromLog(File logFile) {
  if (!logFile.existsSync()) return null;
  final String contents;
  try {
    contents = logFile.readAsStringSync();
  } on FileSystemException {
    return null;
  }

  String? found;
  for (final String line in const LineSplitter().convert(contents)) {
    final Match? match = vmServiceUriPattern.firstMatch(line);
    if (match != null) found = normalizeVmServiceUriString(match.group(1)!);
  }
  return found;
}
