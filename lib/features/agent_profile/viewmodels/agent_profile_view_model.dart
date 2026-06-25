import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/utils/copy_with_nullable.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
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
class AgentProfileState {
  final LoadState<AgentDetailData> detailLoadState;
  final bool isSaving;
  final String? saveError;
  final bool saveSuccess;
  final List<Achievement> newUnlocks; // freshly unlocked this session

  /// US-021 v1.1: 当前 agent 是否已被 Gateway 端删除（tombstoned）。
  /// 响应式字段 —— 与 ChatSessionState.isAgentRemoved 模式一致。
  /// 任何 `_agent =` 写入点必须同步此字段（_syncAgentRemoved helper）。
  final bool isAgentRemoved;

  const AgentProfileState({
    this.detailLoadState = const LoadInProgress(),
    this.isSaving = false,
    this.saveError,
    this.saveSuccess = false,
    this.newUnlocks = const [],
    this.isAgentRemoved = false,
  });

  /// copyWith 使用 [CopyWithSentinel] 区分 "未传参" 和 "显式传 null"，
  /// 避免手写 sentinel 单例导致的样板代码。
  AgentProfileState copyWith({
    LoadState<AgentDetailData>? detailLoadState,
    bool? isSaving,
    Object? saveError = CopyWithSentinel.instance,
    bool? saveSuccess,
    List<Achievement>? newUnlocks,
    bool? isAgentRemoved,
  }) {
    return AgentProfileState(
      detailLoadState: detailLoadState ?? this.detailLoadState,
      isSaving: isSaving ?? this.isSaving,
      saveError: copyWithNullable(saveError, this.saveError),
      saveSuccess: saveSuccess ?? this.saveSuccess,
      newUnlocks: newUnlocks ?? this.newUnlocks,
      isAgentRemoved: isAgentRemoved ?? this.isAgentRemoved,
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
          isAgentRemoved == other.isAgentRemoved;

  @override
  int get hashCode => Object.hash(
    detailLoadState,
    isSaving,
    saveError,
    saveSuccess,
    newUnlocks,
    isAgentRemoved,
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
class AgentProfileViewModel extends StateNotifier<AgentProfileState> {
  final IAgentRepo _agentRepo;
  final IInstanceRepo _instanceRepo;
  final IMessageRepo _messageRepo;
  final IActivityRepo _activityRepo;
  final EvaluateAchievementsUseCase _evaluateAchievements;
  final IAvatarStorageService _avatarStorageService;
  final String agentId;

  /// US-021 v1.1: 私有缓存，与 ChatViewModel._agent 模式一致。
  /// 用于 write guard 在不重新查库的前提下判断 tombstone 状态。
  Agent? _agent;

  /// US-021 v1.1: 同步 _agent 的 tombstone 状态到 state.isAgentRemoved。
  /// 必须在每个 `_agent =` 写入点调用一次（SSOT）。
  void _syncAgentRemoved() {
    _updateState((s) => s.copyWith(isAgentRemoved: _agent?.isRemoved ?? false));
  }

  /// US-021 v1.1: 响应式重查入口。provider 侧 `ref.listen(agentSyncTickerProvider)`
  /// 在 agents 同步完成后调用，把最新 tombstone 状态写进 state。
  Future<void> refreshAgent() async {
    try {
      _agent = await _agentRepo.getById(agentId);
    } catch (e, st) {
      debugPrint('[AgentProfileViewModel] refreshAgent failed: $e\n$st');
      return;
    }
    _syncAgentRemoved();
  }

  /// BUG B 修复入口:暴露 agent 的 instanceId,让 provider 层的 ticker
  /// listener 能按 `next == instanceId` 过滤跨实例 sync,避免
  /// `_agentRepo.getById()` N+1 (N 个 active profile × 任意 sync)。
  ///
  /// 返回 null 当 [_agent] 尚未加载（init 未完成或 agent 在 DB 中不存在）。
  /// ticker 监听器在 null 时跳过 — 下次 sync tick 会再 fire,届时 _agent
  /// 必然已就绪。
  String? get instanceId => _agent?.instanceId;

  /// Optional callback invoked when an avatar file needs cache eviction.
  ///
  /// Receives the absolute file path of the old avatar image. The callback
  /// is wired in the provider layer to call [imageCache.evict], keeping
  /// [dart:io] and [package:flutter/widgets.dart] out of the ViewModel.
  final void Function(String path)? _onAvatarChanged;

  AgentProfileViewModel({
    required IAgentRepo agentRepo,
    required IInstanceRepo instanceRepo,
    required IMessageRepo messageRepo,
    required IActivityRepo activityRepo,
    required EvaluateAchievementsUseCase evaluateAchievements,
    required IAvatarStorageService avatarStorageService,
    required this.agentId,
    void Function(String path)? onAvatarChanged,
  }) : _agentRepo = agentRepo,
       _instanceRepo = instanceRepo,
       _messageRepo = messageRepo,
       _activityRepo = activityRepo,
       _evaluateAchievements = evaluateAchievements,
       _avatarStorageService = avatarStorageService,
       _onAvatarChanged = onAvatarChanged,
       super(const AgentProfileState());

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
      _agent = agent;
      _syncAgentRemoved();

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
      // 错误信息。重置 isAgentRemoved 让 UI 回退到 LoadError 状态。
      _updateState(
        (s) => s.copyWith(
          detailLoadState: LoadError(error, stackTrace),
          isAgentRemoved: false,
        ),
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
      debugPrint('Instance lookup failed for $instanceId: $error\n$stackTrace');
      return null;
    }
  }

  Future<int> _safeGetMessageCount(String id) async {
    try {
      return await _messageRepo.getMessageCount(id);
    } catch (error, stackTrace) {
      debugPrint('Message count lookup failed for $id: $error\n$stackTrace');
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
      debugPrint('Stats/achievement load failed for $id: $error\n$stackTrace');
      return null;
    }
  }

  Future<List<DailyActivity>> _safeGetDailyActivity(String id) async {
    try {
      return await _activityRepo.getDailyActivity(id);
    } catch (error, stackTrace) {
      debugPrint('Daily activity load failed for $id: $error\n$stackTrace');
      return const [];
    }
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
    if (_agent == null) {
      debugPrint(
        '[AgentProfileViewModel] saveProfile blocked: agent not loaded',
      );
      _updateState((s) => s.copyWith(saveError: '数据尚未加载完成，请稍后再试'));
      return;
    }
    if (_agent!.isRemoved) {
      debugPrint(
        '[AgentProfileViewModel] saveProfile blocked: agent tombstoned',
      );
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
      debugPrint('AgentConfig save failed: $error\n$stackTrace');
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
    if (_agent == null) {
      debugPrint(
        '[AgentProfileViewModel] updateAvatar blocked: agent not loaded',
      );
      _updateState((s) => s.copyWith(saveError: '数据尚未加载完成，请稍后再试'));
      return;
    }
    if (_agent!.isRemoved) {
      debugPrint(
        '[AgentProfileViewModel] updateAvatar blocked: agent tombstoned',
      );
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
    if (_agent == null) {
      debugPrint(
        '[AgentProfileViewModel] removeAvatar blocked: agent not loaded',
      );
      _updateState((s) => s.copyWith(saveError: '数据尚未加载完成，请稍后再试'));
      return;
    }
    if (_agent!.isRemoved) {
      debugPrint(
        '[AgentProfileViewModel] removeAvatar blocked: agent tombstoned',
      );
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
      debugPrint('Avatar $opTag failed: $error\n$stackTrace');
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
