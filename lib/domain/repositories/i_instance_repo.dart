import '../models/instance.dart';
import '../models/enums.dart';

/// 实例仓库接口
/// 对齐: 架构 vFinal 5.1 (网关防腐层与连接状态机)
abstract class IInstanceRepo {
  /// 获取所有已保存的实例（按最后连接时间降序）
  Future<List<Instance>> getAll();

  /// 根据 ID 获取单个实例
  Future<Instance?> getById(String id);

  /// 批量根据 ID 获取实例（替代 N+1 查询，Law 6）。
  /// 返回 `Map<id, Instance>`，未找到的 ID 不出现在结果中。
  /// 传入空列表时返回空 Map（不查询数据库）。
  /// 契约对齐 [IAgentRepo.getByIds]。
  Future<Map<String, Instance>> getByIds(List<String> ids);

  /// 保存实例（新增或更新）
  /// 返回保存后的实例
  Future<Instance> save(Instance instance);

  /// 删除实例及其关联的所有本地数据
  Future<void> delete(String id);

  /// 检查实例名称是否已存在（排除指定 ID）
  Future<bool> nameExists(String name, {String? excludeId});

  /// 更新实例健康状态
  Future<Instance> updateHealthStatus(String id, HealthStatus status);

  /// 更新最后连接时间
  Future<void> updateLastConnectedAt(String id, int timestamp);

  /// 批量更新指定网络类型的实例状态，返回被更新的实例 ID 列表。
  /// 用于 WiFi→4G 时标记内网实例为 EXPECTED_OFFLINE。
  Future<List<String>> batchUpdateStatusByNetwork({
    required bool isLocalNetwork,
    required HealthStatus status,
  });
}
