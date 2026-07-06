import 'dart:async';

import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';

/// 消息中心预览同步器 —— 把同事件循环内多条入站消息合并为一次预览写。
///
/// 抽自 `ChatViewModel._scheduleConversationPreviewUpdate` + `_pendingPreviewMessage`
/// + `_previewCoalesceTimer`(PR-A,spec 2026-07-04)。纯 Dart,不依赖
/// StateNotifier/Riverpod —— VM 经 `onFlush` 回调注入真正的预览写逻辑
/// (`_updateConversationPreview`:时间戳 guard + generatePreview + updateLastMessage)。
///
/// 单一职责:**留 timestamp 最大那条 + 同事件循环合并**。其他业务
/// (toolCall 跳过、FK 兜底、预览文本生成)由 VM 的 `onFlush` 体承担。
///
/// 合并语义:每次 [schedule] 取消上一个 `Timer(Duration.zero)`,故同一
/// 事件循环内多次 schedule 只在队列排空时触发一次 flush —— 与原 VM 行为
/// 1:1 等价(`streaming_guard_test` 的 "rapid incoming messages coalesce"
/// case 锁住该契约:3 条入站 → 1 次 `updateLastMessage`)。
class PreviewUpdater {
  PreviewUpdater({required this.onFlush, required this.isMounted});

  /// 真正的预览写逻辑 —— 由 VM 提供([ChatViewModel._updateConversationPreview])。
  /// 仅在 flush 触发且 [isMounted] 为 true 时调用,带最新 timestamp 的那条消息。
  final Future<void> Function(Message) onFlush;

  /// VM 的 mounted 状态 —— flush 触发时若 VM 已 dispose,跳过 onFlush。
  /// (VM 的 `_updateState` 虽有 mounted 守卫,但 `onFlush` 内还含
  /// `_conversationRepo.getById`/`updateLastMessage` 等 DB 调用,提前
  /// short-circuit 避免无谓 IO。)
  final bool Function() isMounted;

  /// 当前 pending 的预览消息(timestamp 最大者)。
  Message? _pending;

  /// 合并用 zero-delay timer。每次 schedule 重置,故同事件循环只触发一次。
  Timer? _timer;

  /// 调度一次预览更新。
  ///
  /// - `toolCall` 消息直接 return(护栏 1:toolCall 走专用 UI,其预览是字面量
  ///   `[工具调用]`,覆盖会话预览会让消息中心显示无意义内容)。
  /// - timestamp 不小于 pending 时覆盖;否则保留 pending(护栏 2:乱序/重发
  ///   旧消息不得回卷预览)。
  /// - 重置 timer,在事件队列排空时统一 flush。
  void schedule(Message message) {
    if (message.type == MessageType.toolCall) return;
    // 这些角色不用于会话侧边栏预览:toolResult 是工具输出、userPlaceholder
    // 是上传占位、system 是系统通知,写入预览会覆盖真正的最后聊天消息。
    if (message.role == MessageRole.toolResult ||
        message.role == MessageRole.userPlaceholder ||
        message.role == MessageRole.system)
      return;

    if (_pending == null || message.timestamp >= _pending!.timestamp) {
      _pending = message;
    }

    _timer?.cancel();
    _timer = Timer(Duration.zero, () {
      final pending = _pending;
      _pending = null;
      if (pending == null || !isMounted()) return;
      // onFlush 返回 Future<void> 但属 fire-and-forget(原 VM 用 unawaited 标记);
      // 显式 unawaited 避免 discarded_futures lint。
      unawaited(onFlush(pending));
    });
  }

  /// 取消未触发的 flush 并清空 pending。供 VM `_teardownSubscriptions` 调用。
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
