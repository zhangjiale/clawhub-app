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

      // Round 4 P1 cleanup: hoist logger reference once at family body top.
      // Two listeners below (ticker + AchievementChecker.updates) both
      // catch errors and route to ILogger — reading loggerProvider twice
      // per family closure was redundant. Note: ref.read is correct here
      // (not ref.watch) because we want a stable logger instance for the
      // lifetime of this VM, not a rebuild trigger.
      final logger = ref.read(loggerProvider);

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
        // AgentProfileViewModel.refreshAgent() 内部已捕获并记录异常;这里
        // 是 provider 层兜底,确保 fire-and-forget listener 不会泄漏未
        // 处理异步错误。Iron Law 8:catchError 必须把错误交给 ILogger,
        // 不能 `() => Future<void>.value()` 静默吞掉——那样 agent 同步
        // 链路上的失败在生产中完全看不见。
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

      // Bug-fix (round 3): subscribe to AchievementChecker.updates so the
      // profile VM refreshes its snapshot whenever stats are just
      // recomputed (typically right after a chat message). Without this,
      // the page keeps showing whatever stats were loaded at init() time —
      // new messages arrive, stats aggregate changes, but the user-facing
      // profile still displays the old snapshot because VM state is
      // cached in memory and not reactive to DB writes.
      //
      // Filter to this agent's id only — other agents' AchievementChecker
      // events must not trigger our refresh (would be a wasted computeStats
      // round-trip and could clobber the user's mid-edit isSaving state).
      // No-cycle guarantee: vm.refresh() → execute(id) → computeStats,
      // which does NOT call AchievementChecker.check() (the
      // checker only fires from chat message events). So the stream is
      // never self-fed.
      final updatesSub = ref.read(achievementCheckerProvider).updates.listen((
        updatedAgentId,
      ) {
        if (updatedAgentId != agentId) return;
        // Race 修复：用 achievementRefresh() 替代 refresh()。
        // vm.refresh() 会把 detailLoadState 重置为 LoadInProgress,
        // 与 saveProfile 内部的 await refresh() 并发时会互相覆盖,
        // 导致 Profile 页闪一下空白、Config 页的 saveError/saveSuccess
        // 状态机被异步打断。achievementRefresh() 只刷 stats /
        // achievements / newUnlocks 三个字段,不触碰 detailLoadState
        // 和 save 流程的 isSaving/saveError/saveSuccess。
        unawaited(
          vm.achievementRefresh().catchError((Object e, StackTrace st) {
            // Iron Law 8: Stream listener 不能静默吞错。
            // achievementRefresh 内部的 _safeEvaluateAchievements 失败
            // 已被 _logger.error 记录,这里捕获的是 listener 本身抛出
            // 的非预期错误(例如 vm 已 dispose 后 state 写入)。通过
            // 同一 logger 集中输出,排查时一处即可看到全链路。
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
