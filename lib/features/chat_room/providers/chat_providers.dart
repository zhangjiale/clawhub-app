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
final chatViewModelProvider = StateNotifierProvider.family<ChatViewModel, ChatSessionState, ({
  String instanceId,
  String agentId,
})>(
  (ref, params) {
    final vm = ChatViewModel(
      agentRepo: ref.watch(agentRepoProvider),
      conversationRepo: ref.watch(conversationRepoProvider),
      messageRepo: ref.watch(messageRepoProvider),
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
    return vm;
  },
);
