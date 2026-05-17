import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

/// Fake [PromptDriver] that records every method invocation but returns
/// fixed responses. Used to assert that [InstallContext] exposes the
/// injected driver verbatim (no wrapper).
class _RecordingPromptDriver implements PromptDriver {
  final List<String> log = <String>[];

  @override
  String ask(
    String question, {
    String? defaultValue,
    String? Function(String)? validator,
  }) {
    log.add('ask:$question');
    return defaultValue ?? '';
  }

  @override
  bool confirm(String question, {bool defaultValue = false}) {
    log.add('confirm:$question');
    return defaultValue;
  }

  @override
  String choice(
    String question, {
    required List<String> options,
    String? defaultValue,
  }) {
    log.add('choice:$question');
    return defaultValue ?? options.first;
  }

  @override
  String secret(String question) {
    log.add('secret:$question');
    return '';
  }
}

/// Fake [StubDriver] that maps stub names to fixture strings, recording
/// every load + replace call for assertion purposes.
class _RecordingStubDriver implements StubDriver {
  final Map<String, String> fixtures;
  final List<String> log = <String>[];

  _RecordingStubDriver(this.fixtures);

  @override
  String load(String name, {List<String>? searchPaths}) {
    log.add('load:$name');
    final raw = fixtures[name];
    if (raw == null) {
      throw ArgumentError('No fixture for $name.');
    }
    return raw;
  }

  @override
  String replace(String stub, Map<String, String> replacements) {
    log.add('replace');
    var out = stub;
    for (final entry in replacements.entries) {
      out = out.replaceAll('{{ ${entry.key} }}', entry.value);
    }
    return out;
  }

  @override
  String make(String name, Map<String, String> replacements) =>
      replace(load(name), replacements);
}

void main() {
  group('InstallContext.test()', () {
    test('exposes injected fs / prompt / stubs / projectRoot via getters', () {
      final fs = InMemoryFs();
      final prompt = _RecordingPromptDriver();
      final stubs = _RecordingStubDriver(const {});

      final ctx = InstallContext.test(
        fs: fs,
        prompt: prompt,
        stubs: stubs,
        projectRoot: '/virtual/project',
      );

      expect(identical(ctx.fs, fs), isTrue);
      expect(identical(ctx.prompt, prompt), isTrue);
      expect(identical(ctx.stubs, stubs), isTrue);
      expect(ctx.projectRoot, '/virtual/project');
    });

    test('defaults projectRoot to /test when not supplied', () {
      final ctx = InstallContext.test(
        fs: InMemoryFs(),
        prompt: _RecordingPromptDriver(),
        stubs: _RecordingStubDriver(const {}),
      );

      expect(ctx.projectRoot, '/test');
    });

    test('uses the injected clock callback when present', () {
      final fixed = DateTime.utc(2025, 1, 1, 12, 0, 0);

      final ctx = InstallContext.test(
        fs: InMemoryFs(),
        prompt: _RecordingPromptDriver(),
        stubs: _RecordingStubDriver(const {}),
        clock: () => fixed,
      );

      expect(ctx.clock(), fixed);
      expect(ctx.clock(), fixed);
    });

    test('defaults clock to DateTime.now when not supplied', () {
      final before = DateTime.now();
      final ctx = InstallContext.test(
        fs: InMemoryFs(),
        prompt: _RecordingPromptDriver(),
        stubs: _RecordingStubDriver(const {}),
      );
      final sampled = ctx.clock();
      final after = DateTime.now();

      expect(
        sampled.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        sampled.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test(
        'constructs a bare ArtisanContext with MapInput + BufferedOutput when input/output not supplied',
        () {
      final ctx = InstallContext.test(
        fs: InMemoryFs(),
        prompt: _RecordingPromptDriver(),
        stubs: _RecordingStubDriver(const {}),
      );

      expect(ctx.artisanContext, isA<ArtisanContext>());
      expect(ctx.artisanContext.input, isA<MapInput>());
      expect(ctx.artisanContext.output, isA<BufferedOutput>());
      expect(ctx.artisanContext.vmClient, isNull);
    });

    test('honours injected input + output when supplied', () {
      final input = MapInput(<String, dynamic>{'flag': true});
      final output = BufferedOutput();

      final ctx = InstallContext.test(
        fs: InMemoryFs(),
        prompt: _RecordingPromptDriver(),
        stubs: _RecordingStubDriver(const {}),
        input: input,
        output: output,
      );

      expect(identical(ctx.artisanContext.input, input), isTrue);
      expect(identical(ctx.artisanContext.output, output), isTrue);
    });

    test('exposes the injected driver instances unchanged (no wrapping)', () {
      final prompt = _RecordingPromptDriver();
      final stubs = _RecordingStubDriver(const {'greet': 'Hello {{ name }}'});

      final ctx = InstallContext.test(
        fs: InMemoryFs(),
        prompt: prompt,
        stubs: stubs,
      );

      ctx.prompt.ask('What is your name?');
      ctx.stubs.make('greet', const {'name': 'World'});

      expect(prompt.log, contains('ask:What is your name?'));
      expect(stubs.log, contains('load:greet'));
    });
  });

  group('InstallContext.real()', () {
    test(
        'wires production drivers (RealFs / RealPromptDriver / RealStubDriver)',
        () {
      final artisanCtx = ArtisanContext.bare(
        MapInput(const <String, dynamic>{}),
        BufferedOutput(),
      );

      final ctx = InstallContext.real(
        artisanCtx,
        projectRoot: '/explicit/root',
      );

      expect(ctx.fs, isA<RealFs>());
      expect(ctx.prompt, isA<RealPromptDriver>());
      expect(ctx.stubs, isA<RealStubDriver>());
      expect(ctx.projectRoot, '/explicit/root');
      expect(identical(ctx.artisanContext, artisanCtx), isTrue);
    });

    test('uses DateTime.now as the default clock', () {
      final artisanCtx = ArtisanContext.bare(
        MapInput(const <String, dynamic>{}),
        BufferedOutput(),
      );

      final ctx = InstallContext.real(
        artisanCtx,
        projectRoot: '/explicit/root',
      );

      final before = DateTime.now();
      final sampled = ctx.clock();
      final after = DateTime.now();

      expect(
        sampled.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        sampled.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test(
        'resolves projectRoot via FileHelper.findProjectRoot when not supplied',
        () {
      // The dart test runner cwd is the package root which DOES contain a
      // pubspec.yaml, so FileHelper.findProjectRoot() returns a valid path.
      final artisanCtx = ArtisanContext.bare(
        MapInput(const <String, dynamic>{}),
        BufferedOutput(),
      );

      final ctx = InstallContext.real(artisanCtx);

      expect(ctx.projectRoot, FileHelper.findProjectRoot());
    });
  });

  group('field contract parity', () {
    test('both factories produce instances exposing the same six fields', () {
      final real = InstallContext.real(
        ArtisanContext.bare(
          MapInput(const <String, dynamic>{}),
          BufferedOutput(),
        ),
        projectRoot: '/fake/root',
      );
      final fake = InstallContext.test(
        fs: InMemoryFs(),
        prompt: _RecordingPromptDriver(),
        stubs: _RecordingStubDriver(const {}),
        projectRoot: '/test',
      );

      // The compiler enforces that every field is final + non-nullable; this
      // test simply asserts both instances honour the same getter surface.
      for (final ctx in <InstallContext>[real, fake]) {
        expect(ctx.fs, isA<VirtualFs>());
        expect(ctx.prompt, isA<PromptDriver>());
        expect(ctx.stubs, isA<StubDriver>());
        expect(ctx.clock(), isA<DateTime>());
        expect(ctx.projectRoot, isNotEmpty);
        expect(ctx.artisanContext, isA<ArtisanContext>());
      }
    });
  });
}
