/// POSIX shell-quoting for arguments passed to `sh -c '...'`.
///
/// Each token in [tokens] is left bare when it matches the safe-character
/// bareword pattern (alphanumerics + `_./=:-`); otherwise it is wrapped in
/// single quotes with embedded single quotes escaped via the canonical
/// `'\''` close-reopen pattern.
///
/// Result is joined with single spaces — suitable to be inlined into a
/// `sh -c` payload as a single shell word sequence.
///
/// Used by `StartCommand` to safely interpolate file paths and flutter
/// arguments into the wrapper script. Public so tests can exercise the
/// quoting contract without spawning a real shell.
String shellQuoteTokens(List<String> tokens) {
  return tokens.map((t) {
    if (_bareword.hasMatch(t)) return t;
    return "'${t.replaceAll("'", r"'\''")}'";
  }).join(' ');
}

final RegExp _bareword = RegExp(r'^[A-Za-z0-9_./=:-]+$');
