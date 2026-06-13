import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../repositories/i_instance_repo.dart';
import '../../core/acl/i_gateway_client.dart';
import 'instance_lifecycle.dart';

/// 保存实例用例（统一创建与编辑）
/// 对齐: PRD 3.1 (实例连接管理)
///
/// 流程:
/// 1. 校验名称和 URL 合法性
/// 2. 检查名称唯一性（编辑时排除自身）
/// 3. 执行连通性测试
/// 4. 保存实例（在线/离线）
/// 5. 通知 [IInstanceLifecycle] 触发后续编排（WebSocket 连接等）
///
/// [instanceId] 为 null 时创建新实例，非 null 时编辑已有实例。
class SaveInstanceUseCase {
  final IInstanceRepo _instanceRepo;
  final IGatewayClient _gatewayClient;
  final IInstanceLifecycle? _lifecycle;
  final Uuid _uuid;

  SaveInstanceUseCase({
    required IInstanceRepo instanceRepo,
    required IGatewayClient gatewayClient,
    IInstanceLifecycle? lifecycle,
    Uuid? uuid,
  }) : _instanceRepo = instanceRepo,
       _gatewayClient = gatewayClient,
       _lifecycle = lifecycle,
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
        lastConnectedAt: isOnline
            ? DateTime.now().millisecondsSinceEpoch ~/ 1000
            : null,
      ),
    );
    // 6. 通知生命周期层（编排 WebSocket 连接），始终调用。
    //
    //    isOnline 仅用于决定初始 healthStatus（online/offline），连接策略
    //    （是否建连、何时建连）属于 ConnectionOrchestrator 的职责。
    //    testConnection 可能因网络抖动、DNS 延迟等原因返回 false，但
    //    Gateway 实际可达 —— 跳过 onInstanceSaved 会让实例永远失去重连机会。
    //
    //    ConnectionManager 内置指数退避自动重连（1→2→4→8→16s），对
    //    短暂不可达的 Gateway 有良好的恢复能力。testConnection 与
    //    onInstanceSaved 共用设备凭据的瞬时竞态由
    //    ConnectionManager._handleDeviceIdMismatch 自动 2s 重试处理。
    try {
      await _lifecycle?.onInstanceSaved(saved);
    } catch (_) {
      // 编排失败不应阻止 save 返回成功 — 实例已持久化。
      // 连接错误由 ConnectionOrchestrator 内部的自动重连机制自行处理。
      // 日志关注点属于外层（infrastructure/app），不在 domain 层。
    }

    return saved;
  }
}
