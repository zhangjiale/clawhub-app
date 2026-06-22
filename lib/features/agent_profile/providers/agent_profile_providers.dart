import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/features/settings/providers/clear_cache_guard.dart';

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
      // Major #1 修复: 缓存清理期间禁止打开新 VM，避免竞态窗口。
      // 由 agent_profile_page 用 try/catch 捕获 [ClearedDuringClearError]
      // → SnackBar + pop。
      if (ref.read(clearCacheInProgressProvider)) {
        throw const ClearedDuringClearError();
      }

      // Push 模型:watch 清理完成 tick。clearAll 成功后 tick++ → 本 family
      // 自动销毁重建（agentProfileVM 无流/连接等长生命周期副作用，重建安全）。
      ref.watch(cacheClearedTickProvider);

      final vm = AgentProfileViewModel(
        agentRepo: ref.watch(agentRepoProvider),
        instanceRepo: ref.watch(instanceRepoProvider),
        messageRepo: ref.watch(messageRepoProvider),
        activityRepo: ref.watch(activityRepoProvider),
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
