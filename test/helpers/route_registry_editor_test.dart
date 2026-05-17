import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Full-fixture content matching the uptizm-app RouteServiceProvider shape.
const String _fullFixture = """
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart';
import '../../routes/app.dart';
import '../kernel.dart';

class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  void register() {
    registerKernel();
  }

  @override
  Future<void> boot() async {
    registerMagicStarterAuthRoutes();
    registerAppRoutes();
  }
}
""";

/// Empty-boot fixture: boot body contains only whitespace.
const String _emptyBootFixture = """
import 'package:magic/magic.dart';

class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  Future<void> boot() async {
  }
}
""";

void main() {
  group('RouteRegistryEditor', () {
    late Directory tempDir;
    late String providerPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artisan_route_reg_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // addRouteRegistration
    // -------------------------------------------------------------------------

    test(
      '1. addRouteRegistration inserts call before registerAppRoutes() '
      'preserving order and whitespace',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(_fullFixture);

        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        final content = File(providerPath).readAsStringSync();
        expect(content, contains('registerMyPluginRoutes();'));

        // Must appear BEFORE registerAppRoutes().
        final insertPos = content.indexOf('registerMyPluginRoutes();');
        final appRoutesPos = content.indexOf('registerAppRoutes();');
        expect(insertPos, lessThan(appRoutesPos));
      },
    );

    test(
      '2. addRouteRegistration inserts before closing brace when '
      'registerAppRoutes() is absent (empty boot)',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(_emptyBootFixture);

        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        final content = File(providerPath).readAsStringSync();
        expect(content, contains('registerMyPluginRoutes();'));
      },
    );

    test(
      '3. addRouteRegistration is idempotent — re-call does not double-insert',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(_fullFixture);

        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );
        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        final content = File(providerPath).readAsStringSync();
        final count = 'registerMyPluginRoutes();'.allMatches(content).length;
        expect(count, 1);
      },
    );

    test(
      '4. addRouteRegistration tolerates extra whitespace in boot() signature',
      () {
        // Signature with extra spaces: Future<void>  boot ( ) async {
        const String whitespaceFixture = """
import 'package:magic/magic.dart';

class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  Future<void>  boot ( ) async {
    registerAppRoutes();
  }
}
""";
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(whitespaceFixture);

        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        final content = File(providerPath).readAsStringSync();
        expect(content, contains('registerMyPluginRoutes();'));

        final insertPos = content.indexOf('registerMyPluginRoutes();');
        final appRoutesPos = content.indexOf('registerAppRoutes();');
        expect(insertPos, lessThan(appRoutesPos));
      },
    );

    // -------------------------------------------------------------------------
    // removeRouteRegistration
    // -------------------------------------------------------------------------

    test(
      '5. removeRouteRegistration deletes the target call line',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(_fullFixture);

        // First add, then remove.
        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        RouteRegistryEditor.removeRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        final content = File(providerPath).readAsStringSync();
        expect(content, isNot(contains('registerMyPluginRoutes();')));
      },
    );

    test(
      '6. removeRouteRegistration is idempotent — no-op when call is absent',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(_fullFixture);

        final before = File(providerPath).readAsStringSync();

        // Call remove on a function that was never added.
        RouteRegistryEditor.removeRouteRegistration(
          providerPath,
          'registerNeverAdded',
        );

        expect(File(providerPath).readAsStringSync(), before);
      },
    );

    // -------------------------------------------------------------------------
    // addRouteImport
    // -------------------------------------------------------------------------

    test(
      '7. addRouteImport delegates to ConfigEditor.addImportToFile correctly',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(_fullFixture);

        RouteRegistryEditor.addRouteImport(
          providerPath,
          "import 'package:my_plugin/routes.dart';",
        );

        final content = File(providerPath).readAsStringSync();
        expect(
          content,
          contains("import 'package:my_plugin/routes.dart';"),
        );
      },
    );

    // -------------------------------------------------------------------------
    // Error paths
    // -------------------------------------------------------------------------

    test(
      '8. addRouteRegistration throws StateError when boot() is absent',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        // File with no boot() method at all.
        File(providerPath).writeAsStringSync("""
class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  void register() {
    registerKernel();
  }
}
""");

        expect(
          () => RouteRegistryEditor.addRouteRegistration(
            providerPath,
            'registerMyPluginRoutes',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      '9. addRouteRegistration throws StateError when boot() brace is unmatched',
      () {
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        // Opening brace of boot() exists but no matching closing brace.
        File(providerPath).writeAsStringSync(
          'class X { Future<void> boot() async { registerAppRoutes();',
        );

        expect(
          () => RouteRegistryEditor.addRouteRegistration(
            providerPath,
            'registerMyPluginRoutes',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      '10. addRouteRegistration with multiple existing calls inserts in '
      'correct position',
      () {
        // Provider with two starter registrations before registerAppRoutes.
        const String multiCallFixture = """
import 'package:magic/magic.dart';

class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  Future<void> boot() async {
    registerMagicStarterAuthRoutes();
    registerMagicStarterProfileRoutes();
    registerAppRoutes();
  }
}
""";
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(multiCallFixture);

        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        final content = File(providerPath).readAsStringSync();
        expect(content, contains('registerMyPluginRoutes();'));

        final insertPos = content.indexOf('registerMyPluginRoutes();');
        final appRoutesPos = content.indexOf('registerAppRoutes();');
        expect(insertPos, lessThan(appRoutesPos));
      },
    );

    test(
      '11. addRouteRegistration correctly handles boot() containing nested '
      'block (brace depth > 1)',
      () {
        // boot() with an inner block so the brace-counting depth++ path fires.
        const String nestedBlockFixture = """
import 'package:magic/magic.dart';

class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  Future<void> boot() async {
    if (true) {
      registerMagicStarterAuthRoutes();
    }
    registerAppRoutes();
  }
}
""";
        providerPath = p.join(tempDir.path, 'route_service_provider.dart');
        File(providerPath).writeAsStringSync(nestedBlockFixture);

        RouteRegistryEditor.addRouteRegistration(
          providerPath,
          'registerMyPluginRoutes',
        );

        final content = File(providerPath).readAsStringSync();
        expect(content, contains('registerMyPluginRoutes();'));

        final insertPos = content.indexOf('registerMyPluginRoutes();');
        final appRoutesPos = content.indexOf('registerAppRoutes();');
        expect(insertPos, lessThan(appRoutesPos));
      },
    );
  });
}
