import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';

void main() {
  group('Tinker static hooks', () {
    setUp(() {
      Tinker.autocompleteCorpus.clear();
      Tinker.classAliases.clear();
      Tinker.casters.clear();
    });

    test('autocompleteCorpus is mutable and starts empty', () {
      expect(Tinker.autocompleteCorpus, isEmpty);

      Tinker.autocompleteCorpus.addAll(<String>['User', 'Monitor']);

      expect(Tinker.autocompleteCorpus, <String>['User', 'Monitor']);
    });

    test('classAliases stores short-name -> full-name pairs', () {
      Tinker.classAliases['User'] = 'package:magic/src/auth/user.dart';

      expect(
        Tinker.classAliases['User'],
        'package:magic/src/auth/user.dart',
      );
    });

    test('casters can be appended and invoked', () {
      String? upperString(Object? value) =>
          value is String ? value.toUpperCase() : null;

      Tinker.casters.add(upperString);

      expect(Tinker.casters.first('hi'), 'HI');
      expect(Tinker.casters.first(42), isNull);
    });

    test('TinkerCaster typedef accepts a nullable Object? input', () {
      String? caster(Object? v) => v == null ? '<null>' : null;

      final TinkerCaster typed = caster;
      expect(typed(null), '<null>');
      expect(typed('x'), isNull);
    });
  });
}
