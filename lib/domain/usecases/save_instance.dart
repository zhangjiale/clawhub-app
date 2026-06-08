import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../repositories/i_instance_repo.dart';
import '../../core/acl/i_gateway_client.dart';

/// 保存实例用例（统一创建与编辑）
/// 对齐: PRD 3.1 (实例连接管理)
///
/// 流程:
/// 1. 校验名称和 URL 合法性
/// 2. 检查名称唯一性（编辑时排除自身）
/// 3. 执行连通性测试
/// 4. 保存实例（在线/离线）
///
/// [instanceId] 为 null 时创建新实例，非 null 时编辑已有实例。
class SaveInstanceUseCase {
  final IInstanceRepo _instanceRepo;
  final IGatewayClient _gatewayClient;
  final Uuid _uuid;

  SaveInstanceUseCase({
    required IInstanceRepo instanceRepo,
    required IGatewayClient gatewayClient,
    Uuid? uuid,
  })  : _instanceRepo = instanceRepo,
        _gatewayClient = gatewayClient,
        _uuid = uuid ?? const Uuid();

  /// 保存实例（创建或更新）
  Future<Instance> execute({
    required String name,
    required String gatewayUrl,
    required String token,
    String? instanceId, // null = create, non-null = update
  }) async {
    // 1. 基本校验
    if (name.trim().isEmpty) {
      throw ArgumentError('实例名称不能为空');
    }

    final trimmedName = name.trim();
    final trimmedUrl = gatewayUrl.trim();
    final isUpdate = instanceId != null;

    // 2. 名称唯一性检查 + 获取已有实例（编辑时重用，避免重复查询）
    Instance? existing;
    if (isUpdate) {
      existing = await _instanceRepo.getById(instanceId);
      if (existing == null) {
        throw ArgumentError('实例不存在');
      }
      if (trimmedName != existing.name) {
        final nameTaken = await _instanceRepo.nameExists(
          trimmedName,
          excludeId: instanceId,
        );
        if (nameTaken) {
          throw ArgumentError('实例名称"$trimmedName"已存在');
        }
      }
    } else {
      final exists = await _instanceRepo.nameExists(trimmedName);
      if (exists) {
        throw ArgumentError('实例名称"$trimmedName"已存在');
      }
    }

    // 3. 构建实例
    final Instance instance;
    if (isUpdate) {
      instance = existing!.copyWith(
        name: trimmedName,
        gatewayUrl: trimmedUrl,
        tokenRef: token,
      );
    } else {
      instance = Instance(
        id: _uuid.v4(),
        name: trimmedName,
        gatewayUrl: trimmedUrl,
        tokenRef: token,
      );
    }

    // 4. 连通性测试
    final isOnline = await _gatewayClient.testConnection(instance);

    // 5. 保存（标记在线/离线）
    final saved = await _instanceRepo.save(
      instance.copyWith(
        healthStatus: isOnline ? HealthStatus.online : HealthStatus.offline,
        lastConnectedAt:
            isOnline ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : null,
      ),
    );

    return saved;
  }
}
