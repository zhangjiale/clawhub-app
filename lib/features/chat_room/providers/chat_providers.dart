import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';

/// ChatViewModel provider — owns the full lifecycle of a chat session.
///
/// Created on first read for a given (instanceId, agentId) pair,
/// initialised immediately, and disposed when the provider is no longer watched.
final chatViewModelProvider = Provider.family<ChatViewModel, ({
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
    vm.init();
    ref.onDispose(() => vm.dispose());
    return vm;
  },
);
