import 'dart:io';

import 'package:fluttersdk_artisan/src/commands/helpers/process_group_reaper.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessGroupReaper', () {
    test('signals the process group, so a child of the tool dies with it',
        () async {
      // The tool (200) and its frontend_server (201) share group 190, which is
      // what a detached spawn produces. Signalling 200 alone orphaned 201.
      final _FakeProcessTable table = _FakeProcessTable(<int, int>{
        200: 190,
        201: 190,
      });

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(table.signals, <(int, ProcessSignal)>[
        (-190, ProcessSignal.sigterm),
      ]);
      expect(result.outcome, ReapOutcome.exited);
      expect(result.pgid, 190);
      expect(result.boundPorts, isEmpty);
      expect(table.live, isEmpty);
    });

    test('waits until the last member of the group is gone, not only the pid',
        () async {
      // The tool exits on SIGTERM at once; frontend_server takes three more
      // polls. Returning when the pid is gone is the race `restart` lost.
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{
          200: 190,
          201: 190,
        },
        lingerPolls: <int, int>{201: 3},
      );

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(result.outcome, ReapOutcome.exited);
      expect(table.live, isEmpty);
    });

    test('escalates to SIGKILL on the group when SIGTERM is ignored', () async {
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{
          200: 190,
          201: 190,
        },
        diesOn: ProcessSignal.sigkill,
      );

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(table.signals, <(int, ProcessSignal)>[
        (-190, ProcessSignal.sigterm),
        (-190, ProcessSignal.sigkill),
      ]);
      expect(result.outcome, ReapOutcome.killed);
    });

    test('reports survived when the group outlives SIGKILL and the budget',
        () async {
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{200: 190},
        diesOn: null,
      );

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(result.outcome, ReapOutcome.survived);
    });

    test('does not count a zombie as a live member', () async {
      // Under a pid 1 that reaps nothing (a container entrypoint), a dead
      // member stays in `ps -A` as a zombie for good; counting it wedged
      // every later `stop` on "survived".
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{
          200: 190,
          201: 190,
        },
        zombies: <int>{201},
      );

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(result.outcome, ReapOutcome.exited);
      expect(table.signals, <(int, ProcessSignal)>[
        (-190, ProcessSignal.sigterm),
      ]);
    });

    test('reads a failing process listing as alive, never as gone', () async {
      // Empty output from a failed `ps -A` used to read as "group gone", and
      // `stop` then deleted the session of a live app.
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{200: 190},
        listingFails: true,
      );

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(result.outcome, ReapOutcome.survived);
    });

    test('waits for a port the group held to come free', () async {
      final _FakeProcessTable table = _FakeProcessTable(<int, int>{200: 190});
      int probes = 0;

      final ReapResult result = await _reaperFor(
        table,
        isPortFree: (int port) async => ++probes > 2,
      ).reap(200, ports: <int>[3100]);

      expect(probes, 3);
      expect(result.boundPorts, isEmpty);
    });

    test('reports a port still bound when the budget runs out, without SIGKILL',
        () async {
      // Nothing of ours is left to kill; the holder is someone else.
      final _FakeProcessTable table = _FakeProcessTable(<int, int>{200: 190});

      final ReapResult result = await _reaperFor(
        table,
        isPortFree: (int port) async => port != 3100,
      ).reap(200, ports: <int>[3100, 9223]);

      expect(result.outcome, ReapOutcome.exited);
      expect(result.boundPorts, <int>[3100]);
      expect(table.signals, <(int, ProcessSignal)>[
        (-190, ProcessSignal.sigterm),
      ]);
    });

    test('never signals its own process group', () async {
      // A tool that shares the caller's group (a non-detached spawn) would
      // take the caller down with it; only the pid is signalled.
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{200: _FakeProcessTable.ownPgid},
      );

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(table.signals, <(int, ProcessSignal)>[
        (200, ProcessSignal.sigterm),
      ]);
      expect(result.pgid, isNull);
      expect(result.outcome, ReapOutcome.exited);
    });

    test('never signals process group 1', () async {
      final _FakeProcessTable table = _FakeProcessTable(<int, int>{200: 1});

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(table.signals, <(int, ProcessSignal)>[
        (200, ProcessSignal.sigterm),
      ]);
      expect(result.pgid, isNull);
    });

    test('signals nothing for a pid of 1 or below', () async {
      // `kill(0)` addresses the caller's own group and `kill(-1)` every
      // process it may signal; a hand-edited session can carry either.
      final _FakeProcessTable table = _FakeProcessTable(<int, int>{});

      for (final int pid in <int>[1, 0, -1]) {
        final ReapResult result = await _reaperFor(table).reap(pid);
        expect(result.termDelivered, isFalse);
      }

      expect(table.signals, isEmpty);
    });

    test('signals nothing when the pid now belongs to a newer process',
        () async {
      // A stale session's pid can be reused by anything, an editor, a
      // terminal job. Its group was SIGKILLed along with it.
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{
          200: 190,
          201: 190,
        },
        ageSeconds: <int, int>{200: 5},
      );

      final ReapResult result = await _reaperFor(table).reap(
        200,
        startedBy: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(table.signals, isEmpty);
      expect(result.pidReused, isTrue);
      expect(result.pgid, isNull);
      expect(result.outcome, ReapOutcome.exited);
      expect(table.live, <int>{200, 201});
    });

    test(
        'signals the group of a pid that started before the session was '
        'recorded', () async {
      final _FakeProcessTable table = _FakeProcessTable(
        <int, int>{200: 190},
        // Two days, one hour, one minute and one second: every etime field.
        ageSeconds: <int, int>{200: 2 * 86400 + 3661},
      );

      final ReapResult result = await _reaperFor(table).reap(
        200,
        startedBy: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(result.pidReused, isFalse);
      expect(table.signals, <(int, ProcessSignal)>[
        (-190, ProcessSignal.sigterm),
      ]);
    });

    test('signals the bare pid when it is already gone', () async {
      final _FakeProcessTable table = _FakeProcessTable(<int, int>{});

      final ReapResult result = await _reaperFor(table).reap(200);

      expect(table.signals, <(int, ProcessSignal)>[
        (200, ProcessSignal.sigterm),
      ]);
      expect(result.termDelivered, isFalse);
      expect(result.pgid, isNull);
      expect(result.outcome, ReapOutcome.exited);
    });

    test('uses the injected liveness probe for a pid with no group', () async {
      final _FakeProcessTable table = _FakeProcessTable(<int, int>{});
      final List<int> probed = <int>[];

      final ReapResult result = await _reaperFor(
        table,
        isAlive: (int pid) async {
          probed.add(pid);
          return false;
        },
      ).reap(200);

      expect(probed, contains(200));
      expect(result.outcome, ReapOutcome.exited);
    });
  });
}

ProcessGroupReaper _reaperFor(
  _FakeProcessTable table, {
  Future<bool> Function(int pid)? isAlive,
  Future<bool> Function(int port)? isPortFree,
}) {
  return ProcessGroupReaper(
    kill: table.kill,
    run: table.run,
    isAlive: isAlive,
    isPortFree: isPortFree,
    grace: const Duration(milliseconds: 200),
    pollInterval: const Duration(milliseconds: 1),
    selfPid: _FakeProcessTable.selfPid,
  );
}

/// A process table answering the `ps` calls the reaper makes, and dropping
/// members when the signal they die on reaches them.
final class _FakeProcessTable {
  _FakeProcessTable(
    Map<int, int> groups, {
    this.diesOn = ProcessSignal.sigterm,
    this.listingFails = false,
    Set<int> zombies = const <int>{},
    Map<int, int> lingerPolls = const <int, int>{},
    Map<int, int> ageSeconds = const <int, int>{},
  })  : _groups = Map<int, int>.of(groups),
        _zombies = Set<int>.of(zombies),
        _lingerPolls = Map<int, int>.of(lingerPolls),
        _ageSeconds = Map<int, int>.of(ageSeconds);

  static const int selfPid = 7;
  static const int ownPgid = 50;

  final Map<int, int> _groups;
  final Set<int> _zombies;
  final Map<int, int> _lingerPolls;
  final Map<int, int> _ageSeconds;

  /// The signal that ends a member, or null when nothing does.
  final ProcessSignal? diesOn;

  /// Whether `ps -A` fails, as it can on a host without procfs access.
  final bool listingFails;

  final List<(int, ProcessSignal)> signals = <(int, ProcessSignal)>[];
  final Set<int> _dying = <int>{};

  Set<int> get live => _groups.keys.toSet();

  bool kill(int target, ProcessSignal signal) {
    signals.add((target, signal));
    final List<int> victims = target < 0
        ? _groups.entries
            .where((MapEntry<int, int> e) => e.value == -target)
            .map((MapEntry<int, int> e) => e.key)
            .toList()
        : _groups.keys.where((int pid) => pid == target).toList();
    if (victims.isEmpty) return false;
    final bool fatal =
        diesOn != null && (signal == diesOn || signal == ProcessSignal.sigkill);
    if (fatal) {
      for (final int pid in victims) {
        if (_zombies.contains(pid)) continue;
        if ((_lingerPolls[pid] ?? 0) > 0) {
          _dying.add(pid);
        } else {
          _groups.remove(pid);
        }
      }
    }
    return true;
  }

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (executable != 'ps') throw StateError('unexpected $executable');
    _advance();
    final String argv = arguments.join(' ');
    if (argv == '-A -o pgid=,stat=') {
      if (listingFails) return ProcessResult(0, 1, '', 'ps: no access');
      return ProcessResult(
        0,
        0,
        <String>[
          '  $ownPgid Ss',
          for (final MapEntry<int, int> e in _groups.entries)
            '  ${e.value} ${_stat(e.key)}',
        ].join('\n'),
        '',
      );
    }
    if (arguments.length == 4 && arguments[0] == '-o' && arguments[2] == '-p') {
      final int pid = int.parse(arguments[3]);
      if (pid == selfPid && arguments[1] == 'pgid=') {
        return ProcessResult(0, 0, '  $ownPgid\n', '');
      }
      final int? pgid = _groups[pid];
      if (pgid == null) return ProcessResult(0, 1, '', '');
      return switch (arguments[1]) {
        'pgid=' => ProcessResult(0, 0, '  $pgid\n', ''),
        'stat=' => ProcessResult(0, 0, '${_stat(pid)}\n', ''),
        'etime=' =>
          ProcessResult(0, 0, '${_etime(_ageSeconds[pid] ?? 0)}\n', ''),
        _ => throw StateError('unexpected ps $argv'),
      };
    }
    throw StateError('unexpected ps $argv');
  }

  String _stat(int pid) => _zombies.contains(pid) ? 'Z' : 'S';

  /// `[[dd-]hh:]mm:ss`, the shape both BSD and procps `ps` print.
  static String _etime(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    final int days = seconds ~/ 86400;
    final int hours = seconds % 86400 ~/ 3600;
    final String clock = '${two(seconds % 3600 ~/ 60)}:${two(seconds % 60)}';
    if (days > 0) return '$days-${two(hours)}:$clock';
    if (hours > 0) return '${two(hours)}:$clock';
    return clock;
  }

  void _advance() {
    for (final int pid in _dying.toList()) {
      final int left = (_lingerPolls[pid] ?? 1) - 1;
      _lingerPolls[pid] = left;
      if (left <= 0) {
        _dying.remove(pid);
        _groups.remove(pid);
      }
    }
  }
}
