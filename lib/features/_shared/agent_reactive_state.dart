// Finding #8 (2026-06-27 重构): 把 ChatViewModel / AgentProfileViewModel
// 重复的 `_agent` 字段 + `agent` getter + `_setAgent` + `debugSetAgent`
// 抽到共享 mixin。
//
// 设计：mixin 不持有 state、不依赖 StateNotifier / Riverpod，VM 通过实现
// `onAgentUpdated` 钩子告诉 mixin 如何把 agent 变更 propagate 到自己的
// state（典型实现：`_updateState((s) => s.copyWith(contentRevision: s.contentRevision + 1))`）。
//
// 这比 spec 初版「callback 读写 state」更轻：mixin 不与具体 State 类型耦合，
// 未来 VM 想加额外副作用（如同时清空 detailLoadState）只需在
// `onAgentUpdated` 里加代码，不影响 mixin 接口。

import 'package:flutter/foundation.dart';
import 'package:claw_hub/domain/models/agent.dart';

/// 共享 `_agent` 缓存 + contentEquals guard + revision bump 钩子。
///
/// VM 用法（典型）：
/// ```dart
/// class ChatViewModel extends StateNotifier<ChatSessionState>
///     with AgentReactiveState {
///   @override
///   void onAgentUpdated() {
///     _updateState((s) => s.copyWith(contentRevision: s.contentRevision + 1));
///   }
///   // agent getter + setAgent + debugSetAgent 自动从 mixin 暴露
/// }
/// ```
///
/// 调用方把原本的 `_setAgent(...)` 改成 `setAgent(...)`（mixin 暴露的
/// public 接口，跨文件可见）。`debugSetAgent` 保留为 `@visibleForTesting`
/// 钩子，专供 widget 测试绕过 init/refresh 链路。
mixin AgentReactiveState {
  Agent? _agent;

  /// 当前 agent 缓存（null 直到 [setAgent] 首次写入）。
  Agent? get agent => _agent;

  /// 写入新 agent 后的副作用钩子 —— VM 在这里 bump 自己的 contentRevision
  /// 计数器驱动 Riverpod rebuild。mixin 不持有 state，VM 必须提供实现。
  ///
  /// contentEquals 守卫已过滤掉同内容重复 emit，所以 `onAgentUpdated` 只在
  /// 真实内容变更 / null 转换时被调用 —— VM 不必再额外去重。
  void onAgentUpdated();

  /// 写入 [_agent] —— 内部 [Agent.contentEquals] 守卫过滤掉 Drift
  /// `.watchSingleOrNull()` 的 seed event（与已有 [_agent] 内容完全相同），
  /// 避免上游内容 revision 在 init 同步阶段被无意义 bump。null 转换
  /// （tombstone / 复活 / 首次加载）总是 propagate —— 它们的语义就是
  /// identity 变化而非内容噪声。
  void setAgent(Agent? agent) {
    if (_agent != null && agent != null && _agent!.contentEquals(agent)) {
      return;
    }
    _agent = agent;
    onAgentUpdated();
  }

  /// 测试专用 hook：直接写入 [_agent] + 触发 [onAgentUpdated]，不经过完整
  /// init/refresh 链路。Widget 测试用它绕过 stream 订阅构造特定 tombstone
  /// 状态（详见 `chat_view_model_refresh_agent_test.dart` 模板）。
  ///
  /// 生产代码请走 `init()` / `refreshAgent()` —— 它们会自动建立订阅 + 重查。
  @visibleForTesting
  void debugSetAgent(Agent? agent) => setAgent(agent);
}
