import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/utils/copy_with_nullable.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/models/daily_activity.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/errors.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import 'package:claw_hub/features/_shared/agent_reactive_state.dart';

/// Result bundle for [AgentProfileViewModel._safeEvaluateAchievements],
/// separated from the public state class so the best-effort helper can
/// return it without crossing the ViewModel boundary.
typedef _AchievementResult = ({
  AgentStats? stats,
  List<Achievement> achievements,
  List<Achievement> freshUnlocks,
});

/// Agent 详情聚合数据（不可变值对象）
class AgentDetailData {
  final Agent agent;
  final Instance? instance;
  final int messageCount;
  final AgentStats? stats;
  final List<Achievement> achievements;

  /// 30 天每日活动序列(US-019 成长面板时间线),按 dayBucket 升序。
  ///
  /// 长度为 30(含无消息空日)。加载失败时为 `const []`,UI 退化为空状态。
  final List<DailyActivity> dailyActivity;

  const AgentDetailData({
    required this.agent,
    this.instance,
    required this.messageCount,
    this.stats,
    this.achievements = const [],
    this.dailyActivity = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDetailData &&
          agent == other.agent &&
          instance == other.instance &&
          messageCount == other.messageCount &&
          stats == other.stats &&
          achievements == other.achievements &&
          dailyActivity == other.dailyActivity;

  @override
  int get hashCode => Object.hash(
    agent,
    instance,
    messageCount,
    stats,
    achievements,
    dailyActivity,
  );
}

/// Agent 资料页的不可变状态快照
///
/// 同时服务 AgentProfilePage（消费 [detailLoadState]）和
/// AgentConfigPage（消费 [isSaving]/[saveError]/[saveSuccess]）。
///
/// 2026-06-26 refactor: US-021 tombstone 检测从 `isAgentRemoved: bool` 字段
/// 迁移到 `vm.agent.isRemoved` 直读 —— 配合 `Agent.contentEquals` 让
/// Riverpod dedup 自然放行内容变更。`contentRevision` 字段保留作为
/// rebuild 触发器（`_setAgent` 调用时 bump），与 ChatSessionState 同模式。
class AgentProfileState {
  final LoadState<AgentDetailData> detailLoadState;
  final bool isSaving;
  final String? saveError;
  final bool saveSuccess;
  final List<Achievement> newUnlocks; // freshly unlocked this session

  /// Monotonic counter bumped whenever [_agent] changes in a content-visible
  /// way (post [Agent.contentEquals] filter). UI reads `vm.agent` directly for
  /// tombstone + content data; this field exists to drive Riverpod's
  /// `ref.watch` rebuild when content changes bypass identity-only
  /// `Agent.==` dedup (tombstone transitions, nickname/themeColor changes,
  /// profile save reflects).
  final int contentRevision;

  const AgentProfileState({
    this.detailLoadState = const LoadInProgress(),
    this.isSaving = false,
    this.saveError,
    this.saveSuccess = false,
    this.newUnlocks = const [],
    this.contentRevision = 0,
  });

  /// copyWith 使用 [CopyWithSentinel] 区分 "未传参" 和 "显式传 null"，
  /// 避免手写 sentinel 单例导致的样板代码。
  AgentProfileState copyWith({
    LoadState<AgentDetailData>? detailLoadState,
    bool? isSaving,
    Object? saveError = CopyWithSentinel.instance,
    bool? saveSuccess,
    List<Achievement>? newUnlocks,
    int? contentRevision,
  }) {
    return AgentProfileState(
      detailLoadState: detailLoadState ?? this.detailLoadState,
      isSaving: isSaving ?? this.isSaving,
      saveError: copyWithNullable(saveError, this.saveError),
      saveSuccess: saveSuccess ?? this.saveSuccess,
      newUnlocks: newUnlocks ?? this.newUnlocks,
      contentRevision: contentRevision ?? this.contentRevision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentProfileState &&
          detailLoadState == other.detailLoadState &&
          isSaving == other.isSaving &&
          saveError == other.saveError &&
          saveSuccess == other.saveSuccess &&
          newUnlocks == other.newUnlocks &&
          contentRevision == other.contentRevision;

  @override
  int get hashCode => Object.hash(
    detailLoadState,
    isSaving,
    saveError,
    saveSuccess,
    newUnlocks,
    contentRevision,
  );
}

/// Agent 资料页的 ViewModel
///
/// 拥有 agent 详情加载、实例查询、消息统计、个性化配置保存的全部编排逻辑。
/// AgentProfilePage 和 AgentConfigPage 共享同一个 ViewModel 实例
///（通过同一个 StateNotifierProvider.family 的 agentId 参数）。
///
/// Agent 数据通过 [AgentProfileState.detailLoadState] 暴露给 UI 层，
/// 不再使用单独的 `agent` getter —— Config 页直接从 state 读取初始表单值。
class AgentProfileViewModel extends StateNotifier<AgentProfileState>
    with AgentReactiveState {
  final IAgentRepo _agentRepo;
  final IInstanceRepo _instanceRepo;
  final IMessageRepo _messageRepo;
  final IActivityRepo _activityRepo;
  final EvaluateAchievementsUseCase _evaluateAchievements;
  final IAvatarStorageService _avatarStorageService;
  final ILogger _logger;
  final String agentId;

  /// Public read-only view of [_agent] for UI consumers — 由
  /// [AgentReactiveState] mixin 提供 (Finding #8 重构)。
  // (agent getter 由 mixin 暴露)

  /// [AgentReactiveState] mixin 钩子：写入新 agent 后 bump
  /// [AgentProfileState.contentRevision]，驱动 Riverpod ref.watch 触发本
  /// build 重建。守卫逻辑（contentEquals 过滤同内容 emit）由 mixin 内的
  /// [setAgent] 负责。
  @override
  void onAgentUpdated() {
    _updateState((s) => s.copyWith(contentRevision: s.contentRevision + 1));
  }

  /// US-021 v1.1: 响应式重查入口。provider 侧 `ref.listen(agentSyncTickerProvider)`
  /// 在 agents 同步完成后调用，把最新 tombstone 状态写进 state。
  ///
  /// Like [achievementRefresh], this method protects against three
  /// concurrent paths racing into the same VM:
  ///   1. ticker listener calls refreshAgent while init() is still in flight
  ///   2. ticker listener calls refreshAgent after detail load failed (state
  ///      is LoadError — should not be silently mutated to LoadData)
  ///   3. ticker listener calls refreshAgent after the VM is disposed (provider
  ///      auto-dispose while _agentRepo.getById() is in flight)
  ///
  /// Without these guards:
  ///   - Case 1: an in-flight init's LoadError could be clobbered by a stale
  ///     getById result from the listener (UI shows mixed data)
  ///   - Case 2: a LoadError state is silently mutated to LoadData with a
  ///     half-populated detail (instance/messageCount/stats are all defaults
  ///     because we never re-ran the parallel loaders)
  ///   - Case 3: writing to `state` after dispose throws StateError and
  ///     crashes the provider
  Future<void> refreshAgent() async {
    // Pre-await guard: only proceed if VM is mounted AND we already have
    // an initial LoadData snapshot. If init hasn't finished yet or failed,
    // skip — the next sync tick will retry (init will eventually succeed
    // or the user will see the proper LoadError).
    if (!mounted) return;
    final initial = state.detailLoadState;
    if (initial is! LoadData<AgentDetailData>) return;

    final freshAgent = await _loadFreshAgentForRefresh();
    if (freshAgent == null) return;

    // Post-await guard 1: VM may have been disposed while we awaited
    // _agentRepo.getById(). Bailing here is safe — setAgent + state update
    // would throw StateError on a disposed notifier.
    if (!mounted) return;

    setAgent(freshAgent);

    // US-021 tombstone transition (sync discovered a tombstone):
    // setAgent above already flipped vm.agent.isRemoved = true (drives the
    // page-level AgentRemovedPlaceholder). Skip the state detailLoadState
    // update — copying `current.instance / messageCount / stats /
    // achievements` from the previous LoadData would yield a half-populated
    // LoadData with stale messageCount and stats next to the tombstone
    // placeholder. The page-level UI is the SSOT for tombstoned agents;
    // the detailLoadState carries only the data needed for alive agents.
    if (freshAgent.isRemoved) return;

    // Post-await guard 2: state may have transitioned out of LoadData while
    // we were awaiting (concurrent refresh() during init retry, or
    // saveProfile's internal refresh() clobbering it). Don't write back a
    // stale snapshot on top of a fresh LoadError or different LoadData.
    final after = state.detailLoadState;
    if (after is! LoadData<AgentDetailData>) return;
    final current = after.value;

    _updateState(
      (s) => s.copyWith(
        detailLoadState: LoadData(
          AgentDetailData(
            agent: freshAgent,
            instance: current.instance,
            messageCount: current.messageCount,
            stats: current.stats,
            achievements: current.achievements,
            dailyActivity: current.dailyActivity,
          ),
        ),
      ),
    );
  }

  Future<Agent?> _loadFreshAgentForRefresh() async {
    // Let exceptions propagate — the provider layer's catchError routes
    // them to ILogger. Catching here would swallow the failure silently.
    return await _agentRepo.getById(agentId);
  }

  /// BUG B 修复入口:暴露 agent 的 instanceId,让 provider 层的 ticker
  /// listener 能按 `next == instanceId` 过滤跨实例 sync,避免
  /// `_agentRepo.getById()` N+1 (N 个 active profile × 任意 sync)。
  ///
  /// 返回 null 当 [_agent] 尚未加载（init 未完成或 agent 在 DB 中不存在）。
  /// ticker 监听器在 null 时跳过 — 下次 sync tick 会再 fire,届时 _agent
  /// 必然已就绪。
  String? get instanceId => agent?.instanceId;

  /// Optional callback invoked when an avatar file needs cache eviction.
  ///
  /// Receives the absolute file path of the old avatar image. The callback
  /// is wired in the provider layer to call [imageCache.evict], keeping
  /// [dart:io] and [package:flutter/widgets.dart] out of the ViewModel.
  final void Function(String path)? _onAvatarChanged;

  AgentProfileViewModel({
    required this._agentRepo,
    required this._instanceRepo,
    required this._messageRepo,
    required this._activityRepo,
    required this._evaluateAchievements,
    required this._avatarStorageService,
    required this._logger,
    required this.agentId,
    this._onAvatarChanged,
  }) : super(const AgentProfileState());

  /// 初始化：加载 agent 详情 + 实例信息 + 消息统计。
  Future<void> init() async {
    await refresh();
  }

  /// 重新加载数据（外部触发：下拉刷新、config 保存后）。
  Future<void> refresh() async {
    _updateState((s) => s.copyWith(detailLoadState: const LoadInProgress()));

    try {
      final agent = await _agentRepo.getById(agentId);
      if (agent == null) throw AgentNotFoundError(agentId);
      // US-021 v1.1: 缓存 _agent 并同步 tombstone 状态（SSOT）。
      // Step 6: 走 setAgent —— 顺带 bump contentRevision 触发 UI rebuild，
      // 不再单独调 _syncAgentRemoved (helper 已删)。
      setAgent(agent);

      // The four detail-loads below are independent (instance + counts +
      // stats + activity) and only need the already-resolved agent. Run
      // them concurrently to halve TTI of the profile page; per-call
      // try/catch keeps best-effort semantics (a single failure doesn't
      // collapse the others).
      //
      // 使用 typed record 并行模式 (FutureRecord.wait) 而非
      // Future.wait<dynamic>([...]) + 位置强转:每个字段类型在编译期就绑
      // 定,后续增删字段时不存在错位风险(旧实现 results[N] as T 的位置
      // 强转会让"插入第 5 个 loader"成为静默回归源)。
      final (instance, messageCount, achievementResult, dailyActivity) = await (
        _safeGetInstance(agent.instanceId),
        _safeGetMessageCount(agentId),
        _safeEvaluateAchievements(agentId),
        _safeGetDailyActivity(agentId),
      ).wait;

      _updateState(
        (s) => s.copyWith(
          detailLoadState: LoadData(
            AgentDetailData(
              agent: agent,
              instance: instance,
              messageCount: messageCount,
              stats: achievementResult?.stats,
              achievements: achievementResult?.achievements ?? const [],
              dailyActivity: dailyActivity,
            ),
          ),
          newUnlocks: achievementResult?.freshUnlocks ?? const [],
        ),
      );
    } catch (error, stackTrace) {
      // US-021: 详情加载失败时不应继续显示 tombstone 占位页，否则用户看不到
      // 错误信息。setAgent(null) 清掉 _agent 缓存 + bump contentRevision，
      // UI 重建后 vm.agent.isTombstoned = false，回退到 LoadError
      // 而不是上一轮的 tombstone 占位页。
      setAgent(null);
      _updateState(
        (s) => s.copyWith(detailLoadState: LoadError(error, stackTrace)),
      );
    }
  }

  /// Best-effort loaders used by [refresh]. Each returns a sentinel value
  /// on failure (null / 0 / const []) so the parent can proceed without
  /// the dependent state but still surface the partial data.
  Future<Instance?> _safeGetInstance(String instanceId) async {
    try {
      return await _instanceRepo.getById(instanceId);
    } catch (error, stackTrace) {
      _logger.error(
        'Instance lookup failed for $instanceId: $error',
        stackTrace,
      );
      return null;
    }
  }

  Future<int> _safeGetMessageCount(String id) async {
    try {
      return await _messageRepo.getMessageCount(id);
    } catch (error, stackTrace) {
      _logger.error('Message count lookup failed for $id: $error', stackTrace);
      return 0;
    }
  }

  Future<_AchievementResult?> _safeEvaluateAchievements(String id) async {
    try {
      final result = await _evaluateAchievements.execute(id);
      return (
        stats: result.stats,
        achievements: result.achievements,
        freshUnlocks: result.freshUnlocks,
      );
    } catch (error, stackTrace) {
      _logger.error(
        'Stats/achievement load failed for $id: $error',
        stackTrace,
      );
      return null;
    }
  }

  Future<List<DailyActivity>> _safeGetDailyActivity(String id) async {
    try {
      return await _activityRepo.getDailyActivity(id);
    } catch (error, stackTrace) {
      _logger.error('Daily activity load failed for $id: $error', stackTrace);
      return const [];
    }
  }

  /// 局部刷新入口 — 只更新 stats/achievements/newUnlocks 三个字段,
  /// 不触碰 detailLoadState、agent、instance、messageCount、dailyActivity。
  ///
  /// 由 AchievementChecker.updates stream listener 调用,避免与
  /// [saveProfile] 内部的 `await refresh()` 互相覆盖 detailLoadState
  /// (race 修复)。listener 触发时不应打断用户在 Config 页的保存流程,
  /// 也不应让 Profile 页闪一下 `LoadInProgress` 空白状态。
  ///
  /// 边界:
  /// - detailLoadState 是 LoadInProgress (init 未完成): no-op,
  ///   下次 stream emit 会自然覆盖 (init 完成后)。
  /// - detailLoadState 是 LoadError: no-op,避免破坏错误状态展示。
  /// - detailLoadState 是 LoadData: 更新三个字段,detailLoadState 保持
  ///   LoadData,不重置为 LoadInProgress。
  ///
  /// 不更新 isSaving / saveError / saveSuccess — 与保存流程正交,
  /// 即使在 saveProfile 进行中触发也不会覆盖 Config 页的状态。
  Future<void> achievementRefresh() async {
    final current = state.detailLoadState;
    if (current is! LoadData<AgentDetailData>) return;

    final result = await _safeEvaluateAchievements(agentId);
    if (result == null) return;
    if (!mounted) return;

    // Re-read after the async gap: detailLoadState might have transitioned
    // (e.g. tombstone guard, concurrent refresh). Bail if it's no longer
    // LoadData — don't clobber a fresh error state with stale stats.
    final after = state.detailLoadState;
    if (after is! LoadData<AgentDetailData>) return;
    final currentDetail = after.value;

    // Skip the state write if nothing changed — every chat message would
    // otherwise re-emit the same AgentDetailData and trigger a downstream
    // rebuild. UI bumps newUnlocks only on real unlocks, which the use case
    // already filters — but the comparison must include freshUnlocks
    // otherwise a recompute that returns the same stats+achievements but a
    // non-empty freshUnlocks (e.g. a celebration replay path, or a future
    // use-case variant that decouples the two) would silently drop the
    // unlock event here.
    //
    // Use content equality, NOT `==`. `AgentStats.==` is field-based
    // (safe), but `List<Achievement> ==` is identity in Dart — the use
    // case constructs a fresh list every call, so two semantically-equal
    // lists compare unequal and the skip would never fire (the
    // [[model-equals-identity-blindspot]] trap).
    if (result.stats == currentDetail.stats &&
        listEquals(result.achievements, currentDetail.achievements) &&
        listEquals(result.freshUnlocks, state.newUnlocks)) {
      return;
    }

    _updateState(
      (s) => s.copyWith(
        detailLoadState: LoadData(
          AgentDetailData(
            agent: currentDetail.agent,
            instance: currentDetail.instance,
            messageCount: currentDetail.messageCount,
            stats: result.stats,
            achievements: result.achievements,
            dailyActivity: currentDetail.dailyActivity,
          ),
        ),
        newUnlocks: result.freshUnlocks,
      ),
    );
  }

  /// 保存个性化配置（由 AgentConfigPage 调用）。
  Future<void> saveProfile({
    String? nickname,
    String? themeColor,
    String? avatarUrl,
    List<QuickCommand>? quickCommands,
  }) async {
    // US-021 v1.1: tombstoned 或尚未加载的 agent 拒绝保存 —— 防止后端已删除
    // 或状态未知时用户仍能编辑/保存，造成 DB 与 Gateway 不一致。
    // US-021 v1.2 修复：阻断必须 surface saveError，否则 UI 看不到反馈。
    // 区分 null（未加载）和 tombstoned（已删除）两条文案。
    if (agent == null) {
      _logger.info('saveProfile blocked: agent not loaded');
      _updateState((s) => s.copyWith(saveError: '数据尚未加载完成，请稍后再试'));
      return;
    }
    if (agent!.isRemoved) {
      _logger.info('saveProfile blocked: agent tombstoned');
      _updateState((s) => s.copyWith(saveError: '该 Agent 已被 Gateway 移除，无法保存'));
      return;
    }
    if (state.isSaving) return;
    _updateState(
      (s) => s.copyWith(isSaving: true, saveError: null, saveSuccess: false),
    );
    try {
      // Single transactional write — profile fields + quick commands
      // succeed or fail together (no half-committed state).
      await _agentRepo.updateFullProfile(
        agentId,
        nickname: nickname,
        themeColor: themeColor,
        avatarUrl: avatarUrl,
        quickCommands: quickCommands,
      );
      // 保存后刷新详情数据，Profile 页自动看到最新值
      await refresh();
      _updateState((s) => s.copyWith(isSaving: false, saveSuccess: true));
    } catch (error, stackTrace) {
      _logger.error('AgentConfig save failed: $error', stackTrace);
      _updateState((s) => s.copyWith(isSaving: false, saveError: '保存失败，请重试'));
    }
  }

  /// 更新头像 — 保存图片文件 + 持久化路径 + 清除图片缓存。
  ///
  /// [imageBytes] 应为已压缩的 JPEG 字节（由 [ImagePicker] 的
  /// maxWidth/maxHeight/imageQuality 参数在选取时完成压缩）。
  Future<void> updateAvatar(Uint8List imageBytes) async {
    // US-021 v1.1: tombstoned 或尚未加载的 agent 拒绝写入头像。
    // US-021 v1.2 修复：阻断必须 surface saveError（见 saveProfile 注释）。
    if (agent == null) {
      _logger.info('updateAvatar blocked: agent not loaded');
      _updateState((s) => s.copyWith(saveError: '数据尚未加载完成，请稍后再试'));
      return;
    }
    if (agent!.isRemoved) {
      _logger.info('updateAvatar blocked: agent tombstoned');
      _updateState(
        (s) => s.copyWith(saveError: '该 Agent 已被 Gateway 移除，无法上传头像'),
      );
      return;
    }
    return _runAvatarOp(
      opTag: 'save',
      errLabel: '头像保存失败，请重试',
      body: () async {
        // 1) Save image to disk
        final savedPath = await _avatarStorageService.saveAvatar(
          agentId,
          imageBytes,
        );

        // 2) Persist path in database
        await _agentRepo.updateLocalProfile(agentId, avatarUrl: savedPath);

        // 3) Notify UI layer to evict stale Flutter image cache
        // (same path → new content). Best-effort via callback —
        // non-fatal if unavailable (e.g. in unit tests).
        _onAvatarChanged?.call(savedPath);
      },
      onErrorRollback: () async {
        // 回滚：删除已写入的孤儿文件（best-effort，不覆盖原始错误）。
        try {
          await _avatarStorageService.deleteAvatar(agentId);
        } catch (_) {
          /* iron-law-allow: Law8 — best-effort cleanup */
        }
      },
    );
  }

  /// 移除头像 — 删除文件 + 清空 DB 中的 avatarUrl + 清除缓存。
  Future<void> removeAvatar() async {
    // US-021 v1.1: tombstoned 或尚未加载的 agent 拒绝清除头像（同样不会触达 DB）。
    // US-021 v1.2 修复：阻断必须 surface saveError（见 saveProfile 注释）。
    if (agent == null) {
      _logger.info('removeAvatar blocked: agent not loaded');
      _updateState((s) => s.copyWith(saveError: '数据尚未加载完成，请稍后再试'));
      return;
    }
    if (agent!.isRemoved) {
      _logger.info('removeAvatar blocked: agent tombstoned');
      _updateState(
        (s) => s.copyWith(saveError: '该 Agent 已被 Gateway 移除，无法移除头像'),
      );
      return;
    }
    return _runAvatarOp(
      opTag: 'remove',
      errLabel: '头像移除失败，请重试',
      body: () async {
        // Capture current avatarUrl from loaded agent data for cache eviction.
        // Using the known path avoids relying on getAvatarPath's implicit
        // dependency on _appDocDirPath being initialized by a prior async call.
        final currentAvatarUrl = switch (state.detailLoadState) {
          LoadData<AgentDetailData>(:final value) => value.agent.avatarUrl,
          _ => null,
        };

        // 1) Delete file from disk (no-op if already deleted)
        await _avatarStorageService.deleteAvatar(agentId);

        // 2) Clear avatarUrl in database — 使用 clearAvatar() 而非
        //    updateLocalProfile(avatarUrl: null)，因为后者在 Drift 仓库中
        //    使用 Value.absent() 语义（跳过该列），无法真正清除已有值。
        await _agentRepo.clearAvatar(agentId);

        // 3) Notify UI layer to evict stale cache — best-effort via callback.
        // Uses the known avatarUrl rather than recomputing via getAvatarPath.
        if (currentAvatarUrl != null) {
          _onAvatarChanged?.call(currentAvatarUrl);
        }
      },
    );
  }

  /// 头像变更操作的公共骨架 —— 共享 isSaving 守卫、状态更新、刷新、
  /// 错误处理与日志。两个公开方法（[updateAvatar] / [removeAvatar]）
  /// 各自只负责自己的差异步骤（save vs delete、updateLocalProfile vs
  /// clearAvatar），并通过 [onErrorRollback] 提供回滚钩子。
  Future<void> _runAvatarOp({
    required String opTag,
    required String errLabel,
    required Future<void> Function() body,
    Future<void> Function()? onErrorRollback,
  }) async {
    if (state.isSaving) return;
    _updateState(
      (s) => s.copyWith(isSaving: true, saveError: null, saveSuccess: false),
    );
    try {
      await body();
      // 4) Reload agent data so UI picks up new avatarUrl.
      await refresh();
      // 注意：不设置 saveSuccess=true，避免触发 AgentConfigPage 的 pop
      // 监听器。头像变更是即时操作，不需要退出配置页。
      _updateState((s) => s.copyWith(isSaving: false));
    } catch (error, stackTrace) {
      _logger.error('Avatar $opTag failed: $error', stackTrace);
      if (onErrorRollback != null) {
        await onErrorRollback();
      }
      _updateState((s) => s.copyWith(isSaving: false, saveError: errLabel));
    }
  }

  /// 消费保存结果（Config 页 pop 后或 SnackBar 展示后调用）。
  void clearSaveResult() {
    _updateState((s) => s.copyWith(saveSuccess: false, saveError: null));
  }

  /// 消费新解锁成就（庆祝动画播放完毕后调用）。
  void clearNewUnlocks() {
    _updateState((s) => s.copyWith(newUnlocks: const []));
  }

  /// 更新状态并忽略 dispose 后的调用。
  ///
  /// [StateNotifier.mounted] 在 [dispose] 后变为 false。refresh()
  /// 是异步的（含 await 调用），可能在用户导航离开、Provider 已销毁
  /// 后才完成。此时静默丢弃更新是正确的 — no-op 远比尝试 set
  /// disposed state 导致的崩溃安全。
  void _updateState(AgentProfileState Function(AgentProfileState) transform) {
    if (!mounted) return;
    state = transform(state);
  }
}
