import 'dart:async';

import 'package:claw_hub/core/acl/gateway_domain_mapper.dart';
import 'package:claw_hub/core/acl/gateway_event_processor.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/acl/gateway_instance_connection.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLogger implements ILogger {
  final List<String> infos = [];
  final List<String> errors = [];

  @override
  void info(String message) => infos.add(message);

  @override
  void error(String message, [StackTrace? stackTrace]) => errors.add(message);
}

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

    // Review #1 (Option C): chat.final must tag the message with sessionKey
    // metadata so ChatViewModel can re-key the turn's ToolCalls from
    // sessionKey → clientId. Without this tag the keys live in different
    // namespaces and ToolCallCard never renders.
    test(
      'chat.final with message tags message with sessionKey (review #1)',
      () async {
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
        expect(messages.first.metadata?['sessionKey'], 'agent:a1:main');
      },
    );

    test('chat.final fallback (no message) tags message with sessionKey '
        '(review #1)', () async {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );

      final messages = <Message>[];
      conn.messageCtrl.stream.listen(messages.add);

      // Accumulate a buffer via chat.delta so the fallback path has text.
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'agent:a1:main',
            'state': 'delta',
            'deltaText': 'fallback text',
          },
        ),
      );
      // chat.final with no `message` → buildAgentFallbackMessage from buffer.
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {'sessionKey': 'agent:a1:main', 'state': 'final'},
        ),
      );

      await pumpEventQueue();
      expect(messages, hasLength(1));
      expect(messages.first.content, 'fallback text');
      expect(messages.first.metadata?['sessionKey'], 'agent:a1:main');
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

    // Review #3: tool result must extract event.data['output'], not stringify
    // the whole data map. Pre-fix outputResult was event.data.toString() →
    // "{toolCallId: tc-1, name: search, phase: result, output: {hits: 3}}",
    // surfacing the wrapper keys (toolCallId/name/phase) to the ToolCallCard.
    test(
      'agent.tool result extracts output field, not whole data map (#3)',
      () async {
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
              'data': {
                'phase': 'result',
                'toolCallId': 'tc-1',
                'name': 'search',
                'output': {'hits': 3},
              },
            },
          ),
        );

        await pumpEventQueue();
        expect(tools, hasLength(1));
        expect(tools.first.id, 'tc-1');
        expect(tools.first.toolName, 'search');
        expect(
          tools.first.outputResult,
          '{"hits":3}',
          reason:
              'outputResult should be the JSON-encoded `output` field, not the '
              'whole data map (which leaks toolCallId/name/phase to the card)',
        );
      },
    );

    // String outputs are preserved verbatim (not double-encoded).
    test(
      'agent.tool result with string output keeps it verbatim (#3)',
      () async {
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
              'data': {
                'phase': 'result',
                'toolCallId': 'tc-2',
                'name': 'echo',
                'output': 'pong',
              },
            },
          ),
        );

        await pumpEventQueue();
        expect(tools, hasLength(1));
        expect(
          tools.first.outputResult,
          'pong',
          reason:
              'string output must be stored verbatim, not jsonEncode-d to '
              '"pong" with quotes',
        );
      },
    );

    // v2026.6.10 drift: tool completion uses phase: 'end' (not 'result') and
    // carries exitCode / durationMs. phase: 'delta' is streaming output.
    // See memory openclaw-v2026-6-10-wire-format.
    test(
      'agent.tool phase=end with exitCode 0 → success (v2026.6.10)',
      () async {
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
              'data': {
                'phase': 'end',
                'toolCallId': 'tc-end',
                'name': 'exec',
                'output': '-rw-r--r-- 1 root root 17125 ...',
                'exitCode': 0,
                'durationMs': 21,
                'status': 'completed',
              },
            },
          ),
        );

        await pumpEventQueue();
        expect(tools, hasLength(1));
        expect(tools.first.id, 'tc-end');
        expect(tools.first.toolName, 'exec');
        expect(tools.first.status, ToolCallStatus.success);
        expect(tools.first.outputResult, '-rw-r--r-- 1 root root 17125 ...');
      },
    );

    test('agent.tool phase=end with non-zero exitCode → failed', () async {
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
            'data': {
              'phase': 'end',
              'toolCallId': 'tc-fail',
              'name': 'exec',
              'output': 'command not found',
              'exitCode': 127,
            },
          },
        ),
      );

      await pumpEventQueue();
      expect(tools, hasLength(1));
      expect(tools.first.status, ToolCallStatus.failed);
    });

    test(
      'agent.tool phase=delta → running ToolCall (v2026.6.10 streaming)',
      () async {
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
              'data': {
                'phase': 'delta',
                'toolCallId': 'tc-delta',
                'name': 'exec',
                'output': 'partial output',
                'status': 'running',
              },
            },
          ),
        );

        await pumpEventQueue();
        expect(tools, hasLength(1));
        expect(tools.first.status, ToolCallStatus.running);
      },
    );

    // The KEY fix: v2026.6.10 tool events have NO `stream` field — pre-fix
    // they hit AgentStreamType.unknown and were silently dropped, so users
    // never saw live tool execution. parseAgentEvent now infers tool.
    test(
      'null-stream tool event (itemId: command:*) routed to toolCallStream',
      () async {
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
              // NO 'stream' field — v2026.6.10 shape (capture-verified)
              'data': {
                'itemId': 'command:call_abc',
                'phase': 'end',
                'toolCallId': 'call_abc',
                'name': 'exec',
                'output': '-rw-r--r-- 1 root root 17125 ...',
                'status': 'completed',
                'exitCode': 0,
                'durationMs': 21,
              },
            },
          ),
        );

        await pumpEventQueue();
        expect(
          tools,
          hasLength(1),
          reason: 'null-stream tool event must not be dropped',
        );
        expect(tools.first.id, 'call_abc');
        expect(tools.first.toolName, 'exec');
        expect(tools.first.status, ToolCallStatus.success);
      },
    );

    // Review #1 (Option C): lifecycle.end fallback message must also carry the
    // sessionKey tag (v3 Gateway path that never sends chat.final).
    test(
      'lifecycle.end fallback tags message with sessionKey (review #1)',
      () async {
        processor.registerSend(
          instanceId: 'inst-1',
          sessionKey: 'agent:a1:main',
          agentId: 'a1',
        );

        final messages = <Message>[];
        conn.messageCtrl.stream.listen(messages.add);

        // Accumulate a buffer via agent.assistant so lifecycle.end has text.
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'agent',
            payload: {
              'sessionKey': 'agent:a1:main',
              'stream': 'assistant',
              'data': {'delta': 'le text'},
            },
          ),
        );
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

        await pumpEventQueue();
        expect(messages, hasLength(1));
        expect(messages.first.content, 'le text');
        expect(messages.first.metadata?['sessionKey'], 'agent:a1:main');
      },
    );
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

  group('unresolvable sessionKey log dedup', () {
    test(
      'logs error once for repeated deltas on same unresolvable key',
      () async {
        final logger = _RecordingLogger();
        final proc = GatewayEventProcessor(
          uuid: const Uuid(),
          mapper: GatewayDomainMapper(),
          logger: logger,
        );
        addTearDown(proc.dispose);

        final localConn = GatewayInstanceConnection(
          messageCtrl: StreamController<Message>.broadcast(),
          toolCallCtrl: StreamController<ToolCall>.broadcast(),
          pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
          streamingCtrl: StreamController<StreamingEvent>.broadcast(),
        );
        addTearDown(localConn.dispose);

        for (var i = 0; i < 5; i++) {
          proc.processEvent(
            'inst-1',
            localConn,
            const EventFrame(
              event: 'chat',
              payload: {
                'sessionKey': 'bad:session',
                'state': 'delta',
                'deltaText': 'delta',
              },
            ),
          );
        }

        await pumpEventQueue();
        expect(
          logger.errors
              .where((e) => e.contains('Cannot resolve agentId'))
              .length,
          1,
        );
      },
    );

    test('cleanupInstance resets dedup so error is logged again', () async {
      final logger = _RecordingLogger();
      final proc = GatewayEventProcessor(
        uuid: const Uuid(),
        mapper: GatewayDomainMapper(),
        logger: logger,
      );
      addTearDown(proc.dispose);

      final localConn = GatewayInstanceConnection(
        messageCtrl: StreamController<Message>.broadcast(),
        toolCallCtrl: StreamController<ToolCall>.broadcast(),
        pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
        streamingCtrl: StreamController<StreamingEvent>.broadcast(),
      );
      addTearDown(localConn.dispose);

      proc.processEvent(
        'inst-1',
        localConn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'bad:session',
            'state': 'delta',
            'deltaText': 'delta',
          },
        ),
      );
      await pumpEventQueue();
      expect(
        logger.errors.where((e) => e.contains('Cannot resolve agentId')).length,
        1,
      );

      proc.cleanupInstance('inst-1');

      proc.processEvent(
        'inst-1',
        localConn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'bad:session',
            'state': 'delta',
            'deltaText': 'delta',
          },
        ),
      );
      await pumpEventQueue();
      expect(
        logger.errors.where((e) => e.contains('Cannot resolve agentId')).length,
        2,
      );
    });
  });

  group('delta-source lock (cross-turn clearing)', () {
    // 回归:chat.final / lifecycle.end 必须清 _deltaSource,否则旧网关
    // (无 runId、无 lifecycle.start)下 _deltaSource 跨 turn 持续锁定首个源,
    // 下一 turn 的异源 delta 被 putIfAbsent 返回的旧源挡掉 → 回复丢失。
    test(
      'chat.final clears delta-source lock for next turn (no runId)',
      () async {
        processor.registerSend(
          instanceId: 'inst-1',
          sessionKey: 'agent:a1:main',
          agentId: 'a1',
          // 不传 runId —— 模拟旧网关,_resetTurnForSession 不触发。
        );

        final deltas = <StreamingEvent>[];
        conn.streamingCtrl.stream.listen(deltas.add);

        // Turn 1: chat.delta 锁 _deltaSource = 'chat'。
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'chat',
            payload: {
              'sessionKey': 'agent:a1:main',
              'state': 'delta',
              'deltaText': 'turn1',
            },
          ),
        );
        // Turn 1 经 chat.final 完成(带 message)。
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
                'content': 'final1',
                'type': 'text',
              },
            },
          ),
        );
        await pumpEventQueue();
        // turn1 StreamingDelta + StreamingDone;清空,只看 turn2。
        deltas.clear();

        // Turn 2:异源(agent.assistant)delta 先到。pre-fix:_deltaSource 仍 'chat'
        // → putIfAbsent 返回 'chat' → break,agent delta 被丢。post-fix:已清 → 接受。
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'agent',
            payload: {
              'sessionKey': 'agent:a1:main',
              'stream': 'assistant',
              'data': {'delta': 'turn2'},
            },
          ),
        );
        await pumpEventQueue();
        expect(
          deltas.whereType<StreamingDelta>(),
          hasLength(1),
          reason:
              'chat.final 必须清 _deltaSource,否则下一 turn 的 agent delta '
              '被旧源 "chat" 挡掉(回复丢失)。',
        );
        expect(deltas.whereType<StreamingDelta>().first.text, 'turn2');
      },
    );

    test(
      'lifecycle.end clears delta-source lock for next turn (no runId)',
      () async {
        processor.registerSend(
          instanceId: 'inst-1',
          sessionKey: 'agent:a1:main',
          agentId: 'a1',
        );

        final deltas = <StreamingEvent>[];
        conn.streamingCtrl.stream.listen(deltas.add);

        // Turn 1: chat.delta 锁 _deltaSource = 'chat'。
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'chat',
            payload: {
              'sessionKey': 'agent:a1:main',
              'state': 'delta',
              'deltaText': 'turn1',
            },
          ),
        );
        // Turn 1 经 lifecycle.end 完成(v3 路径,消费缓冲文本)。
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
        await pumpEventQueue();
        deltas.clear();

        // Turn 2:异源(agent.assistant)delta。
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'agent',
            payload: {
              'sessionKey': 'agent:a1:main',
              'stream': 'assistant',
              'data': {'delta': 'turn2'},
            },
          ),
        );
        await pumpEventQueue();
        expect(
          deltas.whereType<StreamingDelta>(),
          hasLength(1),
          reason: 'lifecycle.end 必须清 _deltaSource,否则下一 turn 异源 delta 被挡。',
        );
        expect(deltas.whereType<StreamingDelta>().first.text, 'turn2');
      },
    );
  });

  group('finalized-sessions cross-turn clearing', () {
    // 回归:_finalizedSessions(同 turn 内 chat.final/lifecycle.end 去重 guard)
    // 必须在 registerSend 时清,否则旧网关(无 runId → _resetTurnForSession 跳过、
    // 无 lifecycle.start)下该 key 跨 turn 持续存在,下一 turn 的 chat.final 被
    // 当作重复丢弃 → 回复丢失。
    test(
      'registerSend clears _finalizedSessions so next turn chat.final is not dropped (no runId)',
      () async {
        processor.registerSend(
          instanceId: 'inst-1',
          sessionKey: 'agent:a1:main',
          agentId: 'a1',
          // 不传 runId —— 模拟旧网关,_resetTurnForSession 不触发。
        );
        final messages = <Message>[];
        conn.messageCtrl.stream.listen(messages.add);

        // Turn 1: chat.final 带 message。
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
                'content': 'turn1',
                'type': 'text',
              },
            },
          ),
        );
        await pumpEventQueue();
        expect(messages, hasLength(1));

        // Turn 2:用户再发 → registerSend(无 runId)。
        processor.registerSend(
          instanceId: 'inst-1',
          sessionKey: 'agent:a1:main',
          agentId: 'a1',
        );

        // Turn 2: chat.final 带 message。pre-fix:_finalizedSessions 仍有该 key
        // → add 返回 false → 早退 → turn 2 消息被丢。
        // post-fix:registerSend 已清 → 接受。
        processor.processEvent(
          'inst-1',
          conn,
          const EventFrame(
            event: 'chat',
            payload: {
              'sessionKey': 'agent:a1:main',
              'state': 'final',
              'message': {
                'clientId': 'c2',
                'role': 'agent',
                'content': 'turn2',
                'type': 'text',
              },
            },
          ),
        );
        await pumpEventQueue();
        expect(
          messages,
          hasLength(2),
          reason:
              'registerSend 必须清 _finalizedSessions,否则 turn 2 的 '
              'chat.final 被当作重复丢弃',
        );
        expect(messages.last.content, 'turn2');
      },
    );
  });

  group('no-runId aborted-turn buffer clearing (#2)', () {
    // Review #2: registerSend on the no-runId path must also clear the
    // streaming buffer + delta-source lock. An aborted prior turn (delta
    // arrived, no chat.final / lifecycle.end) leaves a non-empty buffer that
    // the next turn's deltas append to (stale_turn1 + turn2 corruption).
    // With runId, _resetTurnForSession handles this; the no-runId else-branch
    // previously only cleared _finalizedSessions.
    test('registerSend (no runId) clears stale buffer so next turn is not '
        'corrupted with prior-turn text', () async {
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
        // no runId — simulates an old Gateway, _resetTurnForSession skipped
      );

      final messages = <Message>[];
      conn.messageCtrl.stream.listen(messages.add);

      // Turn 1: chat.delta accumulates 'turn1' into the buffer.
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'agent:a1:main',
            'state': 'delta',
            'deltaText': 'turn1',
          },
        ),
      );

      // Turn 1 is ABORTED — no chat.final, no lifecycle.end. The buffer
      // retains 'turn1'.

      // Turn 2: user sends again → registerSend (no runId).
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );

      // Turn 2: chat.delta 'turn2' + lifecycle.end (v3 fallback consumes
      // the buffer). Pre-fix: buffer = 'turn1' + 'turn2' → fallback message
      // 'turn1turn2'. Post-fix: registerSend cleared the buffer → 'turn2'.
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'agent:a1:main',
            'state': 'delta',
            'deltaText': 'turn2',
          },
        ),
      );
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
      await pumpEventQueue();

      expect(messages, hasLength(1));
      expect(
        messages.first.content,
        'turn2',
        reason:
            'registerSend (no runId) must clear the stale prior-turn '
            'buffer — pre-fix the aborted turn-1 text "turn1" was prepended '
            'to turn-2 ("turn1turn2"), corrupting the reply',
      );
    });
  });

  group('streaming buffer GC (aging)', () {
    test('_gcStaleSessions ages out abandoned streaming buffers', () async {
      // 注入小 gcMaxAge + gcInterval=1(GC 每次 registerSend 触发)。
      processor = GatewayEventProcessor(
        uuid: const Uuid(),
        mapper: GatewayDomainMapper(),
        logger: const DebugPrintLogger(),
        gcMaxAge: const Duration(milliseconds: 10),
        gcInterval: 1,
      );
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );
      // 发 delta → buffer 创建,lastUpdatedAt = now。
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'agent:a1:main',
            'state': 'delta',
            'deltaText': 'abandoned-mid-stream',
          },
        ),
      );
      await pumpEventQueue();
      expect(processor.streamingBuffersSizeForTesting, 1);

      // 等过 gcMaxAge,使 buffer 变 stale。
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 为另一 session registerSend 触发 GC(interval=1);a1 buffer 30ms 未动
      // > 10ms → 老化掉。
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a2:main',
        agentId: 'a2',
      );
      expect(
        processor.streamingBuffersSizeForTesting,
        0,
        reason: '超过 gcMaxAge 的 abandoned buffer 应被 GC 清理',
      );
    });

    test('GC keeps fresh buffers (within gcMaxAge)', () async {
      processor = GatewayEventProcessor(
        uuid: const Uuid(),
        mapper: GatewayDomainMapper(),
        logger: const DebugPrintLogger(),
        gcMaxAge: const Duration(minutes: 30),
        gcInterval: 1,
      );
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a1:main',
        agentId: 'a1',
      );
      processor.processEvent(
        'inst-1',
        conn,
        const EventFrame(
          event: 'chat',
          payload: {
            'sessionKey': 'agent:a1:main',
            'state': 'delta',
            'deltaText': 'fresh',
          },
        ),
      );
      await pumpEventQueue();
      expect(processor.streamingBuffersSizeForTesting, 1);

      // registerSend 立即触发 GC(interval=1);buffer 刚创建(在 30min 内)→ 保留。
      processor.registerSend(
        instanceId: 'inst-1',
        sessionKey: 'agent:a2:main',
        agentId: 'a2',
      );
      expect(
        processor.streamingBuffersSizeForTesting,
        1,
        reason: 'fresh buffer(在 gcMaxAge 内)不应被 GC 清掉',
      );
    });
  });
}
