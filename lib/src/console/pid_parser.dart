/// Parses `<TAG>=<int>` lines emitted by the start wrapper script into a
/// map keyed by tag. Unknown lines are skipped; malformed entries (tag
/// matches but value is not an integer) are also skipped silently — the
/// caller decides whether missing entries are fatal.
///
/// The recognised tags are `HOLDER` (the `tail -f /dev/null` background
/// process that keeps the FIFO write end open) and `FLUTTER` (the
/// `nohup flutter run` PID). Any other tag is dropped.
///
/// Used by `StartCommand._scrapeTwoPids`. Public so tests can verify the
/// parser contract without spawning a real subprocess.
Map<String, int> parsePidLines(Iterable<String> lines) {
  final out = <String, int>{};
  for (final line in lines) {
    final match = _pattern.firstMatch(line.trim());
    if (match == null) continue;
    final value = int.tryParse(match.group(2)!);
    if (value == null) continue;
    out[match.group(1)!] = value;
  }
  return out;
}

final RegExp _pattern = RegExp(r'^(HOLDER|FLUTTER)=(\d+)$');
