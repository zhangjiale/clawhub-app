import 'dart:async';
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

      // Hoist logger once — both the VM constructor and the two listener
      // closures route errors here. Use [ref.read] (not watch) for a stable
      // instance over the VM lifetime; a single local avoids reading the
      // provider twice and makes the shared dependency obvious.
      final logger = ref.read(loggerProvider);

      final vm = AgentProfileViewModel(
        agentRepo: ref.watch(agentRepoProvider),
        instanceRepo: ref.watch(instanceRepoProvider),
        messageRepo: ref.watch(messageRepoProvider),
        activityRepo: ref.watch(activityRepoProvider),
        evaluateAchievements: ref.watch(evaluateAchievementsUseCaseProvider),
        avatarStorageService: ref.watch(avatarStorageServiceProvider),
        logger: logger,
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

      // US-021 v1.1: 订阅 sync ticker，让本 provider 在 agents 同步完成后
      // （含 tombstone / 复活）自动重建。与 chat_providers.dart:72-74 同模式。
      //
      // BUG B 修复:ticker 携带被同步的 instanceId + revision。
      // listener 按 `next.instanceId == vm.instanceId` 过滤,跨实例 sync 不触发本 VM
      // 的 refreshAgent,避免 N 个 active profile × 任意 sync = N 次冗余
      // getById。vm.instanceId 来自 _agent.instanceId (init 后才有效);
      // init 未完成时 (null) 跳过 — 下次 sync tick 会再 fire。
      ref.listen<AgentSyncTick?>(agentSyncTickerProvider, (prev, next) {
        if (next == null) return;
        final myInstance = vm.instanceId;
        if (myInstance == null || next.instanceId != myInstance) return;
        unawaited(
          vm.refreshAgent().catchError((Object e, StackTrace st) {
            logger.error(
              '[agentProfileProvider] ticker-driven refreshAgent failed '
              'for agent $agentId: $e',
              st,
            );
            return Future<void>.value();
          }),
        );
      });

      // Refresh profile snapshot whenever AchievementChecker recomputes
      // stats (typically right after a chat message). Filter to this
      // agent's id only — other agents' events must not trigger our
      // refresh (would be wasted computeStats + could clobber mid-edit
      // isSaving state).
      final updatesSub = ref.read(achievementCheckerProvider).updates.listen((
        updatedAgentId,
      ) {
        if (updatedAgentId != agentId) return;
        // Race 修复:用 achievementRefresh() 替代 refresh() 避免与
        // saveProfile 内部的 await refresh() 互相覆盖 detailLoadState。
        unawaited(
          vm.achievementRefresh().catchError((Object e, StackTrace st) {
            logger.error(
              '[agentProfileProvider] achievementRefresh listener '
              'failed for agent $agentId: $e',
              st,
            );
            return Future<void>.value();
          }),
        );
      });
      ref.onDispose(() {
        updatesSub.cancel();
        vm.dispose();
      });
      return vm;
    });
