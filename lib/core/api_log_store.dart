import 'dart:async';
import 'dart:collection';

import 'package:claw_hub/core/api_log_redactor.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:uuid/uuid.dart';

// ignore_for_file: prefer_initializing_formals — the `logger` ctor param uses
// direct field assignment (`_logger = logger`) so it stays a public named param
// (DI-able from providers.dart). The initializing formal `this._logger` would be
// library-private (Dart `_`-prefix) and uncallable from other files. (Line-level
// ignore is unstable: dart format reflows the assignment across lines.)

/// 环形缓冲实现 [IApiLogger]（spec §4）。纯 Dart，不碰 Flutter/Riverpod。
///
/// 同一实例既被 [ConnectionManager] 当 logger 用、又被 UI provider 当数据源读
/// （SSOT，spec §2.3 决策 2）。永不抛（spec §4.2 不变量）。
class ApiLogStore implements IApiLogger {
  ApiLogStore({
    this.maxEntries = defaultMaxEntries,
    ILogger? logger,
    int Function()? clock,
  }) : _logger = logger,
       _clock = clock ?? _defaultClock;

  static int _defaultClock() => DateTime.now().millisecondsSinceEpoch;

  static const int defaultMaxEntries = 500;
  static const int pendingReqSweepThreshold = 200;
  static const int pendingReqTtlMs = 30000;

  final int maxEntries;
  final ILogger? _logger;
  final int Function() _clock;
  final Uuid _uuid = const Uuid();

  final ListQueue<ApiLogEntry> _entries = ListQueue<ApiLogEntry>();
  final Map<String, int> _pendingReqTs = {}; // requestId → sentAt ms
  final StreamController<ApiLogEntry> _ctrl =
      StreamController<ApiLogEntry>.broadcast();

  List<ApiLogEntry> snapshot() => List.unmodifiable(_entries.toList());
  Stream<ApiLogEntry> get onEntry => _ctrl.stream;

  void clear() {
    _entries.clear();
    _pendingReqTs.clear();
  }

  void dispose() => _ctrl.close();

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) {
    try {
      final now = _clock();
      _pendingReqTs[requestId] = now;
      _maybeSweep(now);
      _add(
        ApiLogEntry(
          id: _uuid.v4(),
          timestampMs: now,
          instanceId: instanceId,
          direction: ApiLogDirection.outgoing,
          kind: ApiLogKind.req,
          methodOrEvent: method,
          requestId: requestId,
          byteSize: byteSize,
          payloadPreview: redactAndTruncate(rawJson, payloadSize: byteSize),
        ),
      );
    } catch (e, st) {
      _logger?.error('[ApiLogStore] logRequest failed: $e', st);
    }
  }

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {
    try {
      final now = _clock();
      final sentAt = _pendingReqTs.remove(requestId);
      final durationMs = sentAt == null ? null : now - sentAt;
      _maybeSweep(now);
      _add(
        ApiLogEntry(
          id: _uuid.v4(),
          timestampMs: now,
          instanceId: instanceId,
          direction: ApiLogDirection.incoming,
          kind: ApiLogKind.res,
          requestId: requestId,
          ok: ok,
          errorCode: errorCode,
          byteSize: byteSize,
          durationMs: durationMs,
          payloadPreview: rawJson == null
              ? null
              : redactAndTruncate(rawJson, payloadSize: byteSize),
        ),
      );
    } catch (e, st) {
      _logger?.error('[ApiLogStore] logResponse failed: $e', st);
    }
  }

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  }) {
    try {
      _add(
        ApiLogEntry(
          id: _uuid.v4(),
          timestampMs: _clock(),
          instanceId: instanceId,
          kind: ApiLogKind.state,
          state: state,
          message: message,
        ),
      );
    } catch (e, st) {
      _logger?.error('[ApiLogStore] logStateChange failed: $e', st);
    }
  }

  void _add(ApiLogEntry entry) {
    _entries.addLast(entry);
    if (_entries.length > maxEntries) {
      _entries
          .removeFirst(); // O(1) FIFO (was removeAt(0) O(n) on the WS hot path)
    }
    if (!_ctrl.isClosed) _ctrl.add(entry);
  }

  /// 惰性清理超时未匹配 res 的 pending req（spec §4.2）。清理不静默——发一条
  /// state 诊断条目。直接走 [_add] 避免再入 [logStateChange] 的 try/catch。
  void _maybeSweep(int nowMs) {
    if (_pendingReqTs.length <= pendingReqSweepThreshold) return;
    final before = _pendingReqTs.length;
    _pendingReqTs.removeWhere((id, ts) => nowMs - ts > pendingReqTtlMs);
    final evicted = before - _pendingReqTs.length;
    if (evicted > 0) {
      _add(
        ApiLogEntry(
          id: _uuid.v4(),
          timestampMs: nowMs,
          instanceId: 'system',
          kind: ApiLogKind.state,
          state: null,
          message:
              'evicted $evicted pending req entries older than '
              '${pendingReqTtlMs ~/ 1000}s',
        ),
      );
    }
  }
}
