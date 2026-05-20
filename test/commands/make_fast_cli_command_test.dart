import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:fluttersdk_artisan/src/commands/make_fast_cli_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Records every [Process.run]-style invocation and returns scripted results.
///
/// The [scripted] map keys are `'<exe> <args joined by space>'` so tests can
/// provide per-command exit codes and output without spinning up real processes.
class _RecordingRunner {
  _RecordingRunner(this.scripted);

  final Map<String, ProcessResult> scripted;
  final List<List<String>> calls = [];

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add([exe, ...args]);
    return scripted['$exe ${args.join(' ')}'] ?? ProcessResult(0, 0, '', '');
  }
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Builds a fake consumer project tree under [root] with the four files
/// `make:fast-cli` validates before doing any work: pubspec.yaml, pubspec.lock,
/// .dart_tool/package_config.json, and bin/dispatcher.dart wrapper.
///
/// Copied inline from plugin_install_command_test.dart:20-54 per the
/// extract-when-third-caller rule in .claude/rules/tests.md.
void _seedConsumerProject(
  Directory root, {
  required String pluginName,
  String? wrapper,
}) {
  // 1. pubspec.yaml — plugin listed under dependencies.
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: consumer\n'
    'dependencies:\n'
    '  $pluginName: ^1.0.0\n',
  );

  // 2. pubspec.lock — required for SHA256 stamp computation.
  File(p.join(root.path, 'pubspec.lock')).writeAsStringSync(
    'packages:\n'
    '  $pluginName:\n'
    '    version: "1.0.0"\n',
  );

  // 3. .dart_tool/package_config.json — plugin resolvable.
  final pkgConfigDir = Directory(p.join(root.path, '.dart_tool'))
    ..createSync(recursive: true);
  File(p.join(pkgConfigDir.path, 'package_config.json')).writeAsStringSync(
    '{"packages":[{"name": "$pluginName"}]}\n',
  );

  // 4. bin/dispatcher.dart — canonical wrapper with auto.commands anchor.
  final binDir = Directory(p.join(root.path, 'bin'))
    ..createSync(recursive: true);
  File(p.join(binDir.path, 'dispatcher.dart')).writeAsStringSync(
    wrapper ??
        "import 'package:fluttersdk_artisan/artisan.dart';\n\n"
            "Future<void> main(List<String> args) async {\n"
            "  final registry = ArtisanRegistry();\n"
            "  final auto = await loadAutoIndex();\n"
            "  registry.registerAll(auto.commands, providerName: 'app');\n"
            "  final app = ArtisanApplication(registry);\n"
            "  await app.run(args);\n"
            "}\n",
  );
}

/// Builds an [ArtisanContext] backed by a [BufferedOutput] for output assertions.
ArtisanContext _ctx() {
  return ArtisanContext.bare(
    MapInput(const <String, dynamic>{}),
    BufferedOutput(),
  );
}

/// Builds scripted results for the happy path: chmod succeeds, dart --version
/// returns a semver, dart build cli succeeds.
Map<String, ProcessResult> _happyScripted(String root) => {
      'chmod +x ${p.join(root, 'bin', 'fsa')}': ProcessResult(0, 0, '', ''),
      'dart --version':
          ProcessResult(0, 0, '', 'Dart SDK version: 3.8.0 (stable) ...'),
      'dart build cli -t bin/dispatcher.dart -o .artisan/cli-bundle':
          ProcessResult(0, 0, 'Build complete.', ''),
    };

void main() {
  late Directory tempDir;
  late _RecordingRunner runner;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mkfci_');
    _seedConsumerProject(tempDir, pluginName: 'consumer_demo');
    runner = _RecordingRunner(_happyScripted(tempDir.path));
    MakeFastCliCommand.processRunner = runner.call;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    MakeFastCliCommand.processRunner = Process.run;
  });

  // -------------------------------------------------------------------------
  // Test 1 — metadata
  // -------------------------------------------------------------------------
  test('metadata: name, description, boot', () {
    final cmd = MakeFastCliCommand();

    expect(cmd.name, 'make:fast-cli');
    expect(cmd.description, isNotEmpty);
    expect(cmd.boot, CommandBoot.none);
  });

  // -------------------------------------------------------------------------
  // Test 2 — writes bin/fsa with correct content
  // -------------------------------------------------------------------------
  test('writes bin/fsa with correct shell script content', () async {
    final ctx = _ctx();
    final result = await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: ctx,
    );

    expect(result, 0);

    final fsaFile = File(p.join(tempDir.path, 'bin', 'fsa'));
    expect(fsaFile.existsSync(), isTrue);

    final content = fsaFile.readAsStringSync();
    expect(content, contains('follow_links'));
    expect(content, contains('dart build cli'));
    expect(content, contains('mkdir'));
    expect(content, contains('LOCK_DIR'));
  });

  // -------------------------------------------------------------------------
  // Test 3 — chmod called on bin/fsa
  // -------------------------------------------------------------------------
  test('chmod +x is called on bin/fsa', () async {
    await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: _ctx(),
    );

    final binFsaPath = p.join(tempDir.path, 'bin', 'fsa');
    expect(
      runner.calls,
      anyElement(equals(['chmod', '+x', binFsaPath])),
    );
  });

  // -------------------------------------------------------------------------
  // Test 4 — .gitignore patched (idempotent: exactly ONE .artisan/ line)
  // -------------------------------------------------------------------------
  test('.gitignore is patched with .artisan/ exactly once (idempotent)',
      () async {
    // First run.
    await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: _ctx(),
    );

    // Second run with a fresh runner (separate instance).
    final runner2 = _RecordingRunner(_happyScripted(tempDir.path));
    MakeFastCliCommand.processRunner = runner2.call;

    await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: _ctx(),
    );

    final gitignore = File(p.join(tempDir.path, '.gitignore'));
    expect(gitignore.existsSync(), isTrue);

    final content = gitignore.readAsStringSync();
    expect(content, contains('.artisan/'));
    expect(RegExp('.artisan/').allMatches(content).length, 1);
  });

  // -------------------------------------------------------------------------
  // Test 5 — dart build cli invoked with correct args
  // -------------------------------------------------------------------------
  test('dart build cli is invoked with correct args', () async {
    await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: _ctx(),
    );

    expect(
      runner.calls,
      anyElement(
        equals([
          'dart',
          'build',
          'cli',
          '-t',
          'bin/dispatcher.dart',
          '-o',
          '.artisan/cli-bundle',
        ]),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // Test 6 — stamp file written with correct format
  // -------------------------------------------------------------------------
  test('stamp file written with <sha256>:<semver> format', () async {
    await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: _ctx(),
    );

    final stamp = File(p.join(tempDir.path, '.artisan', 'build.stamp'));
    expect(stamp.existsSync(), isTrue);

    final content = stamp.readAsStringSync().trim();
    // Format: 64 hex chars : semver
    expect(content, matches(RegExp(r'^[a-f0-9]{64}:[0-9]+\.[0-9]+')));
  });

  // -------------------------------------------------------------------------
  // Test 7 — idempotency: second run with force=false skips bin/fsa
  // -------------------------------------------------------------------------
  test('second run with force=false skips bin/fsa and does not re-invoke build',
      () async {
    // First run: creates bin/fsa.
    await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: _ctx(),
    );

    // Second run with a fresh runner, force=false.
    final runner2 = _RecordingRunner(_happyScripted(tempDir.path));
    MakeFastCliCommand.processRunner = runner2.call;
    final output2 = BufferedOutput();
    final ctx2 = ArtisanContext.bare(MapInput(const {}), output2);

    final result2 = await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: ctx2,
    );

    expect(result2, 0);
    expect(output2.content, contains('Skipped'));

    // chmod should NOT be called again (bin/fsa was not rewritten).
    final chmodCalls = runner2.calls.where((c) => c.first == 'chmod').toList();
    expect(chmodCalls, isEmpty);

    // dart build cli should NOT be re-invoked (stamp still valid on second run).
    final buildCalls = runner2.calls
        .where((c) => c.length >= 3 && c[0] == 'dart' && c[1] == 'build')
        .toList();
    expect(buildCalls, isEmpty);
  });

  // -------------------------------------------------------------------------
  // Test 8 — force: second run with force=true rewrites bin/fsa + re-chmods
  // -------------------------------------------------------------------------
  test('second run with force=true rewrites bin/fsa and calls chmod again',
      () async {
    // First run.
    await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: false,
      ctx: _ctx(),
    );

    // Second run with a fresh runner, force=true.
    final runner2 = _RecordingRunner(_happyScripted(tempDir.path));
    MakeFastCliCommand.processRunner = runner2.call;

    final result2 = await MakeFastCliCommand.scaffoldInto(
      root: tempDir.path,
      force: true,
      ctx: _ctx(),
    );

    expect(result2, 0);

    // chmod must be called again because bin/fsa was rewritten.
    final binFsaPath = p.join(tempDir.path, 'bin', 'fsa');
    expect(runner2.calls, anyElement(equals(['chmod', '+x', binFsaPath])));
  });
}
