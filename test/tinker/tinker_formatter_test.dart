import 'package:fluttersdk_artisan/artisan.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('formatInstanceRef', () {
    test('returns "null" for null value', () {
      expect(formatInstanceRef(null), 'null');
    });

    test('unwraps a primitive int InstanceRef via valueAsString', () {
      final ref = InstanceRef(
        kind: 'Int',
        valueAsString: '42',
        id: 'objects/int-42',
      );
      expect(formatInstanceRef(ref), '42');
    });

    test('unwraps a primitive double InstanceRef', () {
      final ref = InstanceRef(
        kind: 'Double',
        valueAsString: '3.14',
        id: 'objects/double-1',
      );
      expect(formatInstanceRef(ref), '3.14');
    });

    test('quotes String-kind InstanceRef with double quotes', () {
      final ref = InstanceRef(
        kind: 'String',
        valueAsString: 'hello world',
        id: '#StringInstanceRef#hello world',
      );
      expect(formatInstanceRef(ref), '"hello world"');
    });

    test('falls back to <ClassName#id> for non-primitive InstanceRef', () {
      final classRef = ClassRef(name: 'Monitor', id: 'classes/Monitor');
      final ref = InstanceRef(
        kind: 'PlainInstance',
        classRef: classRef,
        id: 'objects/foo',
      );
      expect(formatInstanceRef(ref), '<Monitor#objects/foo>');
    });

    test('uses "Instance" sentinel when classRef is null', () {
      final ref = InstanceRef(
        kind: 'PlainInstance',
        id: 'objects/bar',
      );
      expect(formatInstanceRef(ref), '<Instance#objects/bar>');
    });

    test('renders ErrorRef with prefix and message', () {
      final err = ErrorRef(
        kind: 'UnhandledException',
        message: 'boom',
        id: 'objects/err',
      );
      expect(formatInstanceRef(err), 'Error: boom');
    });

    test('renders ErrorRef with id fallback when message is null', () {
      final err = ErrorRef(
        kind: 'UnhandledException',
        id: 'objects/silent',
      );
      expect(formatInstanceRef(err), 'Error: objects/silent');
    });

    test('falls through to toString() for plain Dart values', () {
      expect(formatInstanceRef(123), '123');
      expect(formatInstanceRef('plain string'), 'plain string');
      expect(formatInstanceRef([1, 2, 3]), '[1, 2, 3]');
    });
  });

  group('formatTinkerResult', () {
    tearDown(() => Tinker.casters.clear());

    test('falls back to formatInstanceRef when no casters supplied', () {
      final ref = InstanceRef(
        kind: 'Int',
        valueAsString: '7',
        id: 'objects/int-7',
      );
      expect(formatTinkerResult(ref, casters: const <TinkerCaster>[]), '7');
    });

    test('uses the first caster that returns non-null', () {
      final casters = <TinkerCaster>[
        (_) => null, // skip
        (v) => v is int ? 'INT($v)' : null, // hit
        (_) => 'should-not-reach',
      ];
      expect(formatTinkerResult(42, casters: casters), 'INT(42)');
    });

    test('skips casters returning null until one matches', () {
      final casters = <TinkerCaster>[
        (_) => null,
        (_) => null,
        (v) => 'late=$v',
      ];
      expect(formatTinkerResult('x', casters: casters), 'late=x');
    });

    test('returns the InstanceRef fallback when every caster returns null', () {
      final casters = <TinkerCaster>[
        (_) => null,
        (_) => null,
      ];
      expect(formatTinkerResult('plain', casters: casters), 'plain');
    });

    test('defaults to Tinker.casters when none passed', () {
      Tinker.casters.add((v) => v is bool ? 'BOOL($v)' : null);
      expect(formatTinkerResult(true), 'BOOL(true)');
    });

    test('default-chain still falls through to formatInstanceRef', () {
      // Tinker.casters cleared in tearDown; verify empty-list-default
      // doesn't NPE.
      expect(formatTinkerResult(null), 'null');
    });
  });
}
