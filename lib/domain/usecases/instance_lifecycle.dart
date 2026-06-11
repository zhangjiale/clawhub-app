import '../models/instance.dart';

/// 实例生命周期回调接口 — 定义实例保存/删除后的编排操作。
///
/// 由 [ConnectionOrchestrator]（app 层）实现，供 UseCase（domain 层）
/// 在完成持久化操作后调用。UI 层完全不需要知道编排器的存在，
/// 只需调用 UseCase → UseCase 自动触发后续编排。
///
/// 对齐 Law 3（面向接口编程）：domain 定义契约，app 层实现。
abstract class IInstanceLifecycle {
  /// 实例保存后调用（新建或编辑时）。
  ///
  /// 编排器负责建立/刷新 WebSocket 连接。
  Future<void> onInstanceSaved(Instance instance);

  /// 实例删除后调用。
  ///
  /// 编排器负责断开 WebSocket 连接并清理资源。
  Future<void> onInstanceDeleted(String instanceId);
}
