import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:fluttersdk_artisan/artisan.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// Guards the one line of this package that has to be edited by hand on every
/// release and carries no compiler or analyzer pressure to be.
///
/// `McpServer` reports its version in the MCP `initialize` handshake, and the
/// string is a literal beside a comment asking the next person to remember.
/// On the 0.0.9 cut nobody did, so every client read 0.0.8 while the package
/// on disk was 0.0.9: client-side version gating and bug reports both keyed on
/// the wrong number, and correcting it cost a separate release.
///
/// The assertion reads the version off the WIRE rather than off the field,
/// because the wire value is what was wrong, and it reads the expected value
/// out of `pubspec.yaml` rather than hardcoding it, because a second hardcoded
/// copy just moves the drift somewhere else.
void main() {
  group('McpServer handshake version', () {
    test('matches the version declared in pubspec.yaml', () async {
      final Match? declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync());
      expect(declared, isNotNull, reason: 'pubspec.yaml has no version: line');

      final controller = StreamChannelController<String>(sync: true);
      McpServer.test(
        channel: controller.local,
        registry: ArtisanRegistry(),
        filter: McpFilterConfig.empty(),
        // The handshake never dials the VM Service, so neither seam is
        // exercised; both are here because the factory requires them.
        vmClientFactory: (String uri) => VmServiceClient(uri),
        stateReader: () async => null,
      );

      final client = MCPClient(
        Implementation(name: 'version_guard', version: '1.0.0'),
      );
      final connection = client.connectServer(controller.foreign);
      addTearDown(connection.shutdown);

      final InitializeResult init = await connection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: ClientCapabilities(),
          clientInfo: Implementation(name: 'version_guard', version: '1.0.0'),
        ),
      );

      expect(
        init.serverInfo.version,
        equals(declared!.group(1)),
        reason: 'bump the version literal in lib/src/mcp/mcp_server.dart too',
      );
    });
  });
}
