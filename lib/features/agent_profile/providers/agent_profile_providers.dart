import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

/// Agent 资料页 ViewModel Provider
///
/// AgentProfilePage 和 AgentConfigPage 通过同一个 agentId 参数共享
/// 同一个 ViewModel 实例。Config 页调用 vm.saveProfile(...) 后，
/// Profile 页自动重建（因为 watch 同一个 state 对象）。
final agentProfileViewModelProvider =
    StateNotifierProvider.family<
      AgentProfileViewModel,
      AgentProfileState,
      String
    >((ref, agentId) {
      final vm = AgentProfileViewModel(
        agentRepo: ref.watch(agentRepoProvider),
        instanceRepo: ref.watch(instanceRepoProvider),
        messageRepo: ref.watch(messageRepoProvider),
        evaluateAchievements: ref.watch(evaluateAchievementsUseCaseProvider),
        avatarStorageService: ref.watch(avatarStorageServiceProvider),
        agentId: agentId,
        // The callback deliberately imports dart:io and flutter/widgets here
        // in the provider (DI/wiring) layer — NOT in the ViewModel. This keeps
        // Flutter framework types out of AgentProfileViewModel so it remains
        // testable and framework-agnostic. For 5 lines of best-effort cache
        // eviction this is a pragmatic trade-off vs creating a full
        // IAvatarCacheService abstraction. Revisit if more Flutter imports
        // accumulate in this file.
        onAvatarChanged: (path) {
          // Best-effort cache eviction — non-fatal if unavailable
          try {
            imageCache.evict(FileImage(File(path)));
          } catch (_) {
            /* iron-law-allow: Law8 — best-effort cache eviction */
          }
        },
      );
      vm.init();
      ref.onDispose(() => vm.dispose());
      return vm;
    });
