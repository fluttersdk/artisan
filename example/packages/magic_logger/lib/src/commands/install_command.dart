import 'dart:io';
import 'dart:isolate';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;

/// `logger:install` — scaffolds `lib/config/logger.dart` in the host project
/// and prints the one-line `configureMagicLogger()` call the user adds to
/// `lib/main.dart`.
///
/// Demonstrates the third-party plugin install pattern:
///   - StubLoader + custom search path (plugin ships its own stub bundle).
///   - Prompt.confirm + Prompt.choice for interactive defaults.
///   - --force flag for idempotent re-runs.
///   - --non-interactive mode for CI (consume defaults without prompting).
class LoggerInstallCommand extends ArtisanCommand {
  @override
  String get signature => 'logger:install '
      '{--force : Overwrite an existing lib/config/logger.dart} '
      '{--non-interactive : Skip prompts; use defaults} '
      '{--path= : Log file path (interactive default: ~/.magic_logger.log)} '
      '{--level=info : Minimum log level (debug|info|warn|error)}';

  @override
  String get description =>
      'Scaffold magic_logger configuration into the host project.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final root = FileHelper.findProjectRoot();
    final configPath = p.join(root, 'lib', 'config', 'logger.dart');
    final force = ctx.input.option('force') as bool;
    final nonInteractive = ctx.input.option('non-interactive') as bool;
    final overrideLevel = ctx.input.option('level') as String;
    final overridePath = ctx.input.option('path') as String?;

    if (File(configPath).existsSync() && !force) {
      ctx.output.warning(
        'Config exists at $configPath. Re-run with --force to overwrite.',
      );
      return 0;
    }

    // 1. Resolve final values — flags > interactive prompts > defaults.
    final defaultLogPath =
        '${Platform.environment['HOME'] ?? '/tmp'}/.magic_logger.log';
    String logPath;
    String level;
    if (nonInteractive) {
      logPath = overridePath ?? defaultLogPath;
      level = overrideLevel;
    } else {
      logPath = overridePath ??
          Prompt.ask('Log file path?', defaultValue: defaultLogPath);
      level = Prompt.choice(
        'Minimum log level?',
        options: const ['debug', 'info', 'warn', 'error'],
        defaultValue: overrideLevel,
      );
    }

    // 2. Validate level.
    if (!const {'debug', 'info', 'warn', 'error'}.contains(level)) {
      ctx.output.error(
        'Invalid level "$level". Allowed: debug, info, warn, error.',
      );
      return 1;
    }

    // 3. Render stub. Plugin ships its own assets/stubs/ — pass an
    //    explicit search path so StubLoader does not look in the
    //    consumer's tree or the artisan substrate (whose discovery
    //    targets fluttersdk_artisan's own stubs).
    final pluginStubsDir = await _resolvePluginStubsDir();
    final stub = StubLoader.load(
      'install/logger_config.dart',
      searchPaths: <String>[pluginStubsDir],
    );
    final rendered = StubLoader.replace(stub, <String, String>{
      'logFilePath': logPath,
      'minLevel': level,
    });

    // 4. Write.
    FileHelper.writeFile(configPath, rendered);
    ctx.output.success('Created: $configPath');

    // 5. Friendly next-step instructions.
    ctx.output.info('');
    ctx.output.info('Add to lib/main.dart (top of `main()`):');
    ctx.output.writeln('  import \'config/logger.dart\';');
    ctx.output.writeln('  configureMagicLogger();');
    ctx.output.info('');
    ctx.output.info(
      'Then call MagicLogger.info(...), .warn(...), .error(...) anywhere.',
    );
    ctx.output.info('Tail the live log with: artisan logger:tail');

    return 0;
  }

  /// Canonical Dart way to resolve the plugin's filesystem root from any
  /// context: `Isolate.resolvePackageUri('package:magic_logger/cli.dart')`
  /// returns the absolute path of the resolved Dart file, which we walk
  /// back to the package root + assets/stubs/. Works under `dart run`
  /// regardless of cwd, regardless of how the plugin was added (path /
  /// pub.dev / dependency_override).
  Future<String> _resolvePluginStubsDir() async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:magic_logger/cli.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') {
      // Fallback: relative to cwd (works only when invoked from plugin root).
      return p.join(Directory.current.path, 'assets', 'stubs');
    }
    // resolved = <plugin_root>/lib/cli.dart → walk up two levels for plugin root.
    final libCli = resolved.toFilePath();
    final pluginRoot = p.dirname(p.dirname(libCli));
    return p.join(pluginRoot, 'assets', 'stubs');
  }
}
