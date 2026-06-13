import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ============================================================================
// Extracted from connection_manager_test.dart & ws_gateway_client_test.dart
//
// These helpers were previously duplicated ~150 lines verbatim across both
// files.  When the ConnectionManager API or protocol JSON format changes,
// update this single file instead of two.
// ============================================================================

// ---------------------------------------------------------------------------
// Mocktail fakes
// ---------------------------------------------------------------------------

class MockWebSocketChannel extends Mock implements WebSocketChannel {}

class MockWebSocketSink extends Mock implements WebSocketSink {
  /// Override to ensure [close] returns a Future, not null.
  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) =>
      Future.value();
}

// ---------------------------------------------------------------------------
// Controllable WebSocket helper
// ---------------------------------------------------------------------------

class ControllableWebSocket {
  final MockWebSocketChannel channel = MockWebSocketChannel();
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final Completer<WebSocketChannel> readyCompleter =
      Completer<WebSocketChannel>();
  final MockWebSocketSink sink = MockWebSocketSink();
  final List<String> sentFrames = [];

  ControllableWebSocket._();

  factory ControllableWebSocket.create() {
    final ws = ControllableWebSocket._();
    _wire(ws);
    when(() => ws.channel.ready).thenAnswer((_) => ws.readyCompleter.future);
    return ws;
  }

  factory ControllableWebSocket.ready() {
    final ws = ControllableWebSocket._();
    _wire(ws);
    when(() => ws.channel.ready).thenAnswer((_) => Future.value(ws.channel));
    return ws;
  }

  static void _wire(ControllableWebSocket ws) {
    when(() => ws.channel.stream).thenAnswer((_) => ws.incoming.stream);
    when(() => ws.channel.sink).thenReturn(ws.sink);
    when(() => ws.sink.add(any())).thenAnswer((inv) {
      final data = inv.positionalArguments.first;
      if (data is String) ws.sentFrames.add(data);
    });
  }

  void simulateServerFrame(String json) => incoming.add(json);
  void simulateError(Object error) => incoming.addError(error);
  void simulateServerClose() => incoming.close();
  void completeHandshake() => readyCompleter.complete(channel);
}

// ---------------------------------------------------------------------------
// Protocol JSON builders
// ---------------------------------------------------------------------------

Future<void> pumpMicrotasks() => Future.delayed(Duration.zero);

String challengeJson({String nonce = 'test-nonce'}) =>
    '{"type":"event","event":"connect.challenge","payload":{"nonce":"$nonce"}}';

String helloOkJson(String id) =>
    '{"type":"res","id":"$id","ok":true,'
    '"payload":{"type":"hello-ok","protocol":4,"policy":{"tickIntervalMs":15000}}}';

/// Extract the request ID from a sent JSON frame.
String extractReqId(String sentFrame) {
  final m = RegExp(r'"id":"([^"]+)"').firstMatch(sentFrame);
  return m!.group(1)!;
}
