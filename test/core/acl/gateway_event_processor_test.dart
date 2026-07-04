import 'dart:async';

import 'package:claw_hub/core/acl/gateway_domain_mapper.dart';
import 'package:claw_hub/core/acl/gateway_event_processor.dart';
import 'package:claw_hub/core/acl/gateway_instance_connection.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GatewayEventProcessor processor;
  late GatewayInstanceConnection conn;

  setUp(() {
    processor = GatewayEventProcessor(
      uuid: const Uuid(),
      mapper: GatewayDomainMapper(),
      logger: const DebugPrintLogger(),
    );
    conn = GatewayInstanceConnection(
      messageCtrl: StreamController<Message>.broadcast(),
      toolCallCtrl: StreamController<ToolCall>.broadcast(),
      pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
      streamingCtrl: StreamController<StreamingEvent>.broadcast(),
    );
  });

  tearDown(() async {
    await conn.dispose();
  });

  group('registerSend / cleanupInstance', () {
    test('registerSend populates session mapping', () {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );
      expect(processor.sessionToAgentIdSizeForTesting, 1);
      expect(processor.sessionKeysByInstanceSizeForTesting, 1);
    });

    test('cleanupInstance removes only that instance mappings', () {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );
      processor.registerSend(
        instanceId: 'inst-2',
        sessionKey: 'agent:a2:main',
        agentId: 'a2',
      );
      processor.cleanupInstance('inst-1');
      expect(processor.sessionToAgentIdSizeForTesting, 1);
      expect(processor.sessionKeysByInstanceSizeForTesting, 1);
    });

    test('dispose clears all state', () {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );
      processor.dispose();
      expect(processor.sessionToAgentIdSizeForTesting, 0);
      expect(processor.sessionKeysByInstanceSizeForTesting, 0);
    });
  });

  group('chat events', () {
    test('chat.final with message emits Message', () async {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );

      final messages = <Message>[];
      conn.messageCtrl.stream.listen(messages.add);

      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'agent:a1:main',
            'state': 'final',
            'message': {
              'clientId': 'c1',
              'role': 'agent',
              'content': 'hello',
              'type': 'text',
            },
          },
        ),
      );

      await pumpEventQueue();
      expect(messages, hasLength(1));
      expect(messages.first.content, 'hello');
      expect(messages.first.role, MessageRole.agent);
    });

    test('chat.delta emits StreamingDelta', () async {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );

      final deltas = <StreamingEvent>[];
      conn.streamingCtrl.stream.listen(deltas.add);

      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'agent:a1:main',
            'state': 'delta',
            'deltaText': 'world',
          },
        ),
      );

      await pumpEventQueue();
      expect(deltas, hasLength(1));
      expect(deltas.first, isA<StreamingDelta>());
      expect((deltas.first as StreamingDelta).text, 'world');
      expect((deltas.first as StreamingDelta).agentId, 'a1');
    });
  });

  group('agent events', () {
    test('agent.assistant delta emits StreamingDelta', () async {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );

      final deltas = <StreamingEvent>[];
      conn.streamingCtrl.stream.listen(deltas.add);

      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'agent',
          payload: {
            'sessionKey': 'agent:a1:main',
            'stream': 'assistant',
            'data': {'delta': 'hi'},
          },
        ),
      );

      await pumpEventQueue();
      expect(deltas, hasLength(1));
      expect((deltas.first as StreamingDelta).text, 'hi');
    });

    test('agent.tool result emits ToolCall', () async {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );

      final tools = <ToolCall>[];
      conn.toolCallCtrl.stream.listen(tools.add);

      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'agent',
          payload: {
            'sessionKey': 'agent:a1:main',
            'stream': 'tool',
            'data': {'phase': 'result', 'toolCallId': 'tc-1', 'name': 'search'},
          },
        ),
      );

      await pumpEventQueue();
      expect(tools, hasLength(1));
      expect(tools.first.id, 'tc-1');
      expect(tools.first.toolName, 'search');
      expect(tools.first.status, ToolCallStatus.success);
    });
  });

  group('payload.large diagnostic', () {
    test('emits LargePayloadNotice', () async {
      final notices = <GatewayNotice>[];
      conn.gatewayNoticeCtrl.stream.listen(notices.add);

      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'payload.large',
          payload: {'maxSize': 1000, 'actualSize': 2000, 'messageType': 'text'},
        ),
      );

      await pumpEventQueue();
      expect(notices, hasLength(1));
      expect(notices.first, isA<LargePayloadNotice>());
    });
  });

  group('deduplication', () {
    test(
      'chat.final and agent.lifecycle.end produce only one Message',
      () async {
        processor.registerSend(
          instanceId: 'inst-1',
          sessionKey: 'agent:a1:main',
          agentId: 'a1',
        );

        final messages = <Message>[];
        conn.messageCtrl.stream.listen(messages.add);

        // Seed a delta so lifecycle.end has a non-empty buffer.
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'chat',
            payload: {
              'sessionKey': 'agent:a1:main',
              'state': 'delta',
              'deltaText': 'buffered',
            },
          ),
        );

        // lifecycle.end consumes the buffer.
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'agent',
            payload: {
              'sessionKey': 'agent:a1:main',
              'stream': 'lifecycle',
              'data': {'phase': 'end'},
            },
          ),
        );

        // chat.final should be ignored because already finalized.
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'chat',
            payload: {
              'sessionKey': 'agent:a1:main',
              'state': 'final',
              'message': {
                'clientId': 'c1',
                'role': 'agent',
                'content': 'final msg',
                'type': 'text',
              },
            },
          ),
        );

        await pumpEventQueue();
        expect(messages, hasLength(1));
      },
    );
  });
}
