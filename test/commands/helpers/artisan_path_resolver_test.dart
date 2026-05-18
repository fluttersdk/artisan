import 'package:fluttersdk_artisan/src/commands/helpers/artisan_path_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('ArtisanPathResolver.computeRelative', () {
    test(
      'nested case: target two levels deep → ../../fluttersdk_artisan',
      () {
        const artisanRoot = '/foo/fluttersdk_artisan';
        const targetDir = '/foo/example_magic/packages/x';

        final result = ArtisanPathResolver.computeRelative(
          artisanRoot: artisanRoot,
          targetDir: targetDir,
        );

        expect(result, equals('../../../fluttersdk_artisan'));
      },
    );

    test(
      'deep nested case: target five levels deep → ../../../../../fluttersdk_artisan',
      () {
        const artisanRoot = '/foo/fluttersdk_artisan';
        const targetDir = '/foo/a/b/c/d/e';

        final result = ArtisanPathResolver.computeRelative(
          artisanRoot: artisanRoot,
          targetDir: targetDir,
        );

        expect(result, equals('../../../../../fluttersdk_artisan'));
      },
    );

    test(
      'sibling case: target is sibling directory → ../fluttersdk_artisan',
      () {
        const artisanRoot = '/foo/fluttersdk_artisan';
        const targetDir = '/foo/my_plugin';

        final result = ArtisanPathResolver.computeRelative(
          artisanRoot: artisanRoot,
          targetDir: targetDir,
        );

        expect(result, equals('../fluttersdk_artisan'));
      },
    );

    test(
      'identical dir: artisanRoot equals targetDir → .',
      () {
        const artisanRoot = '/foo/fluttersdk_artisan';
        const targetDir = '/foo/fluttersdk_artisan';

        final result = ArtisanPathResolver.computeRelative(
          artisanRoot: artisanRoot,
          targetDir: targetDir,
        );

        expect(result, equals('.'));
      },
    );
  });
}
