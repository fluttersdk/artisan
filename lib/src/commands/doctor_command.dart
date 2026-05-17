import 'dart:io';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';

/// Runs environment preflight checks (artisan toolchain).
class DoctorCommand extends ArtisanCommand {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Run environment preflight checks (flutter, dart, port availability).';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final checks = <_Check>[
      _Check('flutter --version', _checkFlutter),
      _Check('dart --version', _checkDart),
      _Check('port 3100 free', _checkPort3100),
    ];
    var allPass = true;
    for (final c in checks) {
      final pass = await c.run();
      if (!pass) allPass = false;
      ctx.output.writeln('  ${pass ? '✓' : '✗'} ${c.label}');
    }
    return allPass ? 0 : 1;
  }

  static Future<bool> _checkFlutter() async {
    try {
      final r = await Process.run('flutter', <String>['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkDart() async {
    try {
      final r = await Process.run('dart', <String>['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkPort3100() async {
    if (Platform.isWindows) return true; // skip for V1
    try {
      final r = await Process.run('lsof', <String>['-ti', 'tcp:3100']);
      return r.exitCode != 0 || (r.stdout as String).trim().isEmpty;
    } catch (_) {
      return true;
    }
  }
}

class _Check {
  _Check(this.label, this.run);
  final String label;
  final Future<bool> Function() run;
}
