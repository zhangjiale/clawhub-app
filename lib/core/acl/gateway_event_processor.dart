import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';
import '../i_logger.dart';
import 'gateway_domain_mapper.dart';
import 'gateway_instance_connection.dart';
import 'gateway_protocol.dart';

/// Gateway 协议事件处理器。
///
/// 职责：把原始 [EventFrame] 转换为领域事件并写入对应广播流；维护 streaming
/// buffer、runId 转场、session→agent 映射等流式状态。
///
/// 每个 [WsGatewayClient] 实例持有唯一一个 processor；processor 本身不持有
/// WebSocket 连接，只处理事件与状态。
class GatewayEventProcessor {
  final Uuid _uuid;
  final GatewayDomainMapper _mapper;
  final ILogger _logger;

  GatewayEventProcessor({
    required this._uuid,
    required this._mapper,
    required this._logger,
    this._gcMaxAge = const Duration(minutes: 30),
    this._gcInterval = 100,
  });

  /// Max age before an abandoned streaming buffer is GC'd. Default 30min;
  /// tests inject a small value to exercise [_gcStaleSessions] without
  /// waiting.
  final Duration _gcMaxAge;

  /// Run [_gcStaleSessions] every Nth [registerSend]. Default 100; tests
  /// inject 1 to trigger on every call.
  final int _gcInterval;

  int _registerSendCount = 0;

  /// Delta 聚合缓冲区: sessionKey → StreamingBuffer。
  /// agent assistant 事件追加 delta，chat final 事件消费后移除。
  final Map<String, StreamingBuffer> _streamingBuffers = {};

  /// Tracks sessions that have already been finalized (Message pushed +
  /// StreamingDone emitted) to prevent duplicate messages when both
  /// chat.final and agent.lifecycle.end arrive for the same session.
  ///
  /// Key format: `$instanceId:$sessionKey` (same as [_streamingBuffers]).
  /// The first handler to `add()` this key processes the session; the
  /// second handler sees the key already present and skips.
  final Set<String> _finalizedSessions = {};

  /// Tracks which event source serves streaming deltas per session.
  /// Value is 'chat' or 'agent'. Prevents duplicate deltas when a Gateway
  /// sends both `chat.delta` and `agent.assistant` events for the same
  /// response — whichever arrives first locks in the source, and deltas
  /// from the other source are dropped.
  final Map<String, String> _deltaSource = {};

  /// Active server-assigned `runId` for the current turn, per session.
  ///
  /// Key format: `$instanceId:$sessionKey` (same as [_streamingBuffers]).
  /// `runId` is the server-authoritative per-turn identifier (parsed on
  /// `chat`/`agent` events and returned by the `chat.send` response).
  ///
  /// A streaming buffer belongs to exactly one turn. `sessionKey` is
  /// stable across turns for the same agent, so without this pointer a
  /// turn aborted before its `lifecycle.end`/`chat.final` (e.g. a
  /// graceful-shutdown reconnect, which lives inside `ConnectionManager`
  /// and never reaches [_cleanup]) leaves a non-empty buffer that the
  /// next turn's deltas `.append()` to — corrupting the reply with
  /// `stale_turn1 + turn2`.
  ///
  /// When the `runId` for a session changes, the prior buffer is
  /// irrecoverably stale and is dropped (see [_resetTurnForSession]).
  /// A missing `runId` (older Gateways) leaves this map untouched — the
  /// degradation path preserves the no-runId behavior pinned by the
  /// "chat.delta arriving before lifecycle.start is not dropped" test.
  final Map<String, String> _activeRunIdBySession = {};

  /// Explicit mapping from sessionKey → remoteAgentId.
  ///
  /// Populated by [registerSend].
  /// Events dispatch look up agentId via this table instead
  /// of parsing the colon-separated sessionKey string — that heuristic is
  /// unreliable when Gateway uses alternative sessionKey formats.
  ///
  /// Keys are bare sessionKeys (e.g. `agent:r-1:main`), NOT prefixed with
  /// instanceId. The reverse index [_sessionKeysByInstance] tracks which
  /// keys belong to which instance so [cleanupInstance] can drop the right ones.
  final Map<String, String> _sessionToAgentId = {};

  /// Reverse index: instanceId → set of sessionKeys owned by that instance.
  ///
  /// Used by [cleanupInstance] to remove the instance's entries from
  /// [_sessionToAgentId]. Without this index, _sessionToAgentId would
  /// only be cleared in [WsGatewayClient.dispose], leaking entries across
  /// instance churn (add → remove → add → …).
  final Map<String, Set<String>> _sessionKeysByInstance = {};

  /// Tracks sessionKeys that have already been logged as unresolvable so a
  /// long streaming turn with hundreds of deltas does not emit hundreds of
  /// identical error logs. Cleared when the corresponding instance is cleaned
  /// up or the processor is disposed.
  final Set<String> _unresolvableSessionKeys = <String>{};

  /// 测试缝隙 — 返回 [_sessionToAgentId] 当前条目数。
  ///
  /// 用于验证实例断开后映射被正确清理（防内存泄漏）。只在测试中调用。
  int get sessionToAgentIdSizeForTesting => _sessionToAgentId.length;

  /// 测试缝隙 — 返回 [_sessionKeysByInstance] 反向索引中的 sessionKey 总数。
  ///
  /// 用于验证失败的 sendMessage 不会泄露反向索引条目（与
  /// [sessionToAgentIdSizeForTesting] 配对，覆盖两个映射）。只在测试中调用。
  int get sessionKeysByInstanceSizeForTesting =>
      _sessionKeysByInstance.values.fold<int>(0, (n, s) => n + s.length);

  /// 测试缝隙 — 返回 [_streamingBuffers] 当前条目数。用于验证 [_gcStaleSessions]
  /// 老化掉 abandoned buffer。只在测试中调用。
  int get streamingBuffersSizeForTesting => _streamingBuffers.length;

  /// Registers a successful [sendMessage] outcome with this processor.
  ///
  /// - Maps [sessionKey] → [agentId] for event dispatch.
  /// - If [runId] is non-null, resets the prior turn's streaming state so
  ///   an aborted prior turn cannot corrupt the new reply.
  void registerSend({
    required String instanceId,
    required String sessionKey,
    required String agentId,
    String? runId,
  }) {
    _sessionToAgentId[sessionKey] = agentId;
    (_sessionKeysByInstance[instanceId] ??= {}).add(sessionKey);

    final bufferKey = '$instanceId:$sessionKey';

    // Turn-boundary clear of the finalized flag: registerSend fires on every
    // user send, marking a new turn for this session. Without this, old
    // Gateways (no runId → _resetTurnForSession skipped, no lifecycle.start)
    // would see _finalizedSessions persist from the prior turn and drop THIS
    // turn's chat.final as a duplicate. When runId IS present,
    // _resetTurnForSession clears it (plus buffer / delta-source / active
    // runId); the else branch covers the no-runId path.
    if (runId != null) {
      _resetTurnForSession(bufferKey, runId);
    } else {
      // Review #2: clear the streaming buffer + delta-source lock too. An
      // aborted prior turn (delta arrived, no chat.final / lifecycle.end)
      // leaves a non-empty buffer that this turn's deltas append to
      // (stale_turn1 + turn2 corruption), and a delta-source lock that
      // drops this turn's cross-source deltas. Safe because registerSend
      // fires on the chat.send response — before any of this turn's deltas
      // arrive — so clearing here only drops the prior turn's residue.
      // _activeRunIdBySession is runId-specific and never populated on the
      // no-runId path, so it is left untouched (preserves the documented
      // no-runId degradation; see _applyRunId).
      _finalizedSessions.remove(bufferKey);
      _streamingBuffers.remove(bufferKey);
      _deltaSource.remove(bufferKey);
    }

    // Periodic GC: age out abandoned streaming buffers (mid-stream turns
    // that never received chat.final / lifecycle.end). Bounded O(agents)
    // so this is hygiene, not a correctness fix — but abandoned buffers
    // hold accumulated delta text (KB-scale), the only non-trivial leak.
    if (++_registerSendCount % _gcInterval == 0) {
      _gcStaleSessions();
    }
  }

  /// Remove streaming buffers untouched for longer than [_gcMaxAge].
  ///
  /// Only [_streamingBuffers] is aged — it holds accumulated delta text
  /// (KB-scale per abandoned mid-stream turn). [_finalizedSessions] /
  /// [_deltaSource] / [_activeRunIdBySession] are tiny (keys / short
  /// strings), cleared on turn boundaries + [cleanupInstance]; not worth
  /// timestamping.
  void _gcStaleSessions() {
    final cutoff = DateTime.now().subtract(_gcMaxAge).millisecondsSinceEpoch;
    _streamingBuffers.removeWhere((_, b) => b.lastUpdatedAt < cutoff);
  }

  /// Clears all processor state. Called when the owning client is disposed.
  void dispose() {
    _streamingBuffers.clear();
    _finalizedSessions.clear();
    _deltaSource.clear();
    _activeRunIdBySession.clear();
    _sessionToAgentId.clear();
    _sessionKeysByInstance.clear();
    _unresolvableSessionKeys.clear();
  }

  /// Clears all per-instance streaming state and session mappings.
  void cleanupInstance(String instanceId) {
    _streamingBuffers.removeWhere((key, _) => key.startsWith('$instanceId:'));
    _finalizedSessions.removeWhere((key) => key.startsWith('$instanceId:'));
    _deltaSource.removeWhere((key, _) => key.startsWith('$instanceId:'));
    _activeRunIdBySession.removeWhere(
      (key, _) => key.startsWith('$instanceId:'),
    );

    final ownedKeys = _sessionKeysByInstance.remove(instanceId);
    if (ownedKeys != null) {
      for (final key in ownedKeys) {
        _sessionToAgentId.remove(key);
      }
    }
    // Reset the unresolvable log-dedup set when an instance is cleaned up.
    // This is instance-level dedup in the sense that a fresh connection context
    // for any instance gets a fresh error log for a previously-unresolvable key.
    _unresolvableSessionKeys.clear();
  }

  /// Processes a single Gateway event frame for [instanceId].
  void processEvent(
    String instanceId,
    GatewayInstanceConnection conn,
    EventFrame event,
  ) {
    final payload = event.payload;
    if (payload == null) return;

    switch (event.event) {
      case Events.chat:
        _onChatEvent(instanceId, conn, payload);

      case Events.agent:
        _onAgentEvent(instanceId, conn, payload);

      case Events.payloadLarge:
        // Gap #6: Gateway told us we sent an over-sized payload. Surface
        // it on the diagnostic stream so the UI can show a user-visible
        // hint instead of silently dropping the message. Wrap in try/catch
        // so a downstream listener exception doesn't break the router
        // (which would also affect chat/agent events on the same channel).
        try {
          final notice = parseLargePayloadEvent(payload);
          if (!conn.gatewayNoticeCtrl.isClosed) {
            conn.gatewayNoticeCtrl.add(notice);
          }
        } catch (error, stackTrace) {
          _logger.error(
            '[WsGateway] Failed to handle payload.large for $instanceId: '
            '$error',
            stackTrace,
          );
        }

      default:
        break;
    }
  }

  /// Drop all per-session streaming state for [bufferKey] and stamp [runId]
  /// as the active turn.
  ///
  /// Called at a turn boundary — most authoritatively from the `chat.send`
  /// response (the server assigns `runId` before any deltas), and as a
  /// fallback from `lifecycle.start` / a differing-`runId` delta when a
  /// turn begins without a fresh `chat.send`. Dropping the buffer here
  /// prevents an aborted prior turn (no `lifecycle.end`/`chat.final`
  /// ever arrived) from corrupting the new turn's reply.
  ///
  /// [runId] must be the server-sent value (non-null). Callers gate on
  /// null themselves so the no-`runId` degradation path is preserved.
  void _resetTurnForSession(String bufferKey, String runId) {
    _streamingBuffers.remove(bufferKey);
    _finalizedSessions.remove(bufferKey);
    _deltaSource.remove(bufferKey);
    _activeRunIdBySession[bufferKey] = runId;
  }

  /// Record [runId] as the active turn for [bufferKey].
  ///
  /// - [runId] `null` → no-op (degradation for older Gateways that don't
  ///   send `runId`; current behavior is preserved).
  /// - [runId] differs from the active turn → turn boundary: drop the
  ///   prior turn's streaming state via [_resetTurnForSession].
  /// - [runId] equals the active turn (or none is recorded yet) → just
  ///   stamp it as active; buffer is untouched.
  void _applyRunId(String bufferKey, String? runId) {
    if (runId == null) return;
    final active = _activeRunIdBySession[bufferKey];
    if (active != null && active != runId) {
      _resetTurnForSession(bufferKey, runId);
    } else {
      _activeRunIdBySession[bufferKey] = runId;
    }
  }

  /// `chat` 事件 — Gateway v2026.6.6 UI 面向前端事件。
  ///
  /// - `state: "delta"` → 增量文本（含 deltaText）
  /// - `state: "final"` → 响应完成，携带完整 message 对象
  void _onChatEvent(
    String instanceId,
    GatewayInstanceConnection conn,
    Map<String, dynamic> payload,
  ) {
    final event = parseChatEvent(payload);
    // Scope streaming buffers by instanceId to prevent per-instance
    // disconnect from dropping other instances' in-progress aggregation.
    final bufferKey = '$instanceId:${event.sessionKey}';

    switch (event.state) {
      case ChatState.delta:
        if (event.deltaText != null && event.deltaText!.isNotEmpty) {
          // runId turn-token: a differing runId means a new turn began
          // without a fresh chat.send (agent self-branch / tool
          // continuation). Drop the stale prior-turn buffer before
          // appending. Absent runId → degradation (keep current behavior).
          _applyRunId(bufferKey, event.runId);

          // Dedup: if agent source already locked for this session, skip
          final source = _deltaSource.putIfAbsent(bufferKey, () => 'chat');
          if (source != 'chat') break;

          // Resolve agentId from sessionKey (explicit mapping → string parse)
          final agentId = _resolveAgentId(event.sessionKey);
          if (agentId == null) return; // unresolvable, drop event

          // Push typed streaming event to UI
          if (!conn.streamingCtrl.isClosed) {
            conn.streamingCtrl.add(
              StreamingDelta(agentId: agentId, text: event.deltaText!),
            );
          }
          // Also maintain aggregation buffer (fallback)
          _streamingBuffers
              .putIfAbsent(
                bufferKey,
                () => StreamingBuffer(sessionKey: event.sessionKey),
              )
              .append(event.deltaText!);
        }

      case ChatState.final_:
        // 响应完成 — 优先用 message 对象，回退到聚合文本
        if (conn.messageCtrl.isClosed) return;

        // Coordinate with agent.lifecycle.end — only one handler per
        // session may finalize (push Message + StreamingDone) to prevent
        // duplicate messages when a v3 Gateway sends both event types.
        if (!_finalizedSessions.add(bufferKey)) {
          _streamingBuffers.remove(bufferKey);
          _deltaSource.remove(bufferKey);
          return;
        }

        String? agentId;

        try {
          final msgJson = event.message;
          agentId =
              msgJson?['agentId'] as String? ??
              _resolveAgentId(event.sessionKey);

          if (msgJson != null) {
            // chat final event 自带完整 message，直接解析
            final parsed = _mapper.parseMessage(msgJson);
            // Tag with sessionKey so ChatViewModel can re-key the turn's
            // ToolCalls from sessionKey → clientId (review #1, Option C).
            conn.messageCtrl.add(
              parsed.copyWith(
                metadata: <String, dynamic>{
                  ...?parsed.metadata,
                  'sessionKey': event.sessionKey,
                },
              ),
            );
          } else {
            // 没有 message 对象时，用聚合文本构建
            final buffer = _streamingBuffers.remove(bufferKey);
            if (buffer != null && buffer.text.isNotEmpty) {
              conn.messageCtrl.add(
                _mapper
                    .buildAgentFallbackMessage(agentId ?? '', buffer.text)
                    .copyWith(
                      metadata: <String, dynamic>{
                        'sessionKey': event.sessionKey,
                      },
                    ),
              );
            }
          }
        } catch (error, stackTrace) {
          _logger.error(
            '[WsGateway] Failed to handle chat final: $error',
            stackTrace,
          );
        }
        _streamingBuffers.remove(bufferKey);
        // Turn complete — clear the delta-source lock + active runId so the
        // next turn starts clean (also reset by _resetTurnForSession on the
        // next boundary). Without this, _deltaSource persists across turns
        // on old Gateways (no runId / no lifecycle.start) and would drop the
        // next turn's cross-source deltas.
        _deltaSource.remove(bufferKey);
        _activeRunIdBySession.remove(bufferKey);

        // Notify UI that streaming is complete — only when we have
        // a resolvable agentId; otherwise ChatViewModel silently drops
        // StreamingDone('') and a pending _flushTimer republishes the
        // stale buffer as a ghost bubble.
        if (agentId != null && !conn.streamingCtrl.isClosed) {
          conn.streamingCtrl.add(StreamingDone(agentId: agentId));
        }

      case ChatState.unknown:
        break;
    }
  }

  /// `agent` 事件 — Gateway v2026.6.6 后端事件。
  ///
  /// - `stream: "tool"` → 工具调用 (phase: "start" = 开始, "result" = 结束)
  /// - `stream: "assistant"` → 助手文本生成
  /// - `stream: "lifecycle"` → 生命周期 (phase: "start"/"end")
  /// - `stream: "item"` → 工具调用项
  void _onAgentEvent(
    String instanceId,
    GatewayInstanceConnection conn,
    Map<String, dynamic> payload,
  ) {
    final event = parseAgentEvent(payload);
    final bufferKey = '$instanceId:${event.sessionKey}';

    switch (event.stream) {
      case AgentStreamType.tool:
        // 安全提取:网关若把 phase 序列化为 int/bool/double,`as String?`
        // 会同步抛 TypeError,且此处位于 try/catch 之外,导致整帧事件丢失。
        final phase = switch (event.data['phase']) {
          final String s => s,
          _ => null,
        };
        // v2026.6.6: phase='result'; v2026.6.10: phase='end'(带 exitCode/durationMs)。
        if (phase == 'result' || phase == 'end') {
          // tool 结束 — 发出带结果的 ToolCall
          if (!conn.toolCallCtrl.isClosed) {
            try {
              // Review #3: extract event.data['output'] rather than stringifying
              // the whole data map — pre-fix the ToolCallCard rendered the
              // wrapper keys (toolCallId/name/phase) as the result text.
              // Strings stay verbatim (not double-encoded); structured output
              // (Map/List/num/bool) is JSON-encoded to match the
              // `outputResult` "JSON 格式输出结果" contract on [ToolCall].
              final rawOutput = event.data['output'];
              final outputResult = rawOutput is String
                  ? rawOutput
                  : (rawOutput == null ? null : jsonEncode(rawOutput));
              // v2026.6.10 exec 工具:exitCode != 0 → failed;缺省/0 → success。
              // 用 num 而非 int,兼容 JS 序列化产生的 double(如 127.0)。
              final exitCode = event.data['exitCode'];
              final isFailed = exitCode is num && exitCode != 0;
              final tc = ToolCall(
                id: event.data['toolCallId'] as String? ?? _uuid.v4(),
                messageId: event.sessionKey,
                toolName: event.data['name'] as String? ?? 'unknown',
                status: isFailed
                    ? ToolCallStatus.failed
                    : ToolCallStatus.success,
                outputResult: outputResult,
                endedAt: DateTime.now().millisecondsSinceEpoch,
              );
              conn.toolCallCtrl.add(tc);
            } catch (error, stackTrace) {
              _logger.error(
                '[WsGateway] Failed to parse tool result: $error',
                stackTrace,
              );
            }
          }
        } else {
          // tool 开始/增量 — 发出 running 状态的 ToolCall。
          // v2026.6.10 delta 事件带 output/inputArgs;即使终端 end 事件丢失,
          // 最后一条 delta 的输出仍能保留在卡片上。
          if (!conn.toolCallCtrl.isClosed) {
            try {
              final rawOutput = event.data['output'];
              final outputResult = rawOutput is String
                  ? rawOutput
                  : (rawOutput == null ? null : jsonEncode(rawOutput));
              final rawInput = event.data['inputArgs'];
              final inputArgs = rawInput is String
                  ? rawInput
                  : (rawInput == null ? null : jsonEncode(rawInput));
              final tc = ToolCall(
                id: event.data['toolCallId'] as String? ?? _uuid.v4(),
                messageId: event.sessionKey,
                toolName: event.data['name'] as String? ?? 'unknown',
                status: ToolCallStatus.running,
                inputArgs: inputArgs,
                outputResult: outputResult,
                startedAt: DateTime.now().millisecondsSinceEpoch,
              );
              conn.toolCallCtrl.add(tc);
            } catch (error, stackTrace) {
              _logger.error(
                '[WsGateway] Failed to parse tool call: $error',
                stackTrace,
              );
            }
          }
        }

      case AgentStreamType.message:
      case AgentStreamType.assistant:
        // v3 "message" / v4 "assistant" — semantically equivalent delta
        // streaming.  Both carry delta text in data.delta.  Push to UI
        // AND accumulate in buffer for fallback message construction
        // (v3 Gateway may send only agent events, no chat events).
        {
          final delta = event.data['delta'] as String?;
          if (delta != null && delta.isNotEmpty) {
            // runId turn-token (see _onChatEvent delta branch): a differing
            // runId signals a new turn began without a fresh chat.send.
            _applyRunId(bufferKey, event.runId);

            // Dedup: if chat source already locked for this session, skip
            final source = _deltaSource.putIfAbsent(bufferKey, () => 'agent');
            if (source != 'agent') break;

            final agentId = _resolveAgentId(event.sessionKey);
            if (agentId == null) break;
            if (!conn.streamingCtrl.isClosed) {
              conn.streamingCtrl.add(
                StreamingDelta(agentId: agentId, text: delta),
              );
            }
            _streamingBuffers
                .putIfAbsent(
                  bufferKey,
                  () => StreamingBuffer(sessionKey: event.sessionKey),
                )
                .append(delta);
          }
        }

      case AgentStreamType.lifecycle:
        // Gateway v3 protocol: lifecycle events signal agent run boundaries.
        {
          final phase = event.data['phase'] as String?;
          if (phase == 'start') {
            // runId turn-token (secondary boundary): if the server emits
            // a lifecycle.start whose runId differs from the active turn,
            // a new turn began — drop the stale prior-turn buffer. This
            // is the case Fix 7's conditional clear below could not
            // handle (it only cleared empty buffers). Same/absent runId
            // falls through to the existing conditional clear, preserving
            // the "chat.delta arriving before lifecycle.start is not
            // dropped" regression test.
            _applyRunId(bufferKey, event.runId);

            // A new agent run has begun — clear the previous turn's
            // dedup token so _finalizedSessions does not permanently
            // block subsequent messages to the same agent (the key is
            // `$instanceId:$sessionKey` which is identical across turns).
            // This also allows the next lifecycle.end or chat.final for
            // this session to process normally.
            _finalizedSessions.remove(bufferKey);
            _deltaSource.remove(bufferKey);

            // Fix 7 (post-Fix-1 audit): conditionally clear the
            // streaming buffer. If a `chat.delta` event arrived in
            // the SAME microtask as this `lifecycle.start` (server
            // misorder), the buffer was populated by that delta.
            // Clearing it unconditionally would drop the first chunk
            // of the new turn on the floor. Only clear if the buffer
            // is empty — a non-empty buffer is either in-flight data
            // for the new turn or stale data from a prior turn that
            // never sent an end event (rare; the next chat.final or
            // lifecycle.end will consume it).
            final existing = _streamingBuffers[bufferKey];
            if (existing == null || existing.text.isEmpty) {
              _streamingBuffers.remove(bufferKey);
            }
          } else if (phase == 'end') {
            // Coordinate with chat.final — only one handler per session
            // may finalize, preventing duplicate messages when a v3
            // Gateway sends both chat.final and agent.lifecycle.end.
            //
            // IMPORTANT: _finalizedSessions.add() must come AFTER the
            // buffer emptiness guard, not before.  If lifecycle.end
            // arrives without prior deltas (empty buffer), marking the
            // session as finalized here would cause chat.final — which
            // carries the complete msgJson — to see the key already
            // present and silently discard the full agent reply.
            final agentId = _resolveAgentId(event.sessionKey);
            // Build final message from accumulated buffer.
            // Guard against empty buffer — matches _onChatEvent fallback
            // to prevent empty agent bubbles when no deltas were
            // accumulated or chat.final already consumed the buffer.
            final buffer = _streamingBuffers.remove(bufferKey);
            if (buffer == null || buffer.text.isEmpty) break;
            if (!_finalizedSessions.add(bufferKey)) break;

            // Turn complete — clear the delta-source lock + active runId
            // (mirrors chat.final).
            _deltaSource.remove(bufferKey);
            _activeRunIdBySession.remove(bufferKey);

            if (!conn.messageCtrl.isClosed) {
              conn.messageCtrl.add(
                _mapper
                    .buildAgentFallbackMessage(agentId ?? '', buffer.text)
                    .copyWith(
                      metadata: <String, dynamic>{
                        'sessionKey': event.sessionKey,
                      },
                    ),
              );
            }
            // Notify UI that streaming is complete — only when we have
            // a resolvable agentId; otherwise ChatViewModel silently
            // drops StreamingDone('') and a pending _flushTimer
            // republishes the stale buffer as a ghost bubble.
            if (agentId != null && !conn.streamingCtrl.isClosed) {
              conn.streamingCtrl.add(StreamingDone(agentId: agentId));
            }
          }
        }

      case AgentStreamType.item:
        break;
      case AgentStreamType.unknown:
        _logger.error(
          '[WsGateway] Unknown agent stream type for $instanceId: '
          '${event.data['stream']}',
        );
        break;
    }
  }

  /// Resolve a [sessionKey] to its remote agent ID, logging on failure.
  ///
  /// Delegates to the pure protocol-level [resolveAgentId] function, then
  /// logs via [_logger] when resolution fails — keeping the protocol
  /// function free of Flutter/side-effect dependencies.
  String? _resolveAgentId(String sessionKey) {
    final result = resolveAgentId(sessionKey, _sessionToAgentId);
    if (result == null) {
      // Only log the first time a sessionKey fails resolution; repeated deltas
      // for the same unresolvable session should not spam the logs.
      if (_unresolvableSessionKeys.add(sessionKey)) {
        _logger.error(
          '[WsGateway] Cannot resolve agentId from sessionKey: '
          '"$sessionKey" — mapping contains ${_sessionToAgentId.length} entries',
        );
      }
    }
    return result;
  }
}
