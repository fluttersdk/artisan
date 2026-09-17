import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A pattern injection that matches nothing used to write nothing and return
/// normally, so the caller could not tell an applied injection from a skipped
/// one and an install reported Success either way.
///
/// The consequence was measured in a consumer app: `injectProvider` writes an
/// `InjectAfterPattern` whose regex requires the parameter list to be exactly
/// `(app)`, so a `lib/config/app.dart` written as
/// `(MagicApp app) => AppServiceProvider(app),` never matched. The provider
/// was never registered, the plugin never booted, and `plugin:install`
/// reported Success.
void main() {
  group('the pattern helpers report whether they matched', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_match_report_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('insertCodeAfterPattern answers true when it wrote', () {
      final filePath = p.join(tempDir.path, 'after_hit.dart');
      File(filePath).writeAsStringSync('A\nMARK\nC\n');

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: 'MARK',
        code: '\nB-after',
      );

      expect(applied, isTrue);
      expect(File(filePath).readAsStringSync(), contains('B-after'));
    });

    test('insertCodeAfterPattern answers false when nothing matched', () {
      final filePath = p.join(tempDir.path, 'after_miss.dart');
      File(filePath).writeAsStringSync('A\nC\n');

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: 'NOT-IN-THE-FILE',
        code: '\nB-after',
      );

      expect(applied, isFalse);
      expect(File(filePath).readAsStringSync(), 'A\nC\n');
    });

    test('insertCodeBeforePattern answers true when it wrote', () {
      final filePath = p.join(tempDir.path, 'before_hit.dart');
      File(filePath).writeAsStringSync('A\nMARK\nC\n');

      final applied = ConfigEditor.insertCodeBeforePattern(
        filePath: filePath,
        pattern: 'MARK',
        code: 'B-before\n',
      );

      expect(applied, isTrue);
      expect(File(filePath).readAsStringSync(), contains('B-before'));
    });

    test('insertCodeBeforePattern answers false when nothing matched', () {
      final filePath = p.join(tempDir.path, 'before_miss.dart');
      File(filePath).writeAsStringSync('A\nC\n');

      final applied = ConfigEditor.insertCodeBeforePattern(
        filePath: filePath,
        pattern: 'NOT-IN-THE-FILE',
        code: 'B-before\n',
      );

      expect(applied, isFalse);
      expect(File(filePath).readAsStringSync(), 'A\nC\n');
    });

    test('an idempotent skip answers true, because the code IS there', () {
      // The distinction the return value has to carry: "already applied" is a
      // success, "never matched" is a failure. Collapsing them would make a
      // re-run of `plugin:install` fail on work it had already done.
      final filePath = p.join(tempDir.path, 'idempotent.dart');
      File(filePath).writeAsStringSync('MARK\ninjected_code\n');

      final applied = ConfigEditor.insertCodeAfterPattern(
        filePath: filePath,
        pattern: 'MARK',
        code: '\ninjected_code\n',
      );

      expect(applied, isTrue);
      expect(File(filePath).readAsStringSync(), 'MARK\ninjected_code\n');
    });
  });
}
