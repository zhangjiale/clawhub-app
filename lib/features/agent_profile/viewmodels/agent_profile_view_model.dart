import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Sentinel 用于区分 \"未传参\" 和 \"显式传 null\"
  static const _sentinel = Object();

  AgentProfileState copyWith({
    LoadState<AgentDetailData>? detailLoadState,
    bool? isSaving,
    Object? saveError = _sentinel,
    bool? saveSuccess,
  }) {
    return AgentProfileState(
      detailLoadState: detailLoadState ?? this.detailLoadState,
      isSaving: isSaving ?? this.isSaving,
      saveError:
          identical(saveError, _sentinel) ? this.saveError : saveError as String?,
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
