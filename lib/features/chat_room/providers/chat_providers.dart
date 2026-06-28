import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/features/settings/providers/clear_cache_guard.dart';

/// ChatViewModel provider — owns the full lifecycle of a chat session.
///
/// Created on first read for a given (instanceId, agentId) pair,
/// initialised immediately, and disposed when the provider is no longer watched.
///
/// Uses [StateNotifierProvider.family] so the UI can observe
/// [ChatSessionState] via [ref.watch] — no manual listener bridge.
final chatViewModelProvider =
    StateNotifierProvider.family<
      ChatViewModel,
      ChatSessionState,
      ({String instanceId, String agentId})
    >((ref, params) {
      // Major #1 修复: 缓存清理期间禁止打开新 VM，避免竞态窗口。
      // 由 chat_room_page 用 try/catch 捕获 [ClearedDuringClearError]
      // → SnackBar + pop。
      if (ref.read(clearCacheInProgressProvider)) {
        throw const ClearedDuringClearError();
      }

      final vm = ChatViewModel(
        agentRepo: ref.watch(agentRepoProvider),
        conversationRepo: ref.watch(conversationRepoProvider),
        messageRepo: ref.watch(messageRepoProvider),
        instanceRepo: ref.watch(instanceRepoProvider),
        gatewayClient: ref.watch(gatewayClientProvider),
        sendMessageUseCase: ref.watch(sendMessageUseCaseProvider),
        achievementChecker: ref.watch(achievementCheckerProvider),
        instanceId: params.instanceId,
        agentId: params.agentId,
      );
      // Invalidate stats provider whenever a message is sent or received,
      // so the stats bar in the agent list tab reflects updated message counts.
      vm.onStatsChanged = () => ref.invalidate(statsProvider);
      vm.init();
      ref.onDispose(() => vm.dispose());

      // Listen (not watch) outboxFlushTickerProvider — when OutboxProcessor
      // flushes the queue in the background, call reloadMessages() on the
      // existing ViewModel instead of disposing and recreating it.  Watching
      // would rebuild the entire StateNotifierProvider.family, tearing down
      // all stream subscriptions (message, connection, streaming) and losing
      // in-progress streaming text.
      //
      // outbox 计数已由 ChatViewModel 内部的 watchOutboxCount 订阅自动驱动，
      // 此处仅触发消息列表重载（反映冲刷后的最终 SENT 状态）。
      // 按 instanceId 隔离，仅本实例冲刷时触发，避免跨实例广播风暴。
      ref.listen(outboxFlushTickerProvider(params.instanceId), (_, _) {
        vm.reloadMessages();
      });

      // Push 模型:listen 清理完成 tick。clearAll 成功后 tick++ → 温和刷新
      //（reloadMessages），**不**销毁重建 VM——chatVM 持有 WebSocket 流/
      // 定时器/listener，销毁会中断进行中的流式传输。reloadMessages 内部的
      // isStreaming 守卫保证流式期间跳过，流式结束后自然刷新。
      // 当前 tick 恒为 0（clearCacheActionProvider 尚未递增），此处为空操作。
      ref.listen(cacheClearedTickProvider, (_, _) {
        vm.reloadMessages();
      });

      // US-021 AC8 响应式：agents 同步完成后（含 tombstone/复活）重查 agent。
      // 用户停在 ChatRoom 期间，后台 syncFromGateway 可能 tombstone 当前
      // agent —— 不 listen 则占位页无法响应式出现（_agent 是非响应式缓存）。
      // refreshAgent 走 _setAgent 路径更新 _agent + bump contentRevision，
      // UI 经 ref.watch(chatViewModelProvider) 自然重建后读
      // vm.agent.isRemoved 触发占位页。与 agentListProvider /
      // conversationListProvider 同模式（均 watch 此 ticker）。
      //
      // BUG B 修复:ticker 携带被同步的 instanceId + revision。
      // listener 按 `next.instanceId == params.instanceId` 过滤,跨实例 sync 不触发本 VM
      // 的 refreshAgent,避免 N 个 ChatRoom × 任意 sync = N 次冗余 getById。
      // 命中本实例时同时置 _tombstoneSuspect = true,让 send() 在下次发消息
      // 时能识别"缓存可能已 stale"并重查（BUG C 修复）。
      ref.listen<AgentSyncTick?>(agentSyncTickerProvider, (prev, next) {
        if (next == null || next.instanceId != params.instanceId) return;
        // ChatViewModel.refreshAgent() 内部已捕获并记录异常；provider 层用
        // unawaited + catchError 兜底，确保 fire-and-forget 监听器不会泄漏
        // 未处理异步错误。
        unawaited(
          vm.markTombstoneSuspectAndRefresh().catchError((
            Object e,
            StackTrace st,
          ) {
            return Future<void>.value();
          }),
        );
      });

      return vm;
    });
