import 'package:test/test.dart';

import 'package:fluttersdk_artisan/artisan.dart';

void main() {
  group('McpToolDescriptor', () {
    const descriptor = McpToolDescriptor(
      name: 'dusk_tap',
      description: 'Tap a widget by semantic label.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'label': {'type': 'string'},
        },
        'required': ['label'],
      },
      extensionMethod: 'ext.dusk.tap',
    );

    test('constructor populates all 4 fields', () {
      expect(descriptor.name, 'dusk_tap');
      expect(descriptor.description, 'Tap a widget by semantic label.');
      expect(descriptor.inputSchema, {
        'type': 'object',
        'properties': {
          'label': {'type': 'string'},
        },
        'required': ['label'],
      });
      expect(descriptor.extensionMethod, 'ext.dusk.tap');
    });

    test(
        'toJson includes name + description + inputSchema, excludes extensionMethod',
        () {
      final json = descriptor.toJson();

      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('description'), isTrue);
      expect(json.containsKey('inputSchema'), isTrue);
      expect(json.containsKey('extensionMethod'), isFalse);

      expect(json['name'], 'dusk_tap');
      expect(json['description'], 'Tap a widget by semantic label.');
      expect(json['inputSchema'], descriptor.inputSchema);
    });

    test('toString is useful for collision diagnostics', () {
      final str = descriptor.toString();

      expect(str, contains('dusk_tap'));
      expect(str, contains('ext.dusk.tap'));
    });
  });
}
