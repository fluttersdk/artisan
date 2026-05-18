import 'package:test/test.dart';

// bin/mcp.dart is not a library export — import it directly so mcpMain and
// RunArtisanFn are visible to the test without pulling them into the barrel.
import '../../bin/mcp.dart';

void main() {
  group('mcpMain', () {
    // -------------------------------------------------------------------------
    // Argument forwarding
    // -------------------------------------------------------------------------

    test('prepends mcp:serve to caller args', () async {
      final captured = <List<String>>[];
      final capturedFlags = <bool>[];

      Future<int> recorder(List<String> args,
          {bool collectMcpTools = false, bool delegateToConsumer = true}) {
        captured.add(List<String>.from(args));
        capturedFlags.add(collectMcpTools);
        return Future.value(0);
      }

      await mcpMain([], runArtisan: recorder);

      expect(captured, hasLength(1));
      expect(captured.first, equals(['mcp:serve']));
    });

    test('forwards extra args after mcp:serve', () async {
      final captured = <List<String>>[];

      Future<int> recorder(List<String> args,
          {bool collectMcpTools = false, bool delegateToConsumer = true}) {
        captured.add(List<String>.from(args));
        return Future.value(0);
      }

      await mcpMain(['--include-package', 'x'], runArtisan: recorder);

      expect(captured.first, equals(['mcp:serve', '--include-package', 'x']));
    });

    test('passes collectMcpTools: true to runArtisan', () async {
      final capturedFlags = <bool>[];

      Future<int> recorder(List<String> args,
          {bool collectMcpTools = false, bool delegateToConsumer = true}) {
        capturedFlags.add(collectMcpTools);
        return Future.value(0);
      }

      await mcpMain([], runArtisan: recorder);

      expect(capturedFlags, equals([true]));
    });

    test(
        'forces delegateToConsumer: false so MCP never routes through a stale consumer wrapper',
        () async {
      final capturedDelegation = <bool>[];

      Future<int> recorder(List<String> args,
          {bool collectMcpTools = false, bool delegateToConsumer = true}) {
        capturedDelegation.add(delegateToConsumer);
        return Future.value(0);
      }

      await mcpMain([], runArtisan: recorder);

      expect(capturedDelegation, equals([false]));
    });

    test('returns exit code from runArtisan', () async {
      Future<int> recorder(List<String> args,
              {bool collectMcpTools = false, bool delegateToConsumer = true}) =>
          Future.value(42);

      final code = await mcpMain([], runArtisan: recorder);

      expect(code, equals(42));
    });

    test('returns non-zero exit code on error', () async {
      Future<int> recorder(List<String> args,
              {bool collectMcpTools = false, bool delegateToConsumer = true}) =>
          Future.value(1);

      final code = await mcpMain([], runArtisan: recorder);

      expect(code, equals(1));
    });
  });
}
