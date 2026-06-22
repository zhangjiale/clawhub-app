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
      ref.listen(outboxFlushTickerProvider(params.instanceId), (_, __) {
        vm.reloadMessages();
      });

      // Push 模型:listen 清理完成 tick。clearAll 成功后 tick++ → 温和刷新
      //（reloadMessages），**不**销毁重建 VM——chatVM 持有 WebSocket 流/
      // 定时器/listener，销毁会中断进行中的流式传输。reloadMessages 内部的
      // isStreaming 守卫保证流式期间跳过，流式结束后自然刷新。
      // 当前 tick 恒为 0（clearCacheActionProvider 尚未递增），此处为空操作。
      ref.listen(cacheClearedTickProvider, (_, __) {
        vm.reloadMessages();
      });

      return vm;
    });
