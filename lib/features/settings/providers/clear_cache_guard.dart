import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:claw_hub/app/router/smart_back.dart';

/// "清除全部缓存" 进行中互斥 guard — 防止 clearAll 期间打开新 VM 引发竞态。
///
/// 在 [clearCacheActionProvider]（定义于 `settings_providers.dart`）
/// 执行期间为 `true`。被影响的 family builder（agent_profile、chat_room）
/// 顶部检查此值，若 true 则抛出 [ClearedDuringClearError]，由对应页面
/// 用 try/catch 包裹 ref.watch 后调用 [handleClearedDuringClear] 调度
/// SnackBar + pop。
///
/// clearAll 完成后通过 [cacheClearedTickProvider]（push 模型）驱动已存活
/// 的 family VM 自动响应——无需枚举 live-set。本 guard 仅负责清理窗口期
/// 内拦截新建,保证用户看到「清理中」提示而非半提交数据。
///
/// 单独成文件避免 settings_providers ↔ agent_profile_providers ↔ chat_providers
/// 之间的循环导入。
final clearCacheInProgressProvider = StateProvider<bool>((_) => false);

/// 缓存清理完成信号 — 单调递增计数器（push 模型）。
///
/// `clearCacheActionProvider` 在 `clearAll` 成功后递增本值。各 family VM
/// 通过 `ref.watch`（agentProfileVM，可安全销毁重建）或 `ref.listen`
///（chatVM，温和刷新不销毁）订阅本值，从而**自动响应**缓存清理，无需
/// `clearCacheActionProvider` 反向 import 各 feature 枚举失效。
///
/// 用计数器而非 bool：bool 翻转无法区分"连续两次清理"，计数器每次 `++`
/// 都会触发订阅者更新。
final cacheClearedTickProvider = StateProvider<int>((_) => 0);

/// 在缓存清理进行中尝试打开被影响页面时抛出的错误类型。
///
/// agent_profile_page / chat_room_page 用 `try/catch` 包裹 ref.watch，
/// 捕获此特定类型后调用 [handleClearedDuringClear] 显示 SnackBar 并 pop。
/// 不使用通用 Exception 是为了精确区分"用户主动 clearAll"（guard 拦截）
/// vs "DB 异常"（真实失败）。
class ClearedDuringClearError implements Exception {
  const ClearedDuringClearError();

  @override
  String toString() => '缓存清理进行中，无法打开页面';
}

/// Schedule a post-frame SnackBar + smart back navigation for the
/// "cleared during clear" guard flow.
///
/// Called from the `on ClearedDuringClearError` catch in pages whose
/// family VM rejects access while [clearCacheActionProvider] is running.
/// Centralizing this avoids copy-pasting the same 8-line post-frame
/// callback across every guarded page.
void handleClearedDuringClear(BuildContext context, {String? source}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('缓存清理中，无法打开页面')));
    smartBack(context, source: source);
  });
}
