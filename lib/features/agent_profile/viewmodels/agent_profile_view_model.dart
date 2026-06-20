import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/utils/copy_with_nullable.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/errors.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';

/// Agent 详情聚合数据（不可变值对象）
class AgentDetailData {
  final Agent agent;
  final Instance? instance;
  final int messageCount;
  final AgentStats? stats;
  final List<Achievement> achievements;

  const AgentDetailData({
    required this.agent,
    this.instance,
    required this.messageCount,
    this.stats,
    this.achievements = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDetailData &&
          agent == other.agent &&
          instance == other.instance &&
          messageCount == other.messageCount &&
          stats == other.stats &&
          achievements == other.achievements;

  @override
  int get hashCode =>
      Object.hash(agent, instance, messageCount, stats, achievements);
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

  const AgentProfileState({
    this.detailLoadState = const LoadInProgress(),
    this.isSaving = false,
    this.saveError,
    this.saveSuccess = false,
    this.newUnlocks = const [],
  });

  /// copyWith 使用 [CopyWithSentinel] 区分 "未传参" 和 "显式传 null"，
  /// 避免手写 sentinel 单例导致的样板代码。
  AgentProfileState copyWith({
    LoadState<AgentDetailData>? detailLoadState,
    bool? isSaving,
    Object? saveError = CopyWithSentinel.instance,
    bool? saveSuccess,
    List<Achievement>? newUnlocks,
  }) {
    return AgentProfileState(
      detailLoadState: detailLoadState ?? this.detailLoadState,
      isSaving: isSaving ?? this.isSaving,
      saveError: copyWithNullable(saveError, this.saveError),
      saveSuccess: saveSuccess ?? this.saveSuccess,
      newUnlocks: newUnlocks ?? this.newUnlocks,
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
          newUnlocks == other.newUnlocks;

  @override
  int get hashCode => Object.hash(
    detailLoadState,
    isSaving,
    saveError,
    saveSuccess,
    newUnlocks,
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
  final EvaluateAchievementsUseCase _evaluateAchievements;
  final IAvatarStorageService _avatarStorageService;
  final String agentId;

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
    required EvaluateAchievementsUseCase evaluateAchievements,
    required IAvatarStorageService avatarStorageService,
    required this.agentId,
    void Function(String path)? onAvatarChanged,
  }) : _agentRepo = agentRepo,
       _instanceRepo = instanceRepo,
       _messageRepo = messageRepo,
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

      Instance? instance;
      try {
        instance = await _instanceRepo.getById(agent.instanceId);
      } catch (error, stackTrace) {
        debugPrint(
          'Instance lookup failed for ${agent.instanceId}: $error\n$stackTrace',
        );
        // instance 不存在是非致命错误
      }

      final messageCount = await _messageRepo.getMessageCount(agentId);

      // Load stats and achievements (best-effort — non-fatal on failure).
      // Delegated to EvaluateAchievementsUseCase to avoid duplicating the
      // cache-first → evaluate → batch-unlock pipeline with AchievementChecker.
      AgentStats? stats;
      List<Achievement> achievements = const [];
      List<Achievement> freshUnlocks = const [];
      try {
        final result = await _evaluateAchievements.execute(agentId);
        stats = result.stats;
        achievements = result.achievements;
        freshUnlocks = result.freshUnlocks;
      } catch (error, stackTrace) {
        debugPrint(
          'Stats/achievement load failed for $agentId: $error\n$stackTrace',
        );
        // Non-fatal — profile page still shows agent info + message count
      }

      _updateState(
        (s) => s.copyWith(
          detailLoadState: LoadData(
            AgentDetailData(
              agent: agent,
              instance: instance,
              messageCount: messageCount,
              stats: stats,
              achievements: achievements,
            ),
          ),
          newUnlocks: freshUnlocks,
        ),
      );
    } catch (error, stackTrace) {
      _updateState(
        (s) => s.copyWith(detailLoadState: LoadError(error, stackTrace)),
      );
    }
  }

  /// 保存个性化配置（由 AgentConfigPage 调用）。
  Future<void> saveProfile({
    String? nickname,
    String? themeColor,
    String? avatarUrl,
    List<QuickCommand>? quickCommands,
  }) async {
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
    if (state.isSaving) return;
    _updateState(
      (s) => s.copyWith(isSaving: true, saveError: null, saveSuccess: false),
    );
    try {
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

      // 4) Reload agent data so UI picks up new avatarUrl
      await refresh();
      // 注意：不设置 saveSuccess=true，避免触发 AgentConfigPage 的 pop 监听器。
      // 头像变更是即时操作，不需要退出配置页。
      _updateState((s) => s.copyWith(isSaving: false));
    } catch (error, stackTrace) {
      debugPrint('Avatar save failed: $error\n$stackTrace');
      // 回滚：删除已写入的孤儿文件（best-effort，不覆盖原始错误）。
      try {
        await _avatarStorageService.deleteAvatar(agentId);
      } catch (_) {
        /* iron-law-allow: Law8 — best-effort cleanup */
      }
      _updateState((s) => s.copyWith(isSaving: false, saveError: '头像保存失败，请重试'));
    }
  }

  /// 移除头像 — 删除文件 + 清空 DB 中的 avatarUrl + 清除缓存。
  Future<void> removeAvatar() async {
    if (state.isSaving) return;
    _updateState(
      (s) => s.copyWith(isSaving: true, saveError: null, saveSuccess: false),
    );
    try {
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

      // 4) Reload
      await refresh();
      // 注意：不设置 saveSuccess=true，避免触发 AgentConfigPage 的 pop 监听器。
      _updateState((s) => s.copyWith(isSaving: false));
    } catch (error, stackTrace) {
      debugPrint('Avatar remove failed: $error\n$stackTrace');
      _updateState((s) => s.copyWith(isSaving: false, saveError: '头像移除失败，请重试'));
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
