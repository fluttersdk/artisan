import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cli/src/commands/install_command.dart';

/// ----------------------------------------------------------------------------
/// TDD RED PHASE: install_command_test.dart
/// ----------------------------------------------------------------------------
/// This file tests the heavily overhauled `magic install` command.
/// At the time of writing, the `InstallCommand` implementation has NOT been
/// updated to pass these tests. This is expected.
///
/// The overhauled command requires:
/// 1. 7 configs (app, auth, database, network, view, cache, logging)
/// 2. kernel.dart for middleware registration
/// 3. welcome_view.dart with Wind UI
/// 4. Full main.dart replacement (not injection) using MagicApplication
/// 5. .env and .env.example files
/// ----------------------------------------------------------------------------

/// Testable subclass — injects temp project root to avoid hitting real filesystem.
class _TestInstallCommand extends InstallCommand {
  _TestInstallCommand(this._testRoot);

  final String _testRoot;

  @override
  String getProjectRoot() => _testRoot;
}

/// Test subclass that stubs file downloads to avoid real HTTP requests.
class _TestInstallCommandWithDownload extends InstallCommand {
  _TestInstallCommandWithDownload(this._testRoot);

  final String _testRoot;

  /// Whether [downloadFile] was called during the test.
  bool downloadFileCalled = false;

  /// The URL passed to [downloadFile].
  Uri? downloadFileUrl;

  /// Whether the simulated download should succeed.
  bool simulateDownloadSuccess = true;

  @override
  String getProjectRoot() => _testRoot;

  @override
  Future<bool> downloadFile(Uri url, String targetPath) async {
    downloadFileCalled = true;
    downloadFileUrl = url;

    if (simulateDownloadSuccess) {
      // Create a dummy file to simulate a successful download.
      final file = File(targetPath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsBytesSync([0x00, 0x61, 0x73, 0x6D]); // WASM magic bytes
      return true;
    }

    return false;
  }
}

/// Creates a minimal Flutter project scaffold in the given directory.
void _createMinimalFlutterProject(Directory dir) {
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
description: A test Flutter project.
version: 1.0.0+1

environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
''');

  Directory('${dir.path}/lib').createSync(recursive: true);
  File('${dir.path}/lib/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold()));
}
''');
}

void main() {
  group('InstallCommand', () {
    late Directory tempDir;
    late _TestInstallCommand cmd;
    late ArgParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('magic_test_install_');
      _createMinimalFlutterProject(tempDir);

      cmd = _TestInstallCommand(tempDir.path);
      parser = ArgParser();

      // We manually add the new flags here to the test parser so we can parse them,
      // even if the command hasn't implemented configure() for them yet.
      // This ensures the test compiles and can pass arguments.
      cmd.configure(parser);
      if (!parser.options.containsKey('without-network')) {
        parser.addFlag('without-network',
            help: 'Skip network setup', negatable: false);
      }
      if (!parser.options.containsKey('without-logging')) {
        parser.addFlag('without-logging',
            help: 'Skip logging setup', negatable: false);
      }
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Group 1: Default install (no flags)
    // -----------------------------------------------------------------------
    group('Default install (no flags)', () {
      setUp(() async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();
      });

      test('creates all expected app directories', () {
        final expectedDirs = [
          'lib/app/controllers',
          'lib/app/models',
          'lib/app/enums',
          'lib/app/middleware',
          'lib/app/policies',
          'lib/app/providers',
          'lib/app/listeners',
          'lib/app/events',
          'lib/resources/views',
          'lib/routes',
          'lib/config',
        ];

        for (final dir in expectedDirs) {
          expect(
            Directory('${tempDir.path}/$dir').existsSync(),
            isTrue,
            reason: '$dir should exist after default install',
          );
        }
      });

      test('creates database directories', () {
        final dbDirs = [
          'lib/database/migrations',
          'lib/database/seeders',
          'lib/database/factories',
        ];

        for (final dir in dbDirs) {
          expect(
            Directory('${tempDir.path}/$dir').existsSync(),
            isTrue,
            reason: '$dir should exist after default install',
          );
        }
      });

      test('creates assets/lang directory', () {
        expect(
          Directory('${tempDir.path}/assets/lang').existsSync(),
          isTrue,
          reason: 'assets/lang should exist after default install',
        );
      });

      test('creates all 9 config files', () {
        final configs = [
          'app.dart',
          'auth.dart',
          'database.dart',
          'network.dart',
          'routing.dart',
          'view.dart',
          'cache.dart',
          'logging.dart',
          'broadcasting.dart',
        ];

        for (final config in configs) {
          expect(
            File('${tempDir.path}/lib/config/$config').existsSync(),
            isTrue,
            reason: 'lib/config/$config should exist after default install',
          );
        }
      });

      test('creates starter providers', () {
        expect(
          File('${tempDir.path}/lib/app/providers/route_service_provider.dart')
              .existsSync(),
          isTrue,
          reason: 'route_service_provider.dart should exist',
        );
        expect(
          File('${tempDir.path}/lib/app/providers/app_service_provider.dart')
              .existsSync(),
          isTrue,
          reason: 'app_service_provider.dart should exist',
        );
      });

      test('creates kernel.dart', () {
        expect(
          File('${tempDir.path}/lib/app/kernel.dart').existsSync(),
          isTrue,
          reason: 'kernel.dart should exist',
        );
      });

      test('creates routes/app.dart', () {
        expect(
          File('${tempDir.path}/lib/routes/app.dart').existsSync(),
          isTrue,
          reason: 'routes/app.dart should exist',
        );
      });

      test('creates welcome_view.dart', () {
        expect(
          File('${tempDir.path}/lib/resources/views/welcome_view.dart')
              .existsSync(),
          isTrue,
          reason: 'welcome_view.dart should exist',
        );
      });

      test('creates .env and .env.example files', () {
        expect(
          File('${tempDir.path}/.env').existsSync(),
          isTrue,
          reason: '.env should exist',
        );
        expect(
          File('${tempDir.path}/.env.example').existsSync(),
          isTrue,
          reason: '.env.example should exist',
        );
      });

      test('includes broadcasting env vars in .env', () {
        final content = File('${tempDir.path}/.env').readAsStringSync();

        expect(
          content,
          contains('BROADCAST_CONNECTION'),
          reason: '.env should contain BROADCAST_CONNECTION',
        );
        expect(
          content,
          contains('REVERB_HOST'),
          reason: '.env should contain REVERB_HOST',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 1.1: widget_test.dart compatibility patch
    // -----------------------------------------------------------------------
    group('widget_test.dart compatibility patch', () {
      test('replaces Flutter default MyApp test with Magic smoke test',
          () async {
        final widgetTestFile = File('${tempDir.path}/test/widget_test.dart');
        widgetTestFile.parent.createSync(recursive: true);
        widgetTestFile.writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_app/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('0'), findsOneWidget);
  });
}
''');

        cmd.arguments = parser.parse([]);
        await cmd.handle();

        final patchedContent = widgetTestFile.readAsStringSync();
        expect(
          patchedContent,
          contains('Magic app boots smoke test'),
        );
        expect(
          patchedContent,
          contains('MagicApplication'),
        );
        expect(
          patchedContent,
          isNot(contains('const MyApp()')),
        );
      });

      test('does not overwrite customized widget tests', () async {
        final widgetTestFile = File('${tempDir.path}/test/widget_test.dart');
        widgetTestFile.parent.createSync(recursive: true);
        widgetTestFile.writeAsStringSync('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('custom app test', (WidgetTester tester) async {
    expect(1, 1);
  });
}
''');

        final originalContent = widgetTestFile.readAsStringSync();

        cmd.arguments = parser.parse([]);
        await cmd.handle();

        final afterInstallContent = widgetTestFile.readAsStringSync();
        expect(afterInstallContent, equals(originalContent));
      });
    });

    // -----------------------------------------------------------------------
    // Group 2: main.dart replacement
    // -----------------------------------------------------------------------
    group('main.dart replacement', () {
      test('replaces main.dart content completely', () async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        expect(
          content,
          contains('MagicApplication'),
          reason: 'main.dart should use MagicApplication',
        );

        expect(
          content,
          isNot(contains('MaterialApp(home: Scaffold())')),
          reason: 'main.dart should NOT contain old Scaffold code',
        );

        expect(
          content,
          contains('await Magic.init'),
          reason: 'main.dart should contain Magic.init',
        );

        expect(
          content,
          contains('configFactories:'),
          reason: 'main.dart should contain configFactories list',
        );
      });

      test('imports all 9 configs by default', () async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        final expectedImports = [
          "import 'config/app.dart'",
          "import 'config/auth.dart'",
          "import 'config/database.dart'",
          "import 'config/network.dart'",
          "import 'config/routing.dart'",
          "import 'config/view.dart'",
          "import 'config/cache.dart'",
          "import 'config/logging.dart'",
          "import 'config/broadcasting.dart'",
        ];

        for (final imp in expectedImports) {
          expect(
            content,
            contains(imp),
            reason: 'main.dart should import $imp',
          );
        }
      });

      test('is idempotent (Magic.init appears exactly once)', () async {
        cmd.arguments = parser.parse([]);

        // Run first time
        await cmd.handle();

        // Run second time
        await cmd.handle();

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        final count = 'Magic.init'.allMatches(content).length;

        expect(
          count,
          1,
          reason:
              'Magic.init must appear exactly once even after multiple runs',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 3: --without-auth flag
    // -----------------------------------------------------------------------
    group('--without-auth flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-auth']);
        await cmd.handle();
      });

      test('skips auth.dart', () {
        expect(
          File('${tempDir.path}/lib/config/auth.dart').existsSync(),
          isFalse,
          reason: 'auth.dart should not be created',
        );
      });

      test('excludes auth providers from app.dart', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(
          content,
          isNot(contains('AuthServiceProvider')),
          reason: 'app.dart should not contain AuthServiceProvider',
        );
        expect(
          content,
          isNot(contains('VaultServiceProvider')),
          reason: 'app.dart should not contain VaultServiceProvider',
        );
      });

      test('creates remaining configs', () {
        expect(File('${tempDir.path}/lib/config/database.dart').existsSync(),
            isTrue);
        expect(File('${tempDir.path}/lib/config/network.dart').existsSync(),
            isTrue);
      });

      test('excludes auth config import from main.dart', () {
        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        expect(
          content,
          isNot(contains("import 'config/auth.dart'")),
          reason: 'main.dart should not import auth config',
        );
        expect(
          content,
          isNot(contains('authConfig')),
          reason: 'main.dart should not use authConfig factory',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 4: --without-database flag
    // -----------------------------------------------------------------------
    group('--without-database flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-database']);
        await cmd.handle();
      });

      test('skips database directories', () {
        expect(
          Directory('${tempDir.path}/lib/database').existsSync(),
          isFalse,
          reason: 'lib/database should not be created',
        );
      });

      test('skips database.dart', () {
        expect(
          File('${tempDir.path}/lib/config/database.dart').existsSync(),
          isFalse,
          reason: 'database.dart should not be created',
        );
      });

      test('excludes database provider from app.dart', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(
          content,
          isNot(contains('DatabaseServiceProvider')),
          reason: 'app.dart should not contain DatabaseServiceProvider',
        );
      });

      test('excludes database config import from main.dart', () {
        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        expect(
          content,
          isNot(contains("import 'config/database.dart'")),
          reason: 'main.dart should not import database config',
        );
        expect(
          content,
          isNot(contains('databaseConfig')),
          reason: 'main.dart should not use databaseConfig factory',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 5: --without-network flag
    // -----------------------------------------------------------------------
    group('--without-network flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-network']);
        await cmd.handle();
      });

      test('skips network.dart', () {
        expect(
          File('${tempDir.path}/lib/config/network.dart').existsSync(),
          isFalse,
          reason: 'network.dart should not be created',
        );
      });

      test('excludes network provider from app.dart', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(
          content,
          isNot(contains('NetworkServiceProvider')),
          reason: 'app.dart should not contain NetworkServiceProvider',
        );
      });

      test('excludes network config import from main.dart', () {
        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        expect(
          content,
          isNot(contains("import 'config/network.dart'")),
          reason: 'main.dart should not import network config',
        );
        expect(
          content,
          isNot(contains('networkConfig')),
          reason: 'main.dart should not use networkConfig factory',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 6: --without-cache flag
    // -----------------------------------------------------------------------
    group('--without-cache flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-cache']);
        await cmd.handle();
      });

      test('skips cache.dart', () {
        expect(
          File('${tempDir.path}/lib/config/cache.dart').existsSync(),
          isFalse,
          reason: 'cache.dart should not be created',
        );
      });

      test('excludes cache provider from app.dart', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(
          content,
          isNot(contains('CacheServiceProvider')),
          reason: 'app.dart should not contain CacheServiceProvider',
        );
      });

      test('excludes cache config import from main.dart', () {
        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        expect(
          content,
          isNot(contains("import 'config/cache.dart'")),
          reason: 'main.dart should not import cache config',
        );
        expect(
          content,
          isNot(contains('cacheConfig')),
          reason: 'main.dart should not use cacheConfig factory',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 7: --without-events flag
    // -----------------------------------------------------------------------
    group('--without-events flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-events']);
        await cmd.handle();
      });

      test('skips events directories', () {
        expect(
          Directory('${tempDir.path}/lib/app/events').existsSync(),
          isFalse,
          reason: 'app/events should not be created',
        );
        expect(
          Directory('${tempDir.path}/lib/app/listeners').existsSync(),
          isFalse,
          reason: 'app/listeners should not be created',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 8: --without-localization flag
    // -----------------------------------------------------------------------
    group('--without-localization flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-localization']);
        await cmd.handle();
      });

      test('skips assets/lang directory', () {
        expect(
          Directory('${tempDir.path}/assets/lang').existsSync(),
          isFalse,
          reason: 'assets/lang should not be created',
        );
      });

      test('excludes localization provider from app.dart', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(
          content,
          isNot(contains('LocalizationServiceProvider')),
          reason: 'app.dart should not contain LocalizationServiceProvider',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 9: --without-logging flag
    // -----------------------------------------------------------------------
    group('--without-logging flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-logging']);
        await cmd.handle();
      });

      test('skips logging.dart', () {
        expect(
          File('${tempDir.path}/lib/config/logging.dart').existsSync(),
          isFalse,
          reason: 'logging.dart should not be created',
        );
      });

      test('excludes logging config import from main.dart', () {
        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        expect(
          content,
          isNot(contains("import 'config/logging.dart'")),
          reason: 'main.dart should not import logging config',
        );
        expect(
          content,
          isNot(contains('loggingConfig')),
          reason: 'main.dart should not use loggingConfig factory',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 10: --without-broadcasting flag
    // -----------------------------------------------------------------------
    group('--without-broadcasting flag', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-broadcasting']);
        await cmd.handle();
      });

      test('skips broadcasting.dart', () {
        expect(
          File('${tempDir.path}/lib/config/broadcasting.dart').existsSync(),
          isFalse,
          reason: 'broadcasting.dart should not be created',
        );
      });

      test('excludes BroadcastServiceProvider from app.dart', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(
          content,
          isNot(contains('BroadcastServiceProvider')),
          reason: 'app.dart should not contain BroadcastServiceProvider',
        );
      });

      test('excludes broadcasting config import from main.dart', () {
        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();

        expect(
          content,
          isNot(contains("import 'config/broadcasting.dart'")),
          reason: 'main.dart should not import broadcasting config',
        );
        expect(
          content,
          isNot(contains('broadcastingConfig')),
          reason: 'main.dart should not use broadcastingConfig factory',
        );
      });

      test('excludes broadcasting env vars from .env', () {
        final content = File('${tempDir.path}/.env').readAsStringSync();

        expect(
          content,
          isNot(contains('BROADCAST_CONNECTION')),
          reason: '.env should not contain BROADCAST_CONNECTION',
        );
        expect(
          content,
          isNot(contains('REVERB_HOST')),
          reason: '.env should not contain REVERB_HOST',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 11: Combined flags (--without-auth --without-database)
    // -----------------------------------------------------------------------
    group('Combined flags (--without-auth --without-database)', () {
      setUp(() async {
        cmd.arguments = parser.parse(['--without-auth', '--without-database']);
        await cmd.handle();
      });

      test('skips multiple config files and directories', () {
        expect(
            File('${tempDir.path}/lib/config/auth.dart').existsSync(), isFalse);
        expect(File('${tempDir.path}/lib/config/database.dart').existsSync(),
            isFalse);
        expect(Directory('${tempDir.path}/lib/database').existsSync(), isFalse);
      });

      test('excludes multiple providers from app.dart', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(content, isNot(contains('AuthServiceProvider')));
        expect(content, isNot(contains('DatabaseServiceProvider')));
      });

      test('creates only 7 config files', () {
        final dir = Directory('${tempDir.path}/lib/config');
        final files = dir.listSync().whereType<File>().toList();

        expect(
          files.length,
          7,
          reason:
              'Should create exactly 7 config files (app, network, routing, view, cache, logging, broadcasting)',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 12: .env content
    // -----------------------------------------------------------------------
    group('.env content', () {
      setUp(() async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();
      });

      test('.env file contains required keys', () {
        final content = File('${tempDir.path}/.env').readAsStringSync();

        expect(content, contains('APP_NAME='));
        expect(content, contains('APP_ENV='));
        expect(content, contains('APP_DEBUG='));
        expect(content, contains('APP_KEY='));
      });

      test('.env.example matches .env keys', () {
        final content = File('${tempDir.path}/.env.example').readAsStringSync();

        expect(content, contains('APP_NAME='));
        expect(content, contains('APP_ENV='));
        expect(content, contains('APP_DEBUG='));
        expect(content, contains('APP_KEY='));
      });
    });

    // -----------------------------------------------------------------------
    // Group 13: Content verification
    // -----------------------------------------------------------------------
    group('Content verification', () {
      setUp(() async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();
      });

      test('app.dart contains standard providers', () {
        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();

        expect(content, contains('RouteServiceProvider'));
        expect(content, contains('AppServiceProvider'));
      });

      test('kernel.dart contains registerKernel method', () {
        final content =
            File('${tempDir.path}/lib/app/kernel.dart').readAsStringSync();

        expect(content, contains('void registerKernel()'));
      });

      test('routes/app.dart is configured correctly', () {
        final content =
            File('${tempDir.path}/lib/routes/app.dart').readAsStringSync();

        expect(content, contains("import 'package:magic/magic.dart'"));
        expect(content, contains('WelcomeView'));
      });

      test('welcome_view.dart uses Wind UI', () {
        final content =
            File('${tempDir.path}/lib/resources/views/welcome_view.dart')
                .readAsStringSync();

        expect(content, contains('WelcomeView'));
        expect(
          content,
          contains('WDiv'),
          reason: 'welcome_view.dart should use Wind UI components',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 14: Cache config uses FileStore instance
    // -----------------------------------------------------------------------
    group('Cache config uses FileStore instance', () {
      setUp(() async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();
      });

      test('cache.dart imports magic barrel', () {
        final content =
            File('${tempDir.path}/lib/config/cache.dart').readAsStringSync();

        expect(
          content,
          contains("import 'package:magic/magic.dart'"),
          reason: 'cache.dart should import magic barrel for FileStore',
        );
      });

      test('cache.dart uses FileStore() instance not string', () {
        final content =
            File('${tempDir.path}/lib/config/cache.dart').readAsStringSync();

        expect(
          content,
          contains('FileStore()'),
          reason: 'cache.dart driver should be FileStore() instance',
        );
        expect(
          content,
          isNot(contains("'file'")),
          reason: 'cache.dart should NOT use string driver',
        );
      });
    });

    // -----------------------------------------------------------------------
    // Group 15: .env registered as Flutter asset
    // -----------------------------------------------------------------------
    group('.env registered as Flutter asset', () {
      test('adds .env to flutter assets in pubspec.yaml', () async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();

        final content = File('${tempDir.path}/pubspec.yaml').readAsStringSync();

        expect(
          content,
          contains('.env'),
          reason: 'pubspec.yaml should contain .env in flutter assets',
        );
      });

      test('is idempotent — does not duplicate .env entry', () async {
        cmd.arguments = parser.parse([]);
        await cmd.handle();
        await cmd.handle();

        final content = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
        final count = '.env'.allMatches(content).length;

        expect(
          count,
          1,
          reason: '.env should appear exactly once in pubspec.yaml',
        );
      });

      test('works when flutter.assets already exists', () async {
        // Pre-seed pubspec with existing asset.
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
description: A test Flutter project.
version: 1.0.0+1

environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter

flutter:
  assets:
    - assets/images/
''');

        cmd.arguments = parser.parse([]);
        await cmd.handle();

        final content = File('${tempDir.path}/pubspec.yaml').readAsStringSync();

        expect(content, contains('.env'));
        expect(content, contains('assets/images/'));
      });
    });

    // -----------------------------------------------------------------------
    // Group 16: Web support (sqlite3.wasm)
    // -----------------------------------------------------------------------
    group('Web support (sqlite3.wasm)', () {
      late _TestInstallCommandWithDownload downloadCmd;
      late ArgParser downloadParser;

      setUp(() {
        downloadCmd = _TestInstallCommandWithDownload(tempDir.path);
        downloadParser = ArgParser();
        downloadCmd.configure(downloadParser);
      });

      test('downloads sqlite3.wasm on default install', () async {
        downloadCmd.arguments = downloadParser.parse([]);
        await downloadCmd.handle();

        expect(
          downloadCmd.downloadFileCalled,
          isTrue,
          reason: 'downloadFile should be called during install',
        );
        expect(
          File('${tempDir.path}/web/sqlite3.wasm').existsSync(),
          isTrue,
          reason: 'web/sqlite3.wasm should exist after install',
        );
      });

      test('download URL targets correct GitHub release', () async {
        downloadCmd.arguments = downloadParser.parse([]);
        await downloadCmd.handle();

        expect(
          downloadCmd.downloadFileUrl.toString(),
          contains('simolus3/sqlite3.dart'),
          reason: 'Download URL should point to sqlite3.dart releases',
        );
        expect(
          downloadCmd.downloadFileUrl.toString(),
          contains('sqlite3.wasm'),
          reason: 'Download URL should target sqlite3.wasm binary',
        );
      });

      test('skips download when sqlite3.wasm already exists', () async {
        // Pre-create the WASM file.
        final webDir = Directory('${tempDir.path}/web');
        webDir.createSync(recursive: true);
        File('${tempDir.path}/web/sqlite3.wasm')
            .writeAsBytesSync([0x00, 0x61, 0x73, 0x6D]);

        downloadCmd.arguments = downloadParser.parse([]);
        await downloadCmd.handle();

        expect(
          downloadCmd.downloadFileCalled,
          isFalse,
          reason: 'downloadFile should NOT be called if file already exists',
        );
      });

      test('skips wasm download with --without-database flag', () async {
        downloadCmd.arguments = downloadParser.parse(['--without-database']);
        await downloadCmd.handle();

        expect(
          downloadCmd.downloadFileCalled,
          isFalse,
          reason: 'downloadFile should NOT be called with --without-database',
        );
      });

      test('graceful failure — install completes when download fails',
          () async {
        downloadCmd.simulateDownloadSuccess = false;
        downloadCmd.arguments = downloadParser.parse([]);

        // Should NOT throw.
        await downloadCmd.handle();

        expect(
          File('${tempDir.path}/web/sqlite3.wasm').existsSync(),
          isFalse,
          reason: 'sqlite3.wasm should NOT exist when download fails',
        );
      });

      test('uses version from pubspec.lock when available', () async {
        // Write a pubspec.lock with a specific sqlite3 version.
        File('${tempDir.path}/pubspec.lock').writeAsStringSync('''
packages:
  sqlite3:
    dependency: transitive
    description:
      name: sqlite3
      sha256: abc123
      url: "https://pub.dev"
    source: hosted
    version: "2.5.0"
''');

        downloadCmd.arguments = downloadParser.parse([]);
        await downloadCmd.handle();

        expect(
          downloadCmd.downloadFileUrl.toString(),
          contains('sqlite3-2.5.0'),
          reason: 'Should use version from pubspec.lock',
        );
      });

      test('falls back to default version without pubspec.lock', () async {
        downloadCmd.arguments = downloadParser.parse([]);
        await downloadCmd.handle();

        expect(
          downloadCmd.downloadFileUrl.toString(),
          contains('sqlite3-2.4.6'),
          reason: 'Should fall back to 2.4.6 without pubspec.lock',
        );
      });
    });
  });
}
