import 'dart:async';

import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show StreamingDelta, StreamingDone, StreamingEvent;
import 'package:claw_hub/core/i_logger.dart';

/// 流式文本累积器 + 节流器(PR-B,spec 2026-07-04)。
///
/// 抽自 ChatViewModel 的 _streamingSubscription / _streamBuffer /
/// _lastPublishedLength / _flushTimer / _stallTimer / _isStreaming +
/// _startStreaming / _scheduleFlush / _flushToState / _flushImmediately。
/// 纯 Dart,不依赖 StateNotifier/Riverpod —— VM 经回调注入 state 写入
/// ([onStreamingTextChanged])与 thinking 超时联动([onDeltaActivity] /
/// [onStreamError] 重新 arm / 取消 VM 持有的 60s _timeoutTimer)。
///
/// 单一职责:**流式 delta 累积 + 节流 flush + stall 检测**。thinking 状态机
/// (120s 硬顶 _overallTimeoutTimer)与 60s 活动 _timeoutTimer 的 arm 时机
/// 由 VM 驱动([ChatViewModel._startThinking] / [_sendCore]),SL 仅经
/// [onDeltaActivity] 通知"有活动",由 VM 重 arm —— 保持 thinking 状态机
/// 内聚在 VM(Option A,经 architecture-reviewer Q1 审查认可)。
class StreamingLifecycle {
  StreamingLifecycle({
    required this.flushDelay,
    required this.onStreamingTextChanged,
    required this.onDeltaActivity,
    required this.onStreamError,
    required this.logger,
    this.stallDelay = const Duration(seconds: 30),
  });

  /// 节流窗口(delta 在此窗口内的多次 flush 合并为一次)。
  /// 生产默认 150ms(对齐 StreamingBubble 的 MarkdownBody debounce),
  /// 测试注入 Duration.zero 同步断言。VM 经 [ChatViewModel.flushDelay] 透传。
  final Duration flushDelay;

  /// stall 检测窗口(无 delta 持续此时长 → 推空,隐藏卡住的半句)。
  /// 生产默认 30s;测试注入小值免 FakeAsync。
  final Duration stallDelay;

  /// 推 state.streamingText(累积文本或 '' 清空)。
  final void Function(String text) onStreamingTextChanged;

  /// delta 到达通知 —— VM 据此重新 arm 60s _timeoutTimer。
  /// 在 50KB buffer cap 之外,每次 delta 都触发(即使 buffer 已满)。
  final void Function() onDeltaActivity;

  /// 流错误通知 —— VM 据此取消 60s _timeoutTimer(避免错误后误触 timeout)。
  final void Function() onStreamError;

  final ILogger logger;

  StreamSubscription<StreamingEvent>? _subscription;
  String _agentRemoteId = '';
  final StringBuffer _buffer = StringBuffer();
  int _lastPublishedLength = 0;
  Timer? _flushTimer;
  Timer? _stallTimer;
  bool _isStreaming = false;

  bool get isStreaming => _isStreaming;

  /// 订阅流(取消旧订阅,防 stale event)。对应原 _startStreaming 的 listen 体。
  ///
  /// 接收 `Stream` 而非 `IGatewayClient`(spec 细化):SL 只需流,不需要整个
  /// fat ACL 接口(接口隔离);VM 调用方 `_gatewayClient.streamingDeltaStream(id)`
  /// 取流后传入。测试直接传 controller.stream。
  void start(Stream<StreamingEvent> stream, String agentRemoteId) {
    _subscription?.cancel();
    _agentRemoteId = agentRemoteId;
    _subscription = stream.listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) {
        _isStreaming = false;
        _flushImmediately();
        _stallTimer?.cancel();
        _stallTimer = null;
        onStreamError();
        onStreamingTextChanged('');
        logger.error('Streaming stream error: $error', stackTrace);
      },
    );
  }

  void _onEvent(StreamingEvent event) {
    if (event is StreamingDelta && event.agentId == _agentRemoteId) {
      _isStreaming = true;
      // 50KB cap:防止超长回复撑爆内存/Markdown 渲染。cap 只挡 buffer.write
      // 与 scheduleFlush;isStreaming 翻转与 onDeltaActivity 在 if 之外,
      // 始终触发(对齐原 _startStreaming 962/967)。
      if (_buffer.length < 50 * 1024) {
        _buffer.write(event.text);
        _scheduleFlush();
      }
      onDeltaActivity();
      _stallTimer?.cancel();
      _stallTimer = Timer(stallDelay, () => onStreamingTextChanged(''));
    } else if (event is StreamingDone && event.agentId == _agentRemoteId) {
      _isStreaming = false;
      _flushImmediately();
      _stallTimer?.cancel();
      _stallTimer = null;
      onStreamingTextChanged('');
    }
  }

  /// send 开头的重置(原 _sendCore 833-843):取消 sub+flush+stall,清 buffer,
  /// 归零 _lastPublishedLength,isStreaming=false,推 ''。
  /// 不动 VM 的 _timeoutTimer/_overallTimeoutTimer(VM 自己 cancel)。
  void resetForSend() {
    _subscription?.cancel();
    _subscription = null;
    _isStreaming = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _buffer.clear();
    _lastPublishedLength = 0;
    _stallTimer?.cancel();
    _stallTimer = null;
    onStreamingTextChanged('');
  }

  /// 连接掉线重置(原 508-520):清 buffer、归零 _lastPublishedLength、取消 stall,
  /// isStreaming=false,推 ''。**不**取消 sub、**不**取消 flushTimer(严格对齐
  /// 原状——pending flush 因 buffer 已清+_lastPublishedLength 归零而变 no-op)。
  void onConnectionLost() {
    _isStreaming = false;
    _buffer.clear();
    _lastPublishedLength = 0;
    _stallTimer?.cancel();
    _stallTimer = null;
    onStreamingTextChanged('');
  }

  /// agent 最终 Message 到达(原 617-624):isStreaming=false,推 ''。
  /// **不**清 buffer、**不**归零 _lastPublishedLength(对齐原状——stall-后-delta
  /// 回填是既有契约,见 spec 风险点 3)。禁止顺手优化成清 buffer。
  ///
  /// 但必须取消已挂起的 _flushTimer(review #9):否则一条 delta 落定后挂起的
  /// 150ms 节流 flush 会在最终 Message 落地后触发,把陈旧 buffer 文本作为
  /// 幽灵流式文本重新发布一帧。取消 timer 不影响 stall-后-delta 回填——下一条
  /// delta 会自行 _scheduleFlush 新 timer。
  void onReplyArrived() {
    _isStreaming = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    onStreamingTextChanged('');
  }

  /// retry/teardown 用(原 1351-1365 + retry 1320-1322):取消 sub+flush+stall,
  /// 清 buffer、归零 _lastPublishedLength,isStreaming=false。**不**推 state。
  /// (原 teardown 不清 buffer,但 buffer 随后 GC / retry 本就手动清——合并到
  /// 此处后 retry 三行可删,两调用点行为等价,见 spec 风险点 8。)
  void cancel() {
    _subscription?.cancel();
    _subscription = null;
    _isStreaming = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;
    _buffer.clear();
    _lastPublishedLength = 0;
  }

  /// 完整释放。等同 [cancel],幂等。
  void dispose() => cancel();

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, _flushToState);
  }

  /// 推累积文本到 state。无新内容(length 未变)时跳过,避免无谓 rebuild。
  void _flushToState() {
    final full = _buffer.toString();
    if (full.length == _lastPublishedLength) return;
    onStreamingTextChanged(full);
    _lastPublishedLength = full.length;
  }

  void _flushImmediately() {
    _flushTimer?.cancel();
    _flushToState();
  }
}
