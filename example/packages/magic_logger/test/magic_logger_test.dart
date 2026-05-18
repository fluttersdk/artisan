import 'dart:convert';
import 'dart:io';

import 'package:magic_logger/cli.dart';
import 'package:magic_logger/magic_logger.dart';
import 'package:test/test.dart';

void main() {
  group('MagicLoggerArtisanProvider', () {
    final provider = MagicLoggerArtisanProvider();

    test('providerName is "magic_logger"', () {
      expect(provider.providerName, 'magic_logger');
    });

    test('commands() returns 4 entries (install/uninstall/tail/level)', () {
      expect(provider.commands(), hasLength(4));
    });

    test('exposes the canonical command names via signatures', () {
      final names = provider.commands().map((c) => c.name).toSet();
      expect(
        names,
        containsAll(<String>[
          'logger:install',
          'logger:uninstall',
          'logger:tail',
          'logger:level',
        ]),
      );
    });
  });

  group('Commands, signature shape', () {
    test(
        'logger:install declares --force / --non-interactive / --level / --path',
        () {
      final sig = LoggerInstallCommand().parsedSignature!;
      final optionNames = sig.options.map((o) => o.name).toSet();
      expect(
        optionNames,
        containsAll(<String>['force', 'non-interactive', 'level', 'path']),
      );
    });

    test('logger:tail declares --file / --lines / --follow', () {
      final sig = LoggerTailCommand().parsedSignature!;
      final optionNames = sig.options.map((o) => o.name).toSet();
      expect(
        optionNames,
        containsAll(<String>['file', 'lines', 'follow']),
      );
    });

    test('logger:level takes one optional positional arg "level"', () {
      final sig = LoggerLevelCommand().parsedSignature!;
      expect(sig.arguments, hasLength(1));
      expect(sig.arguments.first.name, 'level');
      expect(sig.arguments.first.isOptional, isTrue);
    });
  });

  group('MagicLogger runtime', () {
    late Directory tempDir;
    late String logPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_logger_test_');
      logPath = '${tempDir.path}/test.log';
      MagicLogger.logFilePath = logPath;
      MagicLogger.minLevel = LogLevel.debug;
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('writes a JSON-line entry per call', () {
      MagicLogger.info('hello');
      final lines = File(logPath).readAsLinesSync();
      expect(lines, hasLength(1));
      final entry = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(entry['level'], 'info');
      expect(entry['message'], 'hello');
      expect(entry['ts'], isA<String>());
    });

    test('attaches context map when provided', () {
      MagicLogger.warn('alarm', context: {'severity': 'mid', 'count': 3});
      final entry = jsonDecode(File(logPath).readAsLinesSync().first)
          as Map<String, dynamic>;
      expect(entry['context'], {'severity': 'mid', 'count': 3});
    });

    test('omits context key when not provided', () {
      MagicLogger.debug('quiet');
      final entry = jsonDecode(File(logPath).readAsLinesSync().first)
          as Map<String, dynamic>;
      expect(entry.containsKey('context'), isFalse);
    });

    test('filters entries below minLevel', () {
      MagicLogger.minLevel = LogLevel.warn;
      MagicLogger.debug('hidden');
      MagicLogger.info('also hidden');
      MagicLogger.warn('visible');
      MagicLogger.error('also visible');
      final lines = File(logPath).readAsLinesSync();
      expect(lines, hasLength(2));
      expect(lines.first, contains('"level":"warn"'));
      expect(lines.last, contains('"level":"error"'));
    });

    test('appends to existing file instead of overwriting', () {
      MagicLogger.info('first');
      MagicLogger.info('second');
      expect(File(logPath).readAsLinesSync(), hasLength(2));
    });
  });

  group('LogLevel.parse', () {
    test('case-insensitive', () {
      expect(LogLevel.parse('DEBUG'), LogLevel.debug);
      expect(LogLevel.parse('Info'), LogLevel.info);
      expect(LogLevel.parse('warn'), LogLevel.warn);
      expect(LogLevel.parse('Error'), LogLevel.error);
    });

    test('throws ArgumentError on unknown level', () {
      expect(() => LogLevel.parse('fatal'), throwsArgumentError);
    });
  });
}
