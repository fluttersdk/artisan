import 'dart:io';

import 'package:path/path.dart' as p;

import '../console/artisan_context.dart';
import '../console/artisan_generator_command.dart';
import '../console/string_helper.dart';
import '../helpers/file_helper.dart';
import 'commands_index_writer.dart';

/// `artisan make:command MyCommand` — scaffolds a new ArtisanCommand subclass
/// under `lib/app/commands/` and refreshes the auto-discovery index so the
/// new command shows up on the next `artisan list` without manual wiring.
///
/// Default command name derivation (Laravel convention):
///   - `SyncMonitors` → `sync-monitors`
///   - `Admin/UserSync` → `admin:user-sync`
///
/// The generated stub uses the Laravel-style signature DSL so users can
/// add positional args + flags + options by editing the signature string
/// instead of calling `parser.addOption(...)` manually.
class MakeCommandCommand extends ArtisanGeneratorCommand {
  @override
  String get name => 'make:command';

  @override
  String get description =>
      'Scaffold a new ArtisanCommand subclass under lib/app/commands/.';

  @override
  String getStub() => 'artisan_command';

  @override
  String getDefaultNamespace() => 'lib/app/commands';

  @override
  Map<String, String> getReplacements(String name) {
    final parsed = StringHelper.parseName(name);
    final kebab = _toKebabCase(parsed.className);
    final namespacePrefix = parsed.directory.isEmpty
        ? ''
        : '${parsed.directory.replaceAll('/', ':')}:';
    return <String, String>{
      '{{ commandName }}': '$namespacePrefix$kebab',
    };
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final code = await super.handle(ctx);
    if (code != 0) return code;
    // Auto-refresh the index so the consumer's bin/artisan.dart picks the
    // new command up without an extra `commands:refresh` invocation.
    final root = FileHelper.findProjectRoot();
    final commandsDir = Directory(p.join(root, 'lib', 'app', 'commands'));
    writeCommandsIndex(commandsDir);
    return 0;
  }

  /// `SyncMonitors` → `sync-monitors`, `HTTPClient` → `h-t-t-p-client` —
  /// simple greedy lower-then-upper boundary insertion. Acronyms come out
  /// noisy; users edit the signature string to taste.
  static String _toKebabCase(String pascal) {
    if (pascal.isEmpty) return pascal;
    return pascal
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}-${m[2]}',
        )
        .toLowerCase();
  }
}
