/// Static hooks populated by host-side integration packages.
///
/// The CLI-side [TinkerCommand] reads these for autocomplete + pretty-printing
/// during the REPL loop. Integration packages (e.g. magic's
/// `MagicTinkerIntegration.install()`) append to these lists in the host app's
/// boot phase under `kDebugMode`.
///
/// Populated values are scoped to a single isolate's lifetime — no cross-
/// isolate sharing. Hot-restart clears them; integrations re-populate on
/// next install().
class Tinker {
  Tinker._();

  /// Autocomplete corpus seeded by integrations. The CLI-side TinkerCommand
  /// merges this with runtime `vmService.getClassList()` results (lazy cache).
  static final List<String> autocompleteCorpus = <String>[];

  /// Short-name → full-import-path map (Laravel's ClassAliasAutoloader analog).
  /// Magic populates with project facade shortcuts.
  static final Map<String, String> classAliases = <String, String>{};

  /// Pretty-printers for REPL output (Laravel's TinkerCaster analog).
  /// The first caster returning a non-null string wins.
  static final List<TinkerCaster> casters = <TinkerCaster>[];
}

/// Returns a formatted string representation of [value], or null to defer to
/// the next caster in the chain.
typedef TinkerCaster = String? Function(Object? value);
