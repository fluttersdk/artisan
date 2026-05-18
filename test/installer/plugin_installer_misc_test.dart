import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only driver fakes (NOT exported from lib/).
// ---------------------------------------------------------------------------

/// Recording [PromptDriver] that returns canned answers in order and notes
/// which questions were asked. Lets tests prove IMMEDIATE prompts fire at
/// chain-method call time.
class _RecordingPromptDriver implements PromptDriver {
  _RecordingPromptDriver({
    List<String> askAnswers = const <String>[],
    List<bool> confirmAnswers = const <bool>[],
    List<String> choiceAnswers = const <String>[],
  })  : _ask = List<String>.from(askAnswers),
        _confirm = List<bool>.from(confirmAnswers),
        _choice = List<String>.from(choiceAnswers);

  final List<String> _ask;
  final List<bool> _confirm;
  final List<String> _choice;
  final List<String> askedQuestions = <String>[];
  final List<String> confirmedQuestions = <String>[];
  final List<String> choiceQuestions = <String>[];

  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) {
    askedQuestions.add(question);
    if (_ask.isNotEmpty) return _ask.removeAt(0);
    return defaultValue ?? '';
  }

  @override
  bool confirm(String question, {bool defaultValue = false}) {
    confirmedQuestions.add(question);
    if (_confirm.isNotEmpty) return _confirm.removeAt(0);
    return defaultValue;
  }

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) {
    choiceQuestions.add(question);
    if (_choice.isNotEmpty) return _choice.removeAt(0);
    return defaultValue ?? options.first;
  }

  @override
  String secret(String question) => '';
}

class _SilentStubDriver implements StubDriver {
  @override
  String load(String name, {List<String>? searchPaths}) => '';

  @override
  String replace(String stub, Map<String, String> replacements) => stub;

  @override
  String make(String name, Map<String, String> replacements) => '';
}

InstallContext _ctxFor(Directory tempDir, {PromptDriver? prompt}) {
  return InstallContext.test(
    fs: const RealFs(),
    prompt: prompt ?? _RecordingPromptDriver(),
    stubs: _SilentStubDriver(),
    projectRoot: tempDir.path,
  );
}

// ---------------------------------------------------------------------------
// Fixture writers
// ---------------------------------------------------------------------------

void _writeWebIndex(Directory root) {
  final path = p.join(root.path, 'web', 'index.html');
  File(path).createSync(recursive: true);
  File(path).writeAsStringSync('''
<!DOCTYPE html>
<html>
<head>
  <title>app</title>
</head>
<body>
  <div id="app"></div>
</body>
</html>
''');
}

void main() {
  group('PluginInstaller — interactive (IMMEDIATE) chain methods', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_misc_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('ask fires the prompt synchronously and stores answer in vars', () {
      final prompt =
          _RecordingPromptDriver(askAnswers: const <String>['my_log_path']);
      final installer = PluginInstaller(
        _ctxFor(tempDir, prompt: prompt),
        pluginName: 'demo',
      );

      final chained = installer.ask(
        varName: 'logPath',
        question: 'Log path?',
        defaultValue: '/tmp/x',
      );

      expect(chained, same(installer));
      expect(prompt.askedQuestions, ['Log path?']);
      expect(installer.vars['logPath'], 'my_log_path');
      // No op enqueued by ask.
      expect(installer.pendingCount, 0);
    });

    test('confirm stores true / false as strings', () {
      final prompt = _RecordingPromptDriver(confirmAnswers: const [true]);
      final installer = PluginInstaller(
        _ctxFor(tempDir, prompt: prompt),
        pluginName: 'demo',
      ).confirm(varName: 'wantThing', question: 'Want it?');

      expect(installer.vars['wantThing'], 'true');
    });

    test('confirm stores false correctly', () {
      final prompt = _RecordingPromptDriver(confirmAnswers: const [false]);
      final installer = PluginInstaller(
        _ctxFor(tempDir, prompt: prompt),
        pluginName: 'demo',
      ).confirm(varName: 'wantThing', question: 'Want it?');

      expect(installer.vars['wantThing'], 'false');
    });

    test('choice stores the selected option', () {
      final prompt = _RecordingPromptDriver(choiceAnswers: const ['debug']);
      final installer = PluginInstaller(
        _ctxFor(tempDir, prompt: prompt),
        pluginName: 'demo',
      ).choice(
        varName: 'level',
        question: 'Log level?',
        options: const ['debug', 'info', 'warn'],
      );

      expect(installer.vars['level'], 'debug');
    });

    test('vars returns an unmodifiable view', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .ask(varName: 'k', question: 'q', defaultValue: 'v');
      expect(installer.vars, {'k': 'v'});
      expect(() => installer.vars['injected'] = 'x', throwsUnsupportedError);
    });

    test('vars are visible inside a chain so subsequent ops can branch', () {
      final prompt = _RecordingPromptDriver(askAnswers: const ['production']);
      final installer = PluginInstaller(
        _ctxFor(tempDir, prompt: prompt),
        pluginName: 'demo',
      ).ask(varName: 'mode', question: 'Mode?');

      // Plain Dart `if` over installer.vars[...] — no dedicated askIf helper.
      if (installer.vars['mode'] == 'production') {
        installer.writeFile(
          targetPath: 'lib/prod_only.dart',
          content: '// prod',
        );
      }
      expect(installer.pendingCount, 1);
    });
  });

  group('PluginInstaller — shell + askToRunShell', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_misc_shell_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('runShell enqueues RunShell with args and workingDir', () {
      final installer =
          PluginInstaller(_ctxFor(tempDir), pluginName: 'demo').runShell(
        command: 'flutter',
        args: const ['pub', 'get'],
        workingDir: 'packages/x',
      );
      final op = installer.pendingOps.single as RunShell;
      expect(op.command, 'flutter');
      expect(op.args, ['pub', 'get']);
      expect(op.workingDir, 'packages/x');
    });

    test('askToRunShell enqueues RunShell only when confirm=true', () {
      final prompt = _RecordingPromptDriver(confirmAnswers: const [true]);
      final installer = PluginInstaller(
        _ctxFor(tempDir, prompt: prompt),
        pluginName: 'demo',
      ).askToRunShell(
        prompt: 'Run pub get?',
        command: 'flutter',
        args: const ['pub', 'get'],
      );

      expect(installer.pendingCount, 1);
      final op = installer.pendingOps.single as RunShell;
      expect(op.command, 'flutter');
    });

    test('askToRunShell does NOT enqueue when confirm=false', () {
      final prompt = _RecordingPromptDriver(confirmAnswers: const [false]);
      final installer = PluginInstaller(
        _ctxFor(tempDir, prompt: prompt),
        pluginName: 'demo',
      ).askToRunShell(
        prompt: 'Run pub get?',
        command: 'flutter',
        args: const ['pub', 'get'],
      );

      expect(installer.pendingCount, 0);
    });

    test(
        'runShell dispatcher invokes the command and lands Success when '
        'exit code is 0', () async {
      // Use a deliberately portable echo equivalent. On POSIX `true` exits 0.
      // Skip on Windows where /bin/true is absent.
      if (Platform.isWindows) return;
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .runShell(command: 'true');

      final result = await installer.commit();
      expect(result, isA<Success>());
    });

    test('runShell dispatcher surfaces Error when exit code is non-zero',
        () async {
      if (Platform.isWindows) return;
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .runShell(command: 'false');

      final result = await installer.commit();
      expect(result, isA<Error>());
      expect((result as Error).error, contains('RunShell failed'));
    });
  });

  group('PluginInstaller — env', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_misc_env_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectEnvVar enqueues InjectEnvVar', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectEnvVar(key: 'API_KEY', value: 'secret');
      final op = installer.pendingOps.single as InjectEnvVar;
      expect(op.key, 'API_KEY');
      expect(op.value, 'secret');
    });

    test('injectEnvVar dispatcher creates .env when missing', () async {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectEnvVar(key: 'API_KEY', value: 'secret');

      final result = await installer.commit();
      expect(result, isA<Success>());
      final env = File(p.join(tempDir.path, '.env')).readAsStringSync();
      expect(env, contains('API_KEY=secret'));
    });

    test('injectEnvVar dispatcher updates existing key in-place', () async {
      // Pre-populate .env.
      File(p.join(tempDir.path, '.env')).writeAsStringSync('API_KEY=old\n');

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectEnvVar(key: 'API_KEY', value: 'new');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final env = File(p.join(tempDir.path, '.env')).readAsStringSync();
      expect(env, contains('API_KEY=new'));
      expect(env, isNot(contains('API_KEY=old')));
    });
  });

  group('PluginInstaller — web', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plinst_misc_web_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('injectIntoWebHead / addWebMetaTag enqueue ops', () {
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectIntoWebHead('<script src="x.js"></script>')
          .addWebMetaTag(const {'name': 'viewport', 'content': 'w=d-w'});

      expect(installer.pendingCount, 2);
      expect(installer.pendingOps[0], isA<InjectIntoWebHead>());
      expect(installer.pendingOps[1], isA<AddWebMetaTag>());
    });

    test('injectIntoWebHead dispatcher writes before </head> when web present',
        () async {
      _writeWebIndex(tempDir);

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectIntoWebHead('<script src="app.js"></script>');

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final html =
          File(p.join(tempDir.path, 'web', 'index.html')).readAsStringSync();
      expect(html, contains('<script src="app.js"></script>'));
      expect(html.indexOf('<script src="app.js"></script>'),
          lessThan(html.indexOf('</head>')));
    });

    test('addWebMetaTag dispatcher writes <meta> tag when web present',
        () async {
      _writeWebIndex(tempDir);

      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .addWebMetaTag(
              const {'name': 'description', 'content': 'A test app'});

      final result = await installer.commit(force: true);
      expect(result, isA<Success>());
      final html =
          File(p.join(tempDir.path, 'web', 'index.html')).readAsStringSync();
      expect(html, contains('name="description"'));
      expect(html, contains('content="A test app"'));
    });

    test('web ops are silent no-ops on non-web projects', () async {
      // No web/ dir.
      final installer = PluginInstaller(_ctxFor(tempDir), pluginName: 'demo')
          .injectIntoWebHead('<script></script>');

      final result = await installer.commit();
      expect(result, isA<Success>());
      expect(Directory(p.join(tempDir.path, 'web')).existsSync(), isFalse);
    });
  });
}
