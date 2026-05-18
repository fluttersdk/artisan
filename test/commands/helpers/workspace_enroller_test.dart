import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('WorkspaceEnroller', () {
    late InMemoryFs fs;
    late WorkspaceEnroller enroller;

    setUp(() {
      fs = InMemoryFs();
      enroller = WorkspaceEnroller(fs);
    });

    // -------------------------------------------------------------------------
    // detectParentFlutterApp
    // -------------------------------------------------------------------------

    test(
      'detectParentFlutterApp returns parent pubspec path when target is nested '
      'inside a Flutter app',
      () {
        // Arrange: /app/pubspec.yaml has flutter: key; target is /app/plugins/my_plugin
        fs.writeAsString('/app/pubspec.yaml',
            'name: parent_app\nflutter:\n  uses-material-design: true\n');
        fs.writeAsString(
            '/app/plugins/my_plugin/pubspec.yaml', 'name: my_plugin\n');

        // Act
        final result =
            enroller.detectParentFlutterApp('/app/plugins/my_plugin');

        // Assert
        expect(result, equals('/app/pubspec.yaml'));
      },
    );

    test(
      'detectParentFlutterApp returns null when target dir is a sibling to the '
      'consumer (no Flutter app in ancestor chain)',
      () {
        // Arrange: /projects/my_plugin lives next to /projects/consumer_app but
        // no ancestor pubspec has a flutter: key.
        fs.writeAsString(
            '/projects/my_plugin/pubspec.yaml', 'name: my_plugin\n');

        // Act
        final result = enroller.detectParentFlutterApp('/projects/my_plugin');

        // Assert
        expect(result, isNull);
      },
    );

    test(
      'detectParentFlutterApp skips a non-Flutter pubspec.yaml (no flutter: key) '
      'and continues walking up',
      () {
        // Arrange: /workspace/pubspec.yaml has no flutter: key (pure workspace
        // root). /workspace/app/pubspec.yaml HAS a flutter: key. Target plugin
        // lives at /workspace/app/plugins/my_plugin — the search must skip the
        // non-flutter /workspace/pubspec.yaml and return /workspace/app/pubspec.yaml.
        fs.writeAsString('/workspace/pubspec.yaml', 'name: workspace_root\n');
        fs.writeAsString(
          '/workspace/app/pubspec.yaml',
          'name: consumer\nflutter:\n  uses-material-design: true\n',
        );
        fs.writeAsString(
          '/workspace/app/plugins/my_plugin/pubspec.yaml',
          'name: my_plugin\n',
        );

        // Act: walk up from the plugin directory
        final result =
            enroller.detectParentFlutterApp('/workspace/app/plugins/my_plugin');

        // Assert: nearest ancestor Flutter pubspec found, not the non-flutter
        // workspace root further up.
        expect(result, equals('/workspace/app/pubspec.yaml'));
      },
    );

    // -------------------------------------------------------------------------
    // enrollWorkspace
    // -------------------------------------------------------------------------

    test(
      'enrollWorkspace adds workspace: list to a fresh parent pubspec that has '
      'no existing workspace: section',
      () async {
        // Arrange
        const parentPubspec = '/app/pubspec.yaml';
        const pluginPubspec = '/app/plugins/my_plugin/pubspec.yaml';

        fs.writeAsString(parentPubspec,
            'name: parent_app\n\nflutter:\n  uses-material-design: true\n');
        fs.writeAsString(pluginPubspec, 'name: my_plugin\n');

        // Act
        await enroller.enrollWorkspace(
          parentPubspecPath: parentPubspec,
          pluginRelativePath: 'plugins/my_plugin',
          pluginPubspecPath: pluginPubspec,
        );

        // Assert: parent pubspec gains a workspace: list
        final parentContent = fs.readAsString(parentPubspec);
        expect(parentContent, contains('workspace:'));
        expect(parentContent, contains('plugins/my_plugin'));
      },
    );

    test(
      'enrollWorkspace appends to an existing workspace: list without '
      'clobbering prior entries',
      () async {
        // Arrange: parent already has workspace: with one entry
        const parentPubspec = '/app/pubspec.yaml';
        const pluginPubspec = '/app/plugins/new_plugin/pubspec.yaml';

        fs.writeAsString(
          parentPubspec,
          'name: parent_app\n\nworkspace:\n  - plugins/old_plugin\n',
        );
        fs.writeAsString(pluginPubspec, 'name: new_plugin\n');

        // Act
        await enroller.enrollWorkspace(
          parentPubspecPath: parentPubspec,
          pluginRelativePath: 'plugins/new_plugin',
          pluginPubspecPath: pluginPubspec,
        );

        // Assert: both entries present
        final parentContent = fs.readAsString(parentPubspec);
        expect(parentContent, contains('plugins/old_plugin'));
        expect(parentContent, contains('plugins/new_plugin'));
      },
    );

    test(
      'enrollWorkspace is idempotent: re-enrolling the same plugin path does '
      'NOT duplicate the workspace entry',
      () async {
        // Arrange: parent already has the target path listed
        const parentPubspec = '/app/pubspec.yaml';
        const pluginPubspec = '/app/plugins/my_plugin/pubspec.yaml';

        fs.writeAsString(
          parentPubspec,
          'name: parent_app\n\nworkspace:\n  - plugins/my_plugin\n',
        );
        fs.writeAsString(
            pluginPubspec, 'name: my_plugin\nresolution: workspace\n');

        // Act: enroll again
        await enroller.enrollWorkspace(
          parentPubspecPath: parentPubspec,
          pluginRelativePath: 'plugins/my_plugin',
          pluginPubspecPath: pluginPubspec,
        );

        // Assert: exactly one occurrence of the path
        final parentContent = fs.readAsString(parentPubspec);
        expect(
          RegExp(r'plugins/my_plugin').allMatches(parentContent).length,
          equals(1),
        );
      },
    );

    test(
      'enrollWorkspace adds resolution: workspace to plugin pubspec',
      () async {
        // Arrange: fresh plugin pubspec without resolution:
        const parentPubspec = '/app/pubspec.yaml';
        const pluginPubspec = '/app/plugins/my_plugin/pubspec.yaml';

        fs.writeAsString(parentPubspec, 'name: parent_app\n');
        fs.writeAsString(pluginPubspec, 'name: my_plugin\nversion: 0.0.1\n');

        // Act
        await enroller.enrollWorkspace(
          parentPubspecPath: parentPubspec,
          pluginRelativePath: 'plugins/my_plugin',
          pluginPubspecPath: pluginPubspec,
        );

        // Assert
        final pluginContent = fs.readAsString(pluginPubspec);
        expect(pluginContent, contains('resolution: workspace'));
      },
    );

    test(
      'enrollWorkspace does NOT duplicate resolution: workspace when already '
      'present in plugin pubspec (idempotent)',
      () async {
        // Arrange: plugin pubspec already has resolution: workspace
        const parentPubspec = '/app/pubspec.yaml';
        const pluginPubspec = '/app/plugins/my_plugin/pubspec.yaml';

        fs.writeAsString(parentPubspec, 'name: parent_app\n');
        fs.writeAsString(
            pluginPubspec, 'name: my_plugin\nresolution: workspace\n');

        // Act
        await enroller.enrollWorkspace(
          parentPubspecPath: parentPubspec,
          pluginRelativePath: 'plugins/my_plugin',
          pluginPubspecPath: pluginPubspec,
        );

        // Assert: exactly one occurrence
        final pluginContent = fs.readAsString(pluginPubspec);
        expect(
          RegExp(r'resolution: workspace').allMatches(pluginContent).length,
          equals(1),
        );
      },
    );
  });
}
