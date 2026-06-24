import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:meta/meta.dart';

import '../console/artisan_command.dart';
import '../console/artisan_context.dart';
import '../console/command_boot.dart';
import '../console/pid_parser.dart';
import '../console/shell_quote.dart';
import '../state/state_file.dart';

/// Signature for [Process.start] test seam. Mirrors the upstream subset
/// [StartCommand] needs. The [mode] parameter is nullable so test fakes can
/// omit it comfortably; [_defaultProcessStart] bridges to [Process.start]'s
/// non-nullable parameter with a default.
typedef CdpProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  ProcessStartMode? mode,
});

/// Signature for [Process.run] test seam.
typedef CdpProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
});

/// Resolves the on-disk Chrome binary path or returns null when unsupported.
typedef CdpChromeBinaryResolver = String? Function(String? envOverride);

/// Probes a local Chrome instance on [port] within [timeout]. Returns when
/// Chrome answers /json/version; throws otherwise.
typedef CdpChromeProber = Future<void> Function(int port, Duration timeout);

/// Sends a Page.navigate CDP command to Chrome on [port] for [url].
typedef CdpChromeNavigator = Future<void> Function(int port, String url);

/// Scrapes the VM Service URI from a log file. Used to inject a fake in tests.
typedef CdpVmServiceScraper = Future<String> Function(File logFile);

/// Creates a POSIX FIFO at [path]. Real implementation calls `mkfifo`;
/// tests stub to a regular file.
typedef CdpFifoMaker = Future<void> Function(String path);

/// Waits until the web-server log emits the "is being served at" line.
/// Used to inject a fake (instant-return) in tests so the CDP branch can
/// be exercised without a real flutter process writing to the log.
typedef CdpWebServerReadyWaiter = Future<void> Function(File logFile);

/// Probes whether [port] is available for binding on loopback.
/// Returns `true` when the port is free, `false` when already in use.
typedef CdpPortProbe = Future<bool> Function(int port);

/// Sends [signal] to the process identified by [pid]. Mirrors
/// [Process.killPid]; swapped in tests to record best-effort reap calls on
/// the failure-cleanup path without touching real processes.
typedef CdpKillPid = bool Function(int pid, [ProcessSignal signal]);

/// Bridges [CdpProcessStarter]'s nullable [ProcessStartMode?] to
/// [Process.start]'s non-nullable parameter with a default.
Future<Process> _defaultProcessStart(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  ProcessStartMode? mode,
}) {
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: mode ?? ProcessStartMode.normal,
  );
}

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
/// The optional `--cdp-port=N` flag enables a CDP-aware Chrome launch:
/// 1. Validates the Flutter SDK is at or above 3.30.0 (the version that
///    activates `--web-experimental-hot-reload` for `-d web-server` per
///    flutter/flutter#170612).
/// 2. Resolves a Chrome binary path (macOS bundle or Linux PATH).
/// 3. Probes the web port ([defaultPortProbe]) to confirm it is free.
///    If the port is busy the command exits 1 immediately and spawns nothing.
/// 4. Pre-launches Chrome detached with `--remote-debugging-port=N`,
///    `--remote-allow-origins=*`, and a dedicated `--user-data-dir`.
/// 5. Probes the debug port to confirm Chrome is reachable.
/// 6. Runs `flutter run -d web-server --web-port=<port> --web-experimental-hot-reload`
///    (silent remap from `--device=chrome` because the chrome target would
///    auto-launch its own conflicting Chrome).
/// 7. Waits for the web-server log line "is being served at" so the URL
///    is bound before any client attempts to connect.
/// 8. Navigates the pre-launched Chrome to the served URL via CDP
///    Page.navigate. DWDS only emits "Debug service listening on ..."
///    AFTER a debugger client connects, so the navigate must happen
///    BEFORE the VM Service scrape; scraping first would deadlock the
///    handshake (see commit 871d0a7).
/// 9. Scrapes the VM Service URI from the flutter run log (DWDS prints
///    the "Debug service listening on ..." line once Chrome connected).
/// 10. Writes `chromePid`, `cdpPort`, and `tmpProfileDir` to the state file
///    so [StopCommand] can reap Chrome on teardown.
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

  /// Minimum Flutter SDK version required for the --cdp-port branch.
  /// Tied to flutter/flutter#170612 which wires --web-experimental-hot-reload
  /// for `-d web-server` and removes the --start-paused requirement.
  static const String _minCdpSdkVersion = '3.30.0';

  /// Test seam: Process.start replacement (Chrome + flutter wrapper).
  @visibleForTesting
  static CdpProcessStarter cdpProcessStarter = _defaultProcessStart;

  /// Test seam: Process.run replacement (flutter --version probe, mkfifo).
  @visibleForTesting
  static CdpProcessRunner cdpProcessRunner = Process.run;

  /// Test seam: Chrome binary resolver.
  @visibleForTesting
  static CdpChromeBinaryResolver cdpChromeBinaryResolver = defaultChromeBinary;

  /// Test seam: Chrome /json/version probe (default duplicates the
  /// fluttersdk_dusk ChromeFinder algorithm inline to avoid an inverted
  /// cross-package dependency).
  @visibleForTesting
  static CdpChromeProber cdpChromeProber = defaultChromeProbe;

  /// Test seam: Chrome Page.navigate (default opens a CDP WebSocket).
  @visibleForTesting
  static CdpChromeNavigator cdpChromeNavigator = defaultChromeNavigate;

  /// Test seam: VM Service URI scraper. When null, the production
  /// [_scrapeVmServiceUriFromFile] is used.
  @visibleForTesting
  static CdpVmServiceScraper? cdpVmServiceScraper;

  /// Test seam: tmp profile dir root (default `/tmp`).
  @visibleForTesting
  static String? cdpTmpProfileDirRoot;

  /// Test seam: replaces mkfifo (no-op in tests; production stays POSIX-pure).
  @visibleForTesting
  static CdpFifoMaker? cdpFifoMaker;

  /// Test seam: web-server readiness waiter. When null, the production
  /// [_waitForWebServerReady] polls the log file for the "is being served at"
  /// marker; tests inject an instant-return fake.
  @visibleForTesting
  static CdpWebServerReadyWaiter? cdpWebServerReadyWaiter;

  /// Test seam: web port availability probe. Returns `true` when the port
  /// is free to bind; `false` when already in use. Defaults to
  /// [defaultPortProbe], which attempts [ServerSocket.bind] and immediately
  /// closes the socket. Swap in tests to simulate a busy port.
  @visibleForTesting
  static CdpPortProbe cdpPortProbe = defaultPortProbe;

  /// Test seam: process-kill-by-pid (default [Process.killPid]). Used by the
  /// failure-cleanup path to SIGTERM the flutter holder + child when launch
  /// throws after the PIDs were captured.
  @visibleForTesting
  static CdpKillPid cdpKillPid = Process.killPid;

  /// Default [CdpPortProbe] implementation. Binds [ServerSocket] on
  /// [InternetAddress.loopbackIPv4] and immediately closes it.
  /// Returns `true` when the port is free; `false` on [SocketException]
  /// (port already in use).
  @visibleForTesting
  static Future<bool> defaultPortProbe(int port) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

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
      ..addOption(
        'vm-service-port',
        defaultsTo: '8181',
        help: 'Host VM Service port. Forwarded to flutter run as '
            '--host-vmservice-port=N and recorded in state.json so tools '
            'can reach the running app. Change when 8181 is already taken.',
      )
      ..addFlag('dds', defaultsTo: false, negatable: true)
      ..addFlag('profile-static', defaultsTo: false, negatable: true)
      ..addOption(
        'cdp-port',
        defaultsTo: null,
        help: 'Chrome DevTools Protocol port. When set, pre-launches Chrome '
            'with --remote-debugging-port=N and runs flutter with -d web-server. '
            'Required for dusk:resize / dusk:device commands.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '90',
        help: 'Seconds to wait for the VM Service URI to appear in the flutter '
            'run log. Increase on cold starts where build + DartDev init takes '
            'longer than the default. Applies to the --cdp-port branch only.',
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx, {int? cdpPort}) async {
    final device = (ctx.input.option('device') as String?) ?? 'chrome';
    final webPort = int.parse((ctx.input.option('port') as String?) ?? '3100');
    final vmServicePort =
        int.parse((ctx.input.option('vm-service-port') as String?) ?? '8181');
    final ddsOn = (ctx.input.option('dds') as bool?) ?? false;
    final profileStatic =
        (ctx.input.option('profile-static') as bool?) ?? false;

    // 1. Resolve the CDP port: an explicit --cdp-port flag wins; otherwise the
    //    forwarded `cdpPort` parameter (passed by RestartCommand from prior
    //    state before stop deleted state.json) is the fallback. A bare start
    //    with no flag and no forwarded param leaves it null (non-CDP branch).
    int? resolvedCdpPort = cdpPort;
    final cdpPortRaw = ctx.input.option('cdp-port') as String?;
    if (cdpPortRaw != null) {
      final parsed = int.tryParse(cdpPortRaw);
      if (parsed == null) {
        ctx.output.error(
          '--cdp-port expects an integer port number, got "$cdpPortRaw". '
          'Pass e.g. --cdp-port=9223.',
        );
        return 1;
      }
      resolvedCdpPort = parsed;
    }

    // 2. Resolve --timeout (applies to the CDP branch VM Service scrape).
    final timeoutRaw = (ctx.input.option('timeout') as String?) ?? '90';
    final resolvedTimeout = int.tryParse(timeoutRaw);
    if (resolvedTimeout == null) {
      ctx.output.error(
        '--timeout expects an integer number of seconds, got "$timeoutRaw". '
        'Pass e.g. --timeout=120.',
      );
      return 1;
    }

    if (resolvedCdpPort != null) {
      return await _handleCdpBranch(
        ctx: ctx,
        device: device,
        webPort: webPort,
        vmServicePort: vmServicePort,
        ddsOn: ddsOn,
        profileStatic: profileStatic,
        cdpPort: resolvedCdpPort,
        scrapTimeout: resolvedTimeout,
      );
    }

    final isChromeTarget = device == 'chrome';
    final logFile = File('${_logDir()}/flutter-dev.log');
    await logFile.parent.create(recursive: true);
    await logFile.writeAsString('');

    final fifoPath = '${_logDir()}/flutter-dev.fifo';
    await _ensureFifo(fifoPath);

    final flutterArgs = <String>[
      'run',
      '-d',
      device,
      if (isChromeTarget) '--web-port=$webPort',
      '--host-vmservice-port=$vmServicePort',
      if (!ddsOn) '--no-dds',
      '--dart-define=AI_TEST=1',
    ];

    final process = await _spawnFlutterWrapper(
      flutterArgs: flutterArgs,
      fifoPath: fifoPath,
      logFile: logFile,
    );

    final pids = await _scrapeTwoPids(process);
    final holderPid = pids['HOLDER'];
    final childPid = pids['FLUTTER'];
    if (holderPid == null || childPid == null) {
      throw StateError(
        'Failed to capture child PIDs from start wrapper: $pids',
      );
    }

    final vmServiceUri = await _runVmServiceScrape(logFile, 90);

    await StateFile.write(<String, dynamic>{
      'pid': childPid,
      'stdinPipe': fifoPath,
      'stdinHolderPid': holderPid,
      'vmServiceUri': vmServiceUri,
      'webPort': webPort,
      'vmServicePort': vmServicePort,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'profile': profileStatic ? 'static' : 'debug',
      'projectRoot': Directory.current.path,
      'device': device,
      'chromePid': null,
      'tmpProfileDir': null,
      'cdpPort': null,
    });

    ctx.output.success('flutter run pid=$childPid');
    ctx.output.success('vmServiceUri=$vmServiceUri');
    ctx.output.success('state=${StateFile.path}');
    ctx.output.success('log=${logFile.path}');
    return 0;
  }

  /// Handles the `--cdp-port=N` branch: validate, pre-launch Chrome,
  /// run flutter on web-server, scrape VM Service URI, navigate Chrome,
  /// write state.
  Future<int> _handleCdpBranch({
    required ArtisanContext ctx,
    required String device,
    required int webPort,
    required int vmServicePort,
    required bool ddsOn,
    required bool profileStatic,
    required int cdpPort,
    int scrapTimeout = 90,
  }) async {
    // 1. Validate device value: only chrome (default) and web-server accepted.
    if (device != 'chrome' && device != 'web-server') {
      ctx.output.error(
        '--cdp-port requires --device=chrome or --device=web-server. '
        'Got --device=$device.',
      );
      return 1;
    }

    // 2. Probe Flutter SDK version via flutter --version --machine, gate at
    //    3.30.0 (flutter/flutter#170612 activation floor).
    final sdkProbe = await _probeFlutterSdkVersion();
    if (sdkProbe == null || compareSemver(sdkProbe, _minCdpSdkVersion) < 0) {
      final detected = sdkProbe ?? 'unknown';
      ctx.output.error(
        'Flutter SDK $detected is older than $_minCdpSdkVersion. CDP commands '
        'require the WebSocket hot reload fix from flutter/flutter#170612. '
        'Run `flutter upgrade`.',
      );
      return 1;
    }

    // 3. Resolve Chrome binary inline (no cross-package import on
    //    fluttersdk_dusk; chrome_reaper has no binary-resolution helper).
    final chromeBinary = cdpChromeBinaryResolver(
      Platform.environment['DUSK_CHROME_BIN'],
    );
    if (chromeBinary == null) {
      ctx.output.error(
        'Chrome binary not found. macOS expects /Applications/Google Chrome.app; '
        'Linux expects google-chrome on PATH; Windows out of scope (V1 POSIX-only).',
      );
      return 1;
    }

    // 4. Probe web port availability before spawning anything. A busy port
    //    means flutter will fail immediately after Chrome is up, so fail fast
    //    here and spawn nothing.
    final webPortFree = await cdpPortProbe(webPort);
    if (!webPortFree) {
      ctx.output.error(
        'Port $webPort is already in use. Run `fsa stop` to free it or '
        'pass a different --port value.',
      );
      return 1;
    }

    // 4b. Probe CDP port availability before spawning Chrome. A busy CDP port
    //     means Chrome will fail to open the debug port, producing a misleading
    //     "Is Chrome installed?" error. Fail fast here with an actionable message.
    final cdpPortFree = await cdpPortProbe(cdpPort);
    if (!cdpPortFree) {
      ctx.output.error(
        'CDP port $cdpPort is already in use; pass --cdp-port <free-port> '
        'or free it before running start.',
      );
      return 1;
    }

    // 5. Launch Chrome detached with debug port + dedicated user-data-dir.
    final tmpRoot = cdpTmpProfileDirRoot ?? '/tmp';
    final tmpProfileDir = '$tmpRoot/dusk-chrome-$cdpPort';
    final chromeProcess = await cdpProcessStarter(
      chromeBinary,
      <String>[
        // CDP wiring (load-bearing for dusk + this start command).
        '--remote-debugging-port=$cdpPort',
        '--remote-allow-origins=*',
        '--user-data-dir=$tmpProfileDir',
        // Tells Chrome it is automated. Shows the "Chrome is being controlled
        // by automated test software" banner and implies several behaviors
        // that quiet first-run noise without us listing each one.
        '--enable-automation',
        // First-run flow + default-browser prompt (fresh tmp profile would
        // trigger Welcome dialog that blocks CDP Page.navigate).
        '--no-first-run',
        '--no-default-browser-check',
        // Save-password + autofill prompts (Flutter web forms trigger these
        // and the popups can intercept dusk:tap on the underlying widget).
        '--disable-save-password-bubble',
        '--password-store=basic',
        '--use-mock-keychain',
        '--disable-features=AutofillServerCommunication,PasswordLeakDetection,'
            'PasswordManagerOnboarding,Translate,MediaRouter,OptimizationHints,'
            'InterestFeedContentSuggestions,CalculateNativeWinOcclusion,'
            'GlobalMediaControls,DestroyProfileOnBrowserClose,'
            'AcceptCHFrame,AvoidUnnecessaryBeforeUnloadCheckSync',
        // Misc noise suppression. None of these change user-observable app
        // behavior; they only quiet Chrome internals so automation is clean.
        '--disable-translate',
        '--disable-sync',
        '--disable-background-networking',
        '--disable-default-apps',
        '--disable-extensions',
        '--disable-component-extensions-with-background-pages',
        '--disable-client-side-phishing-detection',
        '--disable-hang-monitor',
        '--disable-popup-blocking',
        '--disable-prompt-on-repost',
        '--disable-domain-reliability',
        '--metrics-recording-only',
        '--no-pings',
        '--no-service-autorun',
        // Performance: keep timers + renderer active when window not focused
        // so dusk actions land on a live frame.
        '--disable-background-timer-throttling',
        '--disable-renderer-backgrounding',
        '--disable-backgrounding-occluded-windows',
        '--disable-ipc-flooding-protection',
        'about:blank',
      ],
      mode: ProcessStartMode.detached,
    );

    // 6. Probe Chrome to confirm it opened the debug port; on failure kill it
    //    so we never leak a runaway Chrome with no parent supervision.
    try {
      await cdpChromeProber(cdpPort, const Duration(seconds: 10));
    } catch (_) {
      chromeProcess.kill();
      ctx.output.error(
        'Chrome failed to open debug port $cdpPort. Is Chrome installed?',
      );
      return 1;
    }

    // 7. Build flutter argv: always -d web-server here (chrome target would
    //    auto-launch its own conflicting Chrome). Path construction below is
    //    pure (no I/O); the side-effecting log + FIFO creation happens inside
    //    the try so a failure there still reaps the already-launched Chrome.
    final logFile = File('${_logDir()}/flutter-dev.log');
    final fifoPath = '${_logDir()}/flutter-dev.fifo';

    final flutterArgs = <String>[
      'run',
      '-d',
      'web-server',
      '--web-port=$webPort',
      '--web-experimental-hot-reload',
      '--host-vmservice-port=$vmServicePort',
      if (!ddsOn) '--no-dds',
      '--dart-define=AI_TEST=1',
    ];

    // The flutter wrapper handle + captured PIDs are held nullable so the
    // failure-cleanup catch can reap whatever was already spawned, regardless
    // of which step (log/FIFO setup, PID capture, navigate, scrape) threw.
    Process? flutterProcess;
    int? holderPid;
    int? childPid;
    try {
      // 8. Prepare the log file + FIFO. Inside the try so a failure here still
      //    reaps the already-launched Chrome + tmp profile dir.
      await logFile.parent.create(recursive: true);
      await logFile.writeAsString('');
      await _ensureFifo(fifoPath);

      // 9. Spawn flutter with the existing FIFO wrapper pattern.
      flutterProcess = await _spawnFlutterWrapper(
        flutterArgs: flutterArgs,
        fifoPath: fifoPath,
        logFile: logFile,
      );

      final pids = await _scrapeTwoPids(flutterProcess);
      holderPid = pids['HOLDER'];
      childPid = pids['FLUTTER'];
      if (holderPid == null || childPid == null) {
        throw StateError(
          'Failed to capture child PIDs from start wrapper: $pids',
        );
      }

      // 10. Wait for the web server to be ready (look for "is being served at"
      //     line in the log), then navigate Chrome FIRST so the debug service
      //     has a client to emit the VM Service URI to. Scraping the URI before
      //     navigation deadlocks: -d web-server only emits "Debug service
      //     listening on ws://..." AFTER a debugger client connects.
      await _runWebServerReadyWait(logFile);
      await cdpChromeNavigator(cdpPort, 'http://localhost:$webPort/');

      // 11. NOW scrape the VM Service URI emitted by DWDS once Chrome connected.
      final vmServiceUri = await _runVmServiceScrape(logFile, scrapTimeout);

      // 12. Write state with the new CDP fields so StopCommand can reap Chrome.
      await StateFile.write(<String, dynamic>{
        'pid': childPid,
        'stdinPipe': fifoPath,
        'stdinHolderPid': holderPid,
        'vmServiceUri': vmServiceUri,
        'webPort': webPort,
        'vmServicePort': vmServicePort,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'profile': profileStatic ? 'static' : 'debug',
        'projectRoot': Directory.current.path,
        'device': device,
        'chromePid': chromeProcess.pid,
        'tmpProfileDir': tmpProfileDir,
        'cdpPort': cdpPort,
      });

      ctx.output.success('chrome pid=${chromeProcess.pid} (cdpPort=$cdpPort)');
      ctx.output.success('flutter run pid=$childPid');
      ctx.output.success('vmServiceUri=$vmServiceUri');
      ctx.output.success('state=${StateFile.path}');
      ctx.output.success('log=${logFile.path}');
      return 0;
    } catch (error) {
      // 13. Best-effort reap of everything launched above so a post-Chrome
      //     failure leaks no Chrome, no flutter web-server, no FIFO, no tmp
      //     profile dir. Every action is individually guarded and swallows so
      //     one cleanup failure cannot abort the rest; the error surfaced to
      //     the operator is the ORIGINAL throw, never a cleanup error. This is
      //     best-effort SIGTERM only (no SIGKILL grace loop): the OS reaps
      //     detached children and `fsa stop` is the deliberate full reaper.
      _reapAfterCdpFailure(
        flutterProcess: flutterProcess,
        holderPid: holderPid,
        childPid: childPid,
        chromeProcess: chromeProcess,
        fifoPath: fifoPath,
        tmpProfileDir: tmpProfileDir,
      );
      ctx.output.error('CDP start failed after launch: $error');
      return 1;
    }
  }

  /// Best-effort reap of every child the CDP branch spawned, invoked only from
  /// the failure-cleanup catch in [_handleCdpBranch]. Mirrors the kill + rm
  /// cascade of `StopCommand._reapChrome` but without a SIGKILL grace loop:
  /// this is the failure path, the handles are still held, and `fsa stop`
  /// remains the deliberate full reaper.
  ///
  /// Every action is wrapped in its own `try`/swallow so a single failure
  /// (process already gone, missing FIFO, locked profile dir) never aborts the
  /// remaining cleanup and never replaces the original error surfaced upstream.
  void _reapAfterCdpFailure({
    required Process? flutterProcess,
    required int? holderPid,
    required int? childPid,
    required Process chromeProcess,
    required String fifoPath,
    required String tmpProfileDir,
  }) {
    // 1. SIGTERM the flutter child + holder. When the PIDs were captured, reap
    //    by pid (the detached holder + child outlive the wrapper handle);
    //    otherwise fall back to killing the wrapper Process handle directly.
    if (childPid != null || holderPid != null) {
      for (final pid in <int?>[childPid, holderPid]) {
        if (pid == null) continue;
        try {
          cdpKillPid(pid, ProcessSignal.sigterm);
        } catch (_) {
          // Non-fatal: the process may already be gone.
        }
      }
    } else if (flutterProcess != null) {
      try {
        flutterProcess.kill();
      } catch (_) {
        // Non-fatal.
      }
    }

    // 2. SIGTERM Chrome via the held handle.
    try {
      chromeProcess.kill();
    } catch (_) {
      // Non-fatal.
    }

    // 3. Delete the FIFO file.
    try {
      final fifo = File(fifoPath);
      if (fifo.existsSync()) fifo.deleteSync();
    } catch (_) {
      // Non-fatal: a stale FIFO is harmless.
    }

    // 4. Delete the tmp profile dir (mirrors _reapChrome's rm).
    try {
      final dir = Directory(tmpProfileDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // Non-fatal: a stale profile directory is not worth surfacing.
    }
  }

  /// Spawns the FIFO-wrapped flutter run process. Common to both the default
  /// and the --cdp-port branches.
  Future<Process> _spawnFlutterWrapper({
    required List<String> flutterArgs,
    required String fifoPath,
    required File logFile,
  }) async {
    // Two background processes:
    // 1. `tail -f /dev/null > fifo` holds the FIFO write end open so flutter
    //    run's stdin does not EOF when the keystroke writer closes.
    // 2. `nohup flutter run ... < fifo` reads from the FIFO on stdin.
    final wrapperArgs = <String>['nohup', 'flutter', ...flutterArgs];
    return await cdpProcessStarter(
      'sh',
      <String>[
        '-c',
        'tail -f /dev/null > ${shellQuoteTokens([
              fifoPath
            ])} & echo HOLDER=\$! ; '
            '${shellQuoteTokens(wrapperArgs)} < ${shellQuoteTokens([
              fifoPath
            ])} >> ${shellQuoteTokens([logFile.path])} 2>&1 & echo FLUTTER=\$!',
      ],
      mode: ProcessStartMode.detachedWithStdio,
    );
  }

  /// Creates the FIFO at [path]. Delegates to a test seam when [cdpFifoMaker]
  /// is set; otherwise calls `mkfifo` via [cdpProcessRunner].
  Future<void> _ensureFifo(String path) async {
    final fifoFile = File(path);
    if (fifoFile.existsSync()) await fifoFile.delete();
    final maker = cdpFifoMaker;
    if (maker != null) {
      await maker(path);
      return;
    }
    final mkfifoResult = await cdpProcessRunner('mkfifo', <String>[path]);
    if (mkfifoResult.exitCode != 0) {
      throw StateError(
        'mkfifo failed (Windows not yet supported; V1 is POSIX-only): '
        '${mkfifoResult.stderr}',
      );
    }
  }

  /// Runs the web-server readiness wait, honoring the test seam when set.
  Future<void> _runWebServerReadyWait(File logFile) {
    final waiter = cdpWebServerReadyWaiter;
    if (waiter != null) return waiter(logFile);
    return _waitForWebServerReady(logFile);
  }

  /// Wait until the web-server log emits "is being served at" so the URL
  /// is bound and Chrome's navigation will not race the bind.
  Future<void> _waitForWebServerReady(File logFile) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (logFile.existsSync()) {
        final content = logFile.readAsStringSync();
        if (content.contains('is being served at')) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError(
      'Timed out after 60s waiting for "is being served at" in ${logFile.path}.',
    );
  }

  /// Runs the VM Service URI scrape, honoring the test seam when set.
  /// [timeoutSeconds] caps the scrape loop; the production implementation
  /// uses it as the deadline, while the test seam ignores it.
  Future<String> _runVmServiceScrape(File logFile, int timeoutSeconds) {
    final scraper = cdpVmServiceScraper;
    if (scraper != null) return scraper(logFile);
    return _scrapeVmServiceUriFromFile(logFile, timeoutSeconds);
  }

  /// Probes `flutter --version --machine` and extracts `frameworkVersion`.
  /// Returns null on parse failure or when the flutter binary is missing.
  Future<String?> _probeFlutterSdkVersion() async {
    try {
      final result = await cdpProcessRunner(
        'flutter',
        <String>['--version', '--machine'],
      );
      if (result.exitCode != 0) return null;
      final raw = result.stdout;
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['frameworkVersion'];
      return version is String ? version : null;
    } catch (_) {
      return null;
    }
  }

  /// Compares two semver-ish strings by numeric segments only. Strips dev /
  /// build suffixes (everything after the first `-`). Returns negative if
  /// [a] < [b], 0 if equal, positive if [a] > [b]. Pads missing segments
  /// with 0 so `3.30` compares equal to `3.30.0`.
  @visibleForTesting
  static int compareSemver(String a, String b) {
    final aSegments = _semverSegments(a);
    final bSegments = _semverSegments(b);
    final length = aSegments.length > bSegments.length
        ? aSegments.length
        : bSegments.length;
    for (var i = 0; i < length; i++) {
      final aV = i < aSegments.length ? aSegments[i] : 0;
      final bV = i < bSegments.length ? bSegments[i] : 0;
      if (aV != bV) return aV - bV;
    }
    return 0;
  }

  static List<int> _semverSegments(String version) {
    final core = version.split('-').first;
    return core
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList(growable: false);
  }

  /// Resolves the Chrome binary path: macOS canonical bundle, then Linux
  /// PATH lookup. Returns null on Windows or when neither candidate exists.
  /// [envOverride] is reserved for V1.x `DUSK_CHROME_BIN`; currently ignored.
  @visibleForTesting
  static String? Function(String? envOverride) get defaultChromeBinary =>
      (envOverride) => resolveChromeBinary(
            isMacOs: Platform.isMacOS,
            isLinux: Platform.isLinux,
            macAppExists: (p) => File(p).existsSync(),
            pathLookup: _whichPosix,
          );

  /// Pure resolver for testability: macOS bundle path, Linux PATH `google-chrome`,
  /// otherwise null. Injects platform booleans and lookup functions so the
  /// real Platform / File / which dependencies stay out of unit tests.
  @visibleForTesting
  static String? resolveChromeBinary({
    required bool isMacOs,
    required bool isLinux,
    required bool Function(String) macAppExists,
    required String? Function(String) pathLookup,
  }) {
    const macPath =
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    if (isMacOs && macAppExists(macPath)) return macPath;
    if (isLinux) {
      final found = pathLookup('google-chrome');
      if (found != null) return found;
    }
    return null;
  }

  /// POSIX `which`-style lookup. Returns absolute path when binary is on PATH,
  /// null otherwise. Windows always returns null (V1 POSIX-only).
  static String? _whichPosix(String binary) {
    if (Platform.isWindows) return null;
    try {
      final result = Process.runSync('which', <String>[binary]);
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String).trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// Production Chrome probe: polls /json/version with retry on
  /// SocketException, throws on HTTP 404 or timeout. Inline duplicate of
  /// fluttersdk_dusk's ChromeFinder.probe algorithm (avoids inverted
  /// cross-package dependency).
  @visibleForTesting
  static Future<void> Function(int, Duration) get defaultChromeProbe =>
      (port, timeout) async {
        final sw = Stopwatch()..start();
        const interval = Duration(milliseconds: 250);
        while (sw.elapsed < timeout) {
          try {
            final client = HttpClient();
            try {
              final req = await client.getUrl(
                Uri.parse('http://localhost:$port/json/version'),
              );
              final resp = await req.close();
              if (resp.statusCode == 200) {
                await resp.drain<void>();
                return;
              }
              if (resp.statusCode == 404) {
                throw StateError(
                  'Port $port is open but does not serve Chrome DevTools '
                  'Protocol. Is it the right Chrome instance?',
                );
              }
              await resp.drain<void>();
            } finally {
              client.close(force: true);
            }
          } on SocketException {
            // Connection refused: Chrome not up yet, retry.
          }
          await Future<void>.delayed(interval);
        }
        throw StateError(
          'Timed out after ${timeout.inSeconds}s waiting for Chrome on '
          'port $port.',
        );
      };

  /// Production Chrome Page.navigate: HTTP /json/version + WebSocket connect
  /// + JSON-RPC send + close. Inline duplicate of dusk's CdpClient at smaller
  /// scope (V1 cross-package inversion avoidance).
  @visibleForTesting
  static Future<void> Function(int, String) get defaultChromeNavigate =>
      (port, url) async {
        // Page.navigate requires a TARGET (page) WebSocket, not the
        // BROWSER-level WS that /json/version exposes. /json lists every
        // attached target with its own webSocketDebuggerUrl. Pick the first
        // page-type target (the about:blank tab Chrome opened on launch).
        final client = HttpClient();
        String wsUrl;
        try {
          final req = await client.getUrl(
            Uri.parse('http://localhost:$port/json'),
          );
          final resp = await req.close();
          if (resp.statusCode != 200) {
            throw StateError(
              'Chrome /json returned ${resp.statusCode} on port $port.',
            );
          }
          final body = await resp.transform(utf8.decoder).join();
          final targets = jsonDecode(body) as List<dynamic>;
          final pageTarget =
              targets.whereType<Map<String, dynamic>>().firstWhere(
                    (t) => t['type'] == 'page',
                    orElse: () => throw StateError(
                      'No page-type target in Chrome /json on port $port.',
                    ),
                  );
          wsUrl = pageTarget['webSocketDebuggerUrl'] as String;
        } finally {
          client.close(force: true);
        }

        final ws = await WebSocket.connect(wsUrl);
        try {
          final completer = Completer<void>();
          ws.listen(
            (raw) {
              if (completer.isCompleted) return;
              try {
                final decoded = jsonDecode(raw as String);
                if (decoded is Map && decoded['id'] == 1) {
                  if (decoded['error'] != null) {
                    completer.completeError(StateError(
                      'CDP Page.navigate failed: ${decoded['error']}',
                    ));
                  } else {
                    completer.complete();
                  }
                }
              } catch (e, st) {
                completer.completeError(e, st);
              }
            },
            onError: completer.completeError,
            onDone: () {
              if (!completer.isCompleted) {
                completer.completeError(
                  StateError('CDP WebSocket closed before Page.navigate ack.'),
                );
              }
            },
            cancelOnError: true,
          );
          ws.add(jsonEncode(<String, dynamic>{
            'id': 1,
            'method': 'Page.navigate',
            'params': <String, dynamic>{'url': url},
          }));
          await completer.future.timeout(const Duration(seconds: 10));
        } finally {
          await ws.close();
        }
      };

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

  /// Parses `HOLDER=<int>` and `FLUTTER=<int>` lines emitted by the start
  /// wrapper. Delegates the line-to-map parse to [parsePidLines]; this method
  /// owns the stream-completion plumbing.
  Future<Map<String, int>> _scrapeTwoPids(Process process) async {
    final captured = <String, int>{};
    final completer = Completer<Map<String, int>>();
    late final StreamSubscription<String> sub;
    sub = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      final parsed = parsePidLines(<String>[line]);
      captured.addAll(parsed);
      if (captured.length == 2 && !completer.isCompleted) {
        completer.complete(captured);
        sub.cancel();
      }
    });
    return await completer.future.timeout(const Duration(seconds: 10));
  }

  Future<String> _scrapeVmServiceUriFromFile(
    File logFile,
    int timeoutSeconds,
  ) async {
    final sw = Stopwatch()..start();
    int lastSize = 0;
    while (sw.elapsed < Duration(seconds: timeoutSeconds)) {
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
      'Timed out after ${timeoutSeconds}s waiting for VM Service URI in '
      '${logFile.path}.',
    );
  }

  /// Derives the artisan log directory from [StateFile.path] so the log,
  /// FIFO, and state.json all live under the same `~/.artisan/` (or test
  /// override) directory in a single hop.
  static String _logDir() {
    final statePath = StateFile.path;
    // Strip the trailing `/state.json` segment.
    final lastSlash = statePath.lastIndexOf('/');
    return lastSlash == -1 ? statePath : statePath.substring(0, lastSlash);
  }
}
