import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('PluginEntry', () {
    test('toJson / fromJson round-trip preserves all fields', () {
      const entry = PluginEntry(
        name: 'firebase_messaging',
        providerImport:
            'package:magic_firebase/src/firebase_messaging_provider.dart',
        providerClass: 'FirebaseMessagingProvider',
        registeredAt: '2026-05-18T10:00:00.000Z',
      );

      final decoded = PluginEntry.fromJson(entry.toJson());

      expect(decoded.name, entry.name);
      expect(decoded.providerImport, entry.providerImport);
      expect(decoded.providerClass, entry.providerClass);
      expect(decoded.registeredAt, entry.registeredAt);
    });
  });

  group('PluginsRegistry', () {
    test('empty factory returns version 1 with an empty plugin list', () {
      final registry = PluginsRegistry.empty();

      expect(registry.version, 1);
      expect(registry.plugins, isEmpty);
    });

    test('toJson / fromJson round-trip preserves version and plugins', () {
      const entry = PluginEntry(
        name: 'analytics',
        providerImport: 'package:analytics/provider.dart',
        providerClass: 'AnalyticsProvider',
        registeredAt: '2026-05-18T11:00:00.000Z',
      );
      final registry = PluginsRegistry(version: 1, plugins: [entry]);

      final decoded = PluginsRegistry.fromJson(registry.toJson());

      expect(decoded.version, 1);
      expect(decoded.plugins, hasLength(1));
      expect(decoded.plugins.first.name, 'analytics');
    });
  });

  group('PluginsRegistryFile.read()', () {
    test('returns empty registry when the file does not exist', () async {
      final fs = InMemoryFs();
      final registryFile = PluginsRegistryFile(fs, '/proj');

      final registry = await registryFile.read();

      expect(registry.version, 1);
      expect(registry.plugins, isEmpty);
    });

    test('returns empty registry when the file exists but is empty', () async {
      final fs = InMemoryFs();
      fs.writeAsString('/proj/.artisan/plugins.json', '');
      final registryFile = PluginsRegistryFile(fs, '/proj');

      final registry = await registryFile.read();

      expect(registry.version, 1);
      expect(registry.plugins, isEmpty);
    });

    test('parses a valid v1 JSON file into a PluginsRegistry', () async {
      final fs = InMemoryFs();
      final payload = jsonEncode(<String, dynamic>{
        'version': 1,
        'plugins': [
          <String, dynamic>{
            'name': 'logger',
            'providerImport': 'package:magic_logger/provider.dart',
            'providerClass': 'LoggerProvider',
            'registeredAt': '2026-05-18T09:00:00.000Z',
          },
        ],
      });
      fs.writeAsString('/proj/.artisan/plugins.json', payload);
      final registryFile = PluginsRegistryFile(fs, '/proj');

      final registry = await registryFile.read();

      expect(registry.version, 1);
      expect(registry.plugins, hasLength(1));
      expect(registry.plugins.first.name, 'logger');
    });

    test('throws FormatException when version field exceeds 1', () async {
      final fs = InMemoryFs();
      final payload = jsonEncode(<String, dynamic>{
        'version': 2,
        'plugins': <dynamic>[],
      });
      fs.writeAsString('/proj/.artisan/plugins.json', payload);
      final registryFile = PluginsRegistryFile(fs, '/proj');

      expect(registryFile.read(), throwsA(isA<FormatException>()));
    });
  });

  group('PluginsRegistryFile.write()', () {
    test('write/read round-trip preserves the full registry', () async {
      final fs = InMemoryFs();
      final registryFile = PluginsRegistryFile(fs, '/proj');
      const entry = PluginEntry(
        name: 'push',
        providerImport: 'package:magic_push/provider.dart',
        providerClass: 'PushProvider',
        registeredAt: '2026-05-18T12:00:00.000Z',
      );
      final registry = PluginsRegistry(version: 1, plugins: [entry]);

      await registryFile.write(registry);
      final read = await registryFile.read();

      expect(read.version, 1);
      expect(read.plugins, hasLength(1));
      expect(read.plugins.first.name, 'push');
    });

    test('atomic write uses .tmp then renames: no .tmp survives after write',
        () async {
      final fs = InMemoryFs();
      final registryFile = PluginsRegistryFile(fs, '/proj');
      final registry = PluginsRegistry.empty();

      await registryFile.write(registry);

      // The temporary file must be gone and the target must exist.
      expect(
        fs.exists('/proj/.artisan/plugins.json.tmp'),
        isFalse,
        reason: '.tmp file must not survive after successful rename',
      );
      expect(
        fs.exists('/proj/.artisan/plugins.json'),
        isTrue,
        reason: 'Target file must exist after write',
      );
    });
  });

  group('PluginsRegistryFile.addPlugin()', () {
    test('adds a new entry to an empty registry', () async {
      final fs = InMemoryFs();
      final registryFile = PluginsRegistryFile(fs, '/proj');
      const entry = PluginEntry(
        name: 'logger',
        providerImport: 'package:magic_logger/provider.dart',
        providerClass: 'LoggerProvider',
        registeredAt: '2026-05-18T09:00:00.000Z',
      );

      await registryFile.addPlugin(entry);
      final registry = await registryFile.read();

      expect(registry.plugins, hasLength(1));
      expect(registry.plugins.first.name, 'logger');
    });

    test('replaces an existing entry with the same name (idempotent add)',
        () async {
      final fs = InMemoryFs();
      final registryFile = PluginsRegistryFile(fs, '/proj');
      const original = PluginEntry(
        name: 'logger',
        providerImport: 'package:magic_logger/v1/provider.dart',
        providerClass: 'LoggerProviderV1',
        registeredAt: '2026-05-18T09:00:00.000Z',
      );
      const updated = PluginEntry(
        name: 'logger',
        providerImport: 'package:magic_logger/v2/provider.dart',
        providerClass: 'LoggerProviderV2',
        registeredAt: '2026-05-18T10:00:00.000Z',
      );

      await registryFile.addPlugin(original);
      await registryFile.addPlugin(updated);
      final registry = await registryFile.read();

      expect(registry.plugins, hasLength(1));
      expect(registry.plugins.first.providerClass, 'LoggerProviderV2');
    });
  });

  group('PluginsRegistryFile.removePlugin()', () {
    test('removes an existing plugin by name', () async {
      final fs = InMemoryFs();
      final registryFile = PluginsRegistryFile(fs, '/proj');
      const entry = PluginEntry(
        name: 'logger',
        providerImport: 'package:magic_logger/provider.dart',
        providerClass: 'LoggerProvider',
        registeredAt: '2026-05-18T09:00:00.000Z',
      );
      await registryFile.addPlugin(entry);

      await registryFile.removePlugin('logger');
      final registry = await registryFile.read();

      expect(registry.plugins, isEmpty);
    });

    test('is a no-op when the name is not present (idempotent remove)',
        () async {
      final fs = InMemoryFs();
      final registryFile = PluginsRegistryFile(fs, '/proj');

      // Should not throw even when the file does not exist yet.
      await registryFile.removePlugin('nonexistent');
      final registry = await registryFile.read();

      expect(registry.plugins, isEmpty);
    });
  });
}
