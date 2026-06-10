import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/utils/copy_with_nullable.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/errors.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';

/// Agent 详情聚合数据（不可变值对象）
class AgentDetailData {
  final Agent agent;
  final Instance? instance;
  final int messageCount;

  const AgentDetailData({
    required this.agent,
    this.instance,
    required this.messageCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDetailData &&
          agent == other.agent &&
          instance == other.instance &&
          messageCount == other.messageCount;

  @override
  int get hashCode => Object.hash(agent, instance, messageCount);
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

  const AgentProfileState({
    this.detailLoadState = const LoadInProgress(),
    this.isSaving = false,
    this.saveError,
    this.saveSuccess = false,
  });

  /// copyWith 使用 [CopyWithSentinel] 区分 "未传参" 和 "显式传 null"，
  /// 避免手写 sentinel 单例导致的样板代码。
  AgentProfileState copyWith({
    LoadState<AgentDetailData>? detailLoadState,
    bool? isSaving,
    Object? saveError = CopyWithSentinel.instance,
    bool? saveSuccess,
  }) {
    return AgentProfileState(
      detailLoadState: detailLoadState ?? this.detailLoadState,
      isSaving: isSaving ?? this.isSaving,
      saveError: copyWithNullable(saveError, this.saveError),
      saveSuccess: saveSuccess ?? this.saveSuccess,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentProfileState &&
          detailLoadState == other.detailLoadState &&
          isSaving == other.isSaving &&
          saveError == other.saveError &&
          saveSuccess == other.saveSuccess;

  @override
  int get hashCode =>
      Object.hash(detailLoadState, isSaving, saveError, saveSuccess);
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
  final String agentId;

  AgentProfileViewModel({
    required IAgentRepo agentRepo,
    required IInstanceRepo instanceRepo,
    required IMessageRepo messageRepo,
    required this.agentId,
  })  : _agentRepo = agentRepo,
       _instanceRepo = instanceRepo,
       _messageRepo = messageRepo,
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

      _updateState((s) => s.copyWith(
        detailLoadState: LoadData(AgentDetailData(
          agent: agent,
          instance: instance,
          messageCount: messageCount,
        )),
      ));
    } catch (error, stackTrace) {
      _updateState((s) => s.copyWith(
        detailLoadState: LoadError(error, stackTrace),
      ));
    }
  }

  /// 保存个性化配置（由 AgentConfigPage 调用）。
  Future<void> saveProfile(
    String? nickname,
    String themeColor,
  ) async {
    if (state.isSaving) return;
    _updateState((s) => s.copyWith(
      isSaving: true,
      saveError: null,
      saveSuccess: false,
    ));
    try {
      await _agentRepo.updateLocalProfile(
        agentId,
        nickname: nickname,
        themeColor: themeColor,
      );
      // 保存后刷新详情数据，Profile 页自动看到最新值
      await refresh();
      _updateState((s) => s.copyWith(isSaving: false, saveSuccess: true));
    } catch (error, stackTrace) {
      debugPrint('AgentConfig save failed: $error\n$stackTrace');
      _updateState((s) => s.copyWith(
        isSaving: false,
        saveError: '保存失败，请重试',
      ));
    }
  }

  /// 消费保存结果（Config 页 pop 后或 SnackBar 展示后调用）。
  void clearSaveResult() {
    _updateState((s) => s.copyWith(saveSuccess: false, saveError: null));
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
