import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/features/agent_list/providers/stats_providers.dart';

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
      final vm = ChatViewModel(
        agentRepo: ref.watch(agentRepoProvider),
        conversationRepo: ref.watch(conversationRepoProvider),
        messageRepo: ref.watch(messageRepoProvider),
        instanceRepo: ref.watch(instanceRepoProvider),
        gatewayClient: ref.watch(gatewayClientProvider),
        sendMessageUseCase: ref.watch(sendMessageUseCaseProvider),
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

      return vm;
    });
