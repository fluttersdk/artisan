import 'dart:io';

import 'package:path/path.dart' as p;

/// One discovered command entry from the filesystem scan.
class DiscoveredCommand {
  const DiscoveredCommand({required this.className, required this.fileName});

  /// Dart class name (e.g. `CleanCacheCommand`).
  final String className;

  /// Source file name relative to the commands directory
  /// (e.g. `clean_cache.dart`).
  final String fileName;
}

/// Scans [commandsDir] for `*.dart` files (excluding `_index.g.dart` and
/// anything else starting with `_`), extracts `ArtisanCommand` subclass
/// names, returns one [DiscoveredCommand] per match.
///
/// Multiple matching classes in the same file are returned in declaration
/// order. The result is sorted by file name to keep the generated index
/// deterministic across runs.
List<DiscoveredCommand> discoverCommandsInDir(Directory commandsDir) {
  if (!commandsDir.existsSync()) return const <DiscoveredCommand>[];

  final entries = commandsDir.listSync().whereType<File>().where((f) {
    final base = p.basename(f.path);
    if (!base.endsWith('.dart')) return false;
    if (base.startsWith('_')) return false; // _index.g.dart + any private file
    return true;
  }).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final out = <DiscoveredCommand>[];
  for (final file in entries) {
    final source = file.readAsStringSync();
    for (final match in _classPattern.allMatches(source)) {
      final className = match.group(1)!;
      out.add(
        DiscoveredCommand(
          className: className,
          fileName: p.basename(file.path),
        ),
      );
    }
  }
  return out;
}

/// Renders the auto-generated index file content for [commands].
///
/// Shape:
/// ```dart
/// // AUTO-GENERATED ...
/// import 'package:fluttersdk_artisan/artisan.dart';
///
/// import 'clean_cache.dart';
///
/// List<ArtisanCommand> get commands => <ArtisanCommand>[
///   CleanCacheCommand(),
/// ];
/// ```
String renderCommandsIndex(List<DiscoveredCommand> commands) {
  final buf = StringBuffer()
    ..writeln('// AUTO-GENERATED — DO NOT EDIT.')
    ..writeln('// Regenerate via: artisan commands:refresh')
    ..writeln('// (Also auto-updated by: artisan make:command <Name>)')
    ..writeln()
    ..writeln("import 'package:fluttersdk_artisan/artisan.dart';");

  if (commands.isEmpty) {
    buf
      ..writeln()
      ..writeln(
          'List<ArtisanCommand> get commands => const <ArtisanCommand>[];')
      ..writeln();
    return buf.toString();
  }

  // Deduplicate file imports (same file may export multiple commands).
  final imports = <String>{for (final c in commands) c.fileName}.toList()
    ..sort();
  buf.writeln();
  for (final f in imports) {
    buf.writeln("import '$f';");
  }
  buf
    ..writeln()
    ..writeln('List<ArtisanCommand> get commands => <ArtisanCommand>[');
  for (final c in commands) {
    buf.writeln('  ${c.className}(),');
  }
  buf
    ..writeln('];')
    ..writeln();
  return buf.toString();
}

/// End-to-end: scan + write. Returns the discovered command list so the
/// caller can report what was registered.
List<DiscoveredCommand> writeCommandsIndex(Directory commandsDir) {
  final discovered = discoverCommandsInDir(commandsDir);
  if (!commandsDir.existsSync()) {
    commandsDir.createSync(recursive: true);
  }
  final indexFile = File(p.join(commandsDir.path, '_index.g.dart'));
  indexFile.writeAsStringSync(renderCommandsIndex(discovered));
  return discovered;
}

/// Matches `class XxxCommand extends YyyCommand` declarations. The base
/// class must itself end in `Command` (covers `ArtisanCommand`,
/// `ArtisanGeneratorCommand`, and any user-defined intermediate base).
/// Comments and string literals are NOT excluded — the convention says
/// command class declarations live at the top level of their file.
final RegExp _classPattern = RegExp(
  r'class\s+(\w+Command)\s+extends\s+\w*Command\b',
);
