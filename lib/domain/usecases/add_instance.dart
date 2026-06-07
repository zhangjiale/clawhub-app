import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../repositories/i_instance_repo.dart';
import '../../core/acl/i_gateway_client.dart';

/// 添加实例用例
/// 对齐: PRD 3.1 (实例连接管理)
///
/// 流程:
/// 1. 校验名称和 URL 合法性
/// 2. 检查名称唯一性
/// 3. 执行连通性测试
/// 4. 保存实例（在线/离线）
class AddInstanceUseCase {
  final IInstanceRepo _instanceRepo;
  final IGatewayClient _gatewayClient;
  final Uuid _uuid;

  AddInstanceUseCase({
    required IInstanceRepo instanceRepo,
    required IGatewayClient gatewayClient,
    Uuid? uuid,
  })  : _instanceRepo = instanceRepo,
        _gatewayClient = gatewayClient,
        _uuid = uuid ?? const Uuid();

  Future<Instance> execute({
    required String name,
    required String gatewayUrl,
    required String token,
  }) async {
    // 1. 基本校验
    if (name.trim().isEmpty) {
      throw ArgumentError('实例名称不能为空');
    }

    // 2. 检查名称唯一性
    final exists = await _instanceRepo.nameExists(name.trim());
    if (exists) {
      throw ArgumentError('实例名称"$name"已存在');
    }

    // 3. 构建实例（构造时自动校验 URL 格式和内网检测）
    final id = _uuid.v4();
    final instance = Instance(
      id: id,
      name: name.trim(),
      gatewayUrl: gatewayUrl.trim(),
      tokenRef: token, // 生产环境中应加密后存储 tokenRef
    );

    // 4. 连通性测试
    final isOnline = await _gatewayClient.testConnection(instance);

    // 5. 保存（标记在线/离线）
    final saved = await _instanceRepo.save(
      instance.copyWith(
        healthStatus: isOnline ? HealthStatus.online : HealthStatus.offline,
        lastConnectedAt: isOnline ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : null,
      ),
    );

    return saved;
  }
}
