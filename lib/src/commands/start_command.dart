import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../state/state_file.dart';

/// Spawns `flutter run -d <device>` detached, scrapes the VM Service URI
/// from stdout, writes `~/.artisan/state.json` for downstream consumers.
///
/// Supports `--device` flag (default `chrome`). For non-chrome targets the
/// `--web-port` flag is omitted (flutter rejects it on desktop/mobile).
/// URI scrape regex matches both web and desktop/mobile stdout formats:
/// - Web: `Debug service listening on ws://127.0.0.1:8181/<token>/ws`
/// - Desktop/mobile: `A Dart VM Service on <Platform> is available at: http://127.0.0.1:<port>/<token>/`
/// Desktop/mobile `http://...` URIs are normalized to `ws://.../ws`.
///
/// D6 Chrome reaper (POSIX, chrome target only) defers to V1.x; V1 ships
/// the basic spawn + URI scrape + state.json write.
class StartCommand extends ArtisanCommand {
  @override
  String get name => 'start';

  @override
  String get description =>
      'Boot `flutter run -d <device>` detached and record the VM Service URI to ~/.artisan/state.json.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'device',
        defaultsTo: 'chrome',
        help:
            'Flutter device target (chrome / macos / linux / windows / iOS UDID / Android serial).',
      )
      ..addOption('port', defaultsTo: '3100', help: 'Web port (chrome only).')
      ..addOption('vm-service-port', defaultsTo: '8181')
      ..addFlag('dds', defaultsTo: false, negatable: true)
      ..addFlag('profile-static', defaultsTo: false, negatable: true);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final device = (ctx.input.option('device') as String?) ?? 'chrome';
    final webPort = int.parse((ctx.input.option('port') as String?) ?? '3100');
    final ddsOn = (ctx.input.option('dds') as bool?) ?? false;
    final profileStatic =
        (ctx.input.option('profile-static') as bool?) ?? false;
    final isChromeTarget = device == 'chrome';

    final logFile = File('${_logDir()}/flutter-dev.log');
    await logFile.parent.create(recursive: true);
    await logFile.writeAsString('');

    final flutterArgs = <String>[
      'run',
      '-d',
      device,
      if (isChromeTarget) '--web-port=$webPort',
      if (!ddsOn) '--no-dds',
      '--dart-define=AI_TEST=1',
    ];

    final wrapperArgs = <String>['nohup', 'flutter', ...flutterArgs];
    final process = await Process.start(
        'sh',
        <String>[
          '-c',
          '${_shellQuote(wrapperArgs)} </dev/null >>${_shellQuote([
                logFile.path
              ])} 2>&1 & echo \$!',
        ],
        mode: ProcessStartMode.detachedWithStdio);

    final childPid = await _scrapeChildPid(process);
    final vmServiceUri = await _scrapeVmServiceUriFromFile(logFile);

    await StateFile.write(<String, dynamic>{
      'pid': childPid,
      'vmServiceUri': vmServiceUri,
      'webPort': webPort,
      'vmServicePort': 8181,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'profile': profileStatic ? 'static' : 'debug',
      'projectRoot': Directory.current.path,
      'device': device,
      'chromePid': null,
      'tmpProfileDir': null,
    });

    ctx.output.success('flutter run pid=$childPid');
    ctx.output.success('vmServiceUri=$vmServiceUri');
    ctx.output.success('state=${StateFile.path}');
    ctx.output.success('log=${logFile.path}');
    return 0;
  }

  static final RegExp _uriPattern = RegExp(
    r'(?:Debug service listening on|Dart VM Service on .+? is available at:?)\s+(\S+)',
  );

  static String normalizeVmServiceUri(String raw) {
    String uri = raw;
    if (uri.startsWith('http://')) {
      uri = 'ws://${uri.substring('http://'.length)}';
    } else if (uri.startsWith('https://')) {
      uri = 'wss://${uri.substring('https://'.length)}';
    }
    if (uri.endsWith('/ws')) return uri;
    if (uri.endsWith('/ws/')) return uri.substring(0, uri.length - 1);
    return uri.endsWith('/') ? '${uri}ws' : '$uri/ws';
  }

  Future<int> _scrapeChildPid(Process process) async {
    final completer = Completer<int>();
    late final StreamSubscription<String> sub;
    sub = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      final pid = int.tryParse(line.trim());
      if (pid != null && !completer.isCompleted) {
        completer.complete(pid);
        sub.cancel();
      }
    });
    return await completer.future.timeout(const Duration(seconds: 10));
  }

  Future<String> _scrapeVmServiceUriFromFile(File logFile) async {
    final sw = Stopwatch()..start();
    int lastSize = 0;
    while (sw.elapsed < const Duration(seconds: 90)) {
      if (logFile.existsSync()) {
        final size = logFile.lengthSync();
        if (size > lastSize) {
          final chunk = logFile.readAsStringSync();
          for (final line in const LineSplitter().convert(chunk)) {
            final match = _uriPattern.firstMatch(line);
            if (match != null) return normalizeVmServiceUri(match.group(1)!);
          }
          lastSize = size;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError(
      'Timed out after 90s waiting for VM Service URI in ${logFile.path}.',
    );
  }

  static String _shellQuote(List<String> tokens) {
    final bareword = RegExp(r'^[A-Za-z0-9_./=:-]+$');
    return tokens.map((t) {
      if (bareword.hasMatch(t)) return t;
      return "'${t.replaceAll("'", r"'\''")}'";
    }).join(' ');
  }

  static String _logDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
    return '$home/.artisan';
  }
}
