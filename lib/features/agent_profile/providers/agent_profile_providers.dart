import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

/// Agent 资料页 ViewModel Provider
///
/// AgentProfilePage 和 AgentConfigPage 通过同一个 agentId 参数共享
/// 同一个 ViewModel 实例。Config 页调用 vm.saveProfile(...) 后，
/// Profile 页自动重建（因为 watch 同一个 state 对象）。
final agentProfileViewModelProvider = StateNotifierProvider.family<
    AgentProfileViewModel, AgentProfileState, String>(
  (ref, agentId) {
    final vm = AgentProfileViewModel(
      agentRepo: ref.watch(agentRepoProvider),
      instanceRepo: ref.watch(instanceRepoProvider),
      messageRepo: ref.watch(messageRepoProvider),
      agentId: agentId,
    );
    vm.init();
    ref.onDispose(() => vm.dispose());
    return vm;
  },
);
