// Phase 3 → Phase 4: v2026.6.10 tool event WITHOUT sessionKey in payload.
//
// Hypothesis: v2026.6.10 tool events (itemId `command:call_...`) don't include
// `sessionKey` at the payload level — only inside data. This means
// `event.sessionKey` defaults to '' (empty), and ToolCall.messageId would
// also be empty without the fix. When the final agent message arrives with
// `sessionKey` in its metadata, the re-key lookup `state.toolCalls[sessionKey]`
// misses the empty key entry, so the live ToolCall never makes it under the
// message's clientId.
//
// Fix: GatewayEventProcessor._resolveToolMessageId() resolves ToolCall.messageId
// with priority: (1) explicit event.sessionKey, (2) toolCallId reverse-map
// match, (3) latest-registered sessionKey for the instance, (4) ''.
//
// The original RED test now verifies GREEN: ToolCall.messageId is the resolved
// sessionKey 'agent:a1:main', not the empty string.

import 'dart:async';

import 'package:claw_hub/core/acl/gateway_domain_mapper.dart';
import 'package:claw_hub/core/acl/gateway_event_processor.dart';
import 'package:claw_hub/core/acl/gateway_instance_connection.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

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
      pairingInfoCtrl: StreamController.broadcast(),
      streamingCtrl: StreamController<StreamingEvent>.broadcast(),
    );
  });

  tearDown(() async {
    await conn.dispose();
  });

  test('v2026.6.10 tool event WITHOUT sessionKey resolves messageId via '
      'latest-registered sessionKey (GREEN)', () async {
    processor.registerSend(
      instanceId: 'inst-1',
      sessionKey: 'agent:a1:main',
      agentId: 'a1',
    );

    final tools = <ToolCall>[];
    conn.toolCallCtrl.stream.listen(tools.add);

    // Simulate v2026.6.10 tool end event — NO sessionKey in payload.
    // sessionKey is implicitly known via the registration mapping.
    // ToolCall.messageId MUST be the resolved sessionKey, not ''.
    processor.processEvent(
      'inst-1',
      conn,
      const EventFrame(
        event: 'agent',
        payload: {
          'data': {
            'itemId': 'command:call_abc',
            'phase': 'end',
            'toolCallId': 'call_abc',
            'name': 'exec',
            'output': '-rw-r--r-- 1 root root 17125 ...',
            'exitCode': 0,
          },
        },
      ),
    );

    await pumpEventQueue();
    expect(tools, hasLength(1), reason: 'tool event must not be dropped');
    expect(
      tools.first.messageId,
      'agent:a1:main',
      reason:
          'ToolCall.messageId must be the resolved sessionKey even when '
          'payload.sessionKey is absent. Otherwise ChatViewModel '
          '_rekeyToolCallForMessage cannot match the tool call to the '
          'final agent message, and ToolCallCard never renders in '
          'real-time (repro: "exec cards only show after app re-enter").',
    );
  });

  test('multi-session fallback: empty sessionKey + no toolCallId match '
      '→ latest-registered sessionKey (LIFO)', () async {
    // Register 2 sessions — the second is the "active" one for a
    // single-instance chat UX (1 active session per instance at a time).
    processor.registerSend(
      instanceId: 'inst-1',
      sessionKey: 'agent:a1:main',
      agentId: 'a1',
    );
    processor.registerSend(
      instanceId: 'inst-1',
      sessionKey: 'agent:a2:main',
      agentId: 'a2',
    );

    final tools = <ToolCall>[];
    conn.toolCallCtrl.stream.listen(tools.add);

    // v2026.6.10 event with no sessionKey AND a toolCallId that hasn't
    // been seen before (so the reverse-map misses too). Must fall back
    // to the latest-registered sessionKey.
    processor.processEvent(
      'inst-1',
      conn,
      const EventFrame(
        event: 'agent',
        payload: {
          'data': {
            'itemId': 'command:call_xyz',
            'phase': 'end',
            'toolCallId': 'call_xyz',
            'name': 'exec',
            'output': 'ls output',
            'exitCode': 0,
          },
        },
      ),
    );

    await pumpEventQueue();
    expect(tools, hasLength(1));
    expect(
      tools.first.messageId,
      'agent:a2:main',
      reason:
          'fallback must pick latest-registered sessionKey '
          '(LinkedHashSet preserves insertion order, .last = LIFO)',
    );
  });

  test(
    'toolCallId reverse-map: start (v2026.6.6 sessionKey) + end '
    '(v2026.6.10 no sessionKey, same toolCallId) → end inherits start sessionKey',
    () async {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );

      final tools = <ToolCall>[];
      conn.toolCallCtrl.stream.listen(tools.add);

      // Start event WITH sessionKey (v2026.6.6 path). Populates
      // _toolCallIdToSessionKey['call_hybrid'] = 'agent:a1:main'.
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'agent',
          payload: {
            'sessionKey': 'agent:a1:main',
            'stream': 'tool',
            'data': {
              'itemId': 'command:call_hybrid',
              'phase': 'start',
              'toolCallId': 'call_hybrid',
              'name': 'exec',
            },
          },
        ),
      );

      // End event WITHOUT sessionKey (v2026.6.10 shape) but same
      // toolCallId. The reverse-map must return 'agent:a1:main' from
      // the start event above, NOT the fallback chain.
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'agent',
          payload: {
            'data': {
              'itemId': 'command:call_hybrid',
              'phase': 'end',
              'toolCallId': 'call_hybrid',
              'name': 'exec',
              'output': 'done',
              'exitCode': 0,
            },
          },
        ),
      );

      await pumpEventQueue();
      expect(tools, hasLength(2));
      expect(tools[0].messageId, 'agent:a1:main');
      expect(
        tools[1].messageId,
        'agent:a1:main',
        reason:
            'end event must inherit sessionKey from the start event '
            'via the toolCallId reverse-map, not fall through to '
            'instance-fallback (which could be wrong on a different '
            'active session)',
      );
    },
  );

  test('empty sessionKey + 0 registered sessions → messageId "" '
      '(VM guard case)', () async {
    // Deliberately do NOT call registerSend. No sessionKey is
    // registered for this instance. Fallback chain returns ''.
    final tools = <ToolCall>[];
    conn.toolCallCtrl.stream.listen(tools.add);

    processor.processEvent(
      'inst-1',
      conn,
      const EventFrame(
        event: 'agent',
        payload: {
          'data': {
            'itemId': 'command:call_orphan',
            'phase': 'end',
            'toolCallId': 'call_orphan',
            'name': 'exec',
            'output': '',
            'exitCode': 0,
          },
        },
      ),
    );

    await pumpEventQueue();
    expect(tools, hasLength(1));
    expect(
      tools.first.messageId,
      '',
      reason:
          'when no sessions are registered and no reverse-map hit, '
          'ToolCall.messageId is "". The VM-level guard in '
          'ChatViewModel then drops the event with an error log — '
          'no silent state.toolCalls[""] pollution.',
    );
  });
}
