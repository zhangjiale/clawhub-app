import '../repositories/i_instance_repo.dart';
import 'instance_lifecycle.dart';

/// 删除实例用例。
///
/// 流程:
/// 1. 从持久化存储删除实例及其关联数据
/// 2. 通知 [IInstanceLifecycle] 断开 WebSocket 连接并清理资源
class DeleteInstanceUseCase {
  final IInstanceRepo _instanceRepo;
  final IInstanceLifecycle? _lifecycle;

  DeleteInstanceUseCase({
    required IInstanceRepo instanceRepo,
    IInstanceLifecycle? lifecycle,
  })  : _instanceRepo = instanceRepo,
        _lifecycle = lifecycle;

  /// 删除指定实例。
  ///
  /// 删除后自动通知编排器断开连接。
  Future<void> execute(String instanceId) async {
    await _instanceRepo.delete(instanceId);
    await _lifecycle?.onInstanceDeleted(instanceId);
  }
}
