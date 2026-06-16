# make:fast-cli

Scaffold a POSIX shell wrapper (`bin/fsa`) and AOT-compiled artisan binary for ~50ms startup, avoiding the 3-second `dart run` overhead with build hooks.

---

## Table of contents

- [Basic Usage](#basic-usage)
- [Synopsis](#synopsis)
- [What It Does](#what-it-does)
- [Output](#output)
- [Re-running](#re-running)
- [Performance](#performance)
- [Caveats](#caveats)
- [Related](#related)

---

## Basic Usage

```bash
dart run fluttersdk_artisan make:fast-cli
```

Writes four files and directories: `bin/fsa` (POSIX shell wrapper, executable), `.artisan/cli-bundle/` (compiled binary + runtime libraries), `.artisan/build.stamp` (staleness marker), and patches `.gitignore` to ignore the cache. Caches the build result so subsequent invocations are cached (real time under 100ms on hit).

---

## Synopsis

```
make:fast-cli {--force : Overwrite bin/fsa even when it already exists}
```

| Option | Description |
|---|---|
| `--force` | Rewrite `bin/fsa` and recompile the binary, even if a cached version exists. |

---

## What It Does

1. **Validates the project structure.** Checks for `pubspec.yaml` and `bin/dispatcher.dart`; errors with actionable guidance if either is missing.

2. **Scaffolds the wrapper script.** Writes a POSIX `sh` script at `bin/fsa` that resolves symlinks via a portable `follow_links()` subshell and derives the project root at runtime.

3. **Computes a staleness key.** Captures the SHA256 hash of `pubspec.lock` and the Dart SDK version string, storing both in `.artisan/build.stamp` for later comparison.

4. **Compiles the binary.** Runs `dart build cli -t bin/dispatcher.dart -o .artisan/cli-bundle`, producing an AOT-native binary at `.artisan/cli-bundle/bundle/bin/dispatcher`.

5. **Patches `.gitignore`.** Appends `.artisan/` if not already present, ensuring the compiled cache is excluded from version control and never tracked. Idempotent.

---

## Output

- **`bin/fsa`** (executable, ~50 LoC): shell wrapper that checks staleness, auto-recompiles if needed, then execs into the binary.
- **`.artisan/cli-bundle/bundle/bin/dispatcher`**: AOT-compiled native executable.
- **`.artisan/cli-bundle/bundle/lib/*.dylib`** (on macOS; `.so` on Linux): runtime libraries bundled with the binary.
- **`.artisan/build.stamp`**: one-line file with `<pubspec_lock_sha256>:<dart_sdk_version>`. Lets the wrapper detect when to rebuild.

---

## Re-running

Run `make:fast-cli` again without `--force`: the wrapper detects `bin/fsa` already exists and skips the override.

Run with `--force`: rewrites the wrapper and recompiles.

The wrapper script itself is the source of truth for staleness detection. When the user runs `./bin/fsa <cmd>` and the Dart SDK updates or `pubspec.lock` changes, the wrapper notices (inside the lock-acquire section) and transparently rebuilds. No manual re-run needed.

---

## Staleness Detection

The wrapper's `needs_build()` function triggers a rebuild when any of these conditions hold:

1. **Binary missing.** The compiled executable at `.artisan/cli-bundle/bundle/bin/dispatcher` does not exist.

2. **Stamp file missing or empty.** The `.artisan/build.stamp` file is absent or has zero size.

3. **Stamp file content mismatches.** The stored compile key (format: `<sha256-of-pubspec.lock>:<dart-sdk-version>`) differs from the current key, meaning either the lock or the SDK changed.

4. **`pubspec.yaml` modified since last build.** The mtime of `pubspec.yaml` is newer than the stamp file's mtime, detected via the `-nt` (newer than) operator.

5. **`lib/app/_plugins.g.dart` modified since last build.** The mtime of `lib/app/_plugins.g.dart` is newer than the stamp file's mtime. This condition was added in 0.0.5 to invalidate the cache when `plugin:install` or `plugins:refresh` regenerates the file (issue #9 GAP A).

Any match triggers a recompile inside the lock-acquire section. The re-check inside the lock prevents redundant builds when multiple invocations race.

---

## Performance

### Cache hit (wrapper runs existing binary)

```bash
time ./bin/fsa status
# real 0m0.045s
# user 0m0.020s
# sys  0m0.015s
```

~50ms round-trip on a modern machine (no `dart run`, no "Running build hooks..." overhead).

### Cache miss (first run or staleness detected)

```bash
time dart run fluttersdk_artisan make:fast-cli
# Building artisan CLI (one-time, ~5s)...
# real 0m8.234s
```

~8 seconds (depends on machine and dependency size). The wrapper prints "Building artisan CLI..." so users know a compile is in progress and not to interrupt.

### Comparison with `dart run`

```bash
time dart run fluttersdk_artisan status
# real 0m3.100s
# (includes "Running build hooks..." unless all hooks are cached)

time ./bin/fsa status
# real 0m0.045s
# (cached; 68x faster)
```

---

## Caveats

**V1 POSIX-only (macOS + Linux).** Windows users continue to use `dart run fluttersdk_artisan <cmd>`. A `.cmd` variant is deferred to V1.x.

**Requires Dart 3.5 or later.** The command uses `dart build cli`, which requires Dart 3.5+ because transitive dependencies may declare `hook/build.dart` via pub-provided build hooks. Earlier SDK versions fail with "dart compile does not support build hooks."

**No cross-compilation.** The compiled binary targets the local machine architecture and OS. Distributing the binary to a different architecture or OS requires re-running `make:fast-cli` on that target.

---

## Related

- [make:command](index.md): scaffold a single `ArtisanCommand` subclass.
- [make:plugin](make-plugin): scaffold a full plugin package.
- [install](install): initialize an artisan consumer project structure.
