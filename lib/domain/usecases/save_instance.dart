import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../repositories/i_agent_repo.dart';
import '../repositories/i_instance_repo.dart';
import '../../core/acl/i_gateway_client.dart';
import '../../core/i_logger.dart';
import 'gateway_change_exceptions.dart';
import 'gateway_change_resolution.dart';
import 'instance_lifecycle.dart';

/// 保存实例用例（统一创建与编辑）
/// 对齐: PRD 3.1 (实例连接管理)
///
/// 流程:
/// 1. 校验名称和 URL 合法性
/// 2. 检查名称唯一性（编辑时排除自身）
/// 3. 构建 Instance（编辑模式下保留原 id）
/// 4. 编辑场景下检测 Gateway host 变化（见下）
/// 5. 执行连通性测试
/// 6. 若用户已确认 purgeLocal 且新 Gateway 在线且 host 确实变化：
///    删除本实例下所有 agents（CASCADE 清 conversations/messages/FTS）
/// 7. 保存实例（在线/离线）
/// 8. 通知 [IInstanceLifecycle] 触发后续编排（WebSocket 连接等）
///
/// **Gateway host 变化检测（编辑模式专用）**：
/// 当 `instanceId != null` 且新 URL 的 host 与旧值不同时，若本地有 agents 且
/// 调用方未给出 [GatewayChangeResolution]，抛出 [GatewayChangeRequiredException]。
/// UI 应弹窗询问用户保留旧数据 / 清除并切换 / 取消，得到选择后用
/// `onGatewayChange` 参数再次调用本方法。
///
/// 数据安全保证（purgeLocal 路径）：
/// - [IAgentRepo.deleteByInstanceId] 严格在 [IGatewayClient.testConnection]
///   **返回 true** 之后执行（不仅"未抛"）。新 Gateway 不可达时抛
///   [GatewayUnreachableException]，本地数据保持不变。
/// - 第二道护栏：purge 前再次比对 host，未变化则跳过 delete（防御调用方
///   传错 resolution）。
///
/// [instanceId] 为 null 时创建新实例，非 null 时编辑已有实例。
class SaveInstanceUseCase {
  final IInstanceRepo _instanceRepo;
  final IAgentRepo _agentRepo;
  final IGatewayClient _gatewayClient;
  final IInstanceLifecycle? _lifecycle;
  final ILogger? _logger;
  final Uuid _uuid;

  SaveInstanceUseCase({
    required IInstanceRepo instanceRepo,
    required IAgentRepo agentRepo,
    required IGatewayClient gatewayClient,
    IInstanceLifecycle? lifecycle,
    ILogger? logger,
    Uuid? uuid,
  }) : _instanceRepo = instanceRepo,
       _agentRepo = agentRepo,
       _gatewayClient = gatewayClient,
       _lifecycle = lifecycle,
       _logger = logger,
       _uuid = uuid ?? const Uuid();

  /// 规范化 host 用于比较：lowercase（`Uri.parse` 已做）+ 剥末尾点。
  ///
  /// 返回 null 表示 URL 不可解析或 host 为空 — 调用方应跳过比较。
  static String? _normalizeHost(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  }

  /// 保存实例（创建或更新）
  ///
  /// [onGatewayChange] 仅在编辑场景下使用：
  /// - `null`：默认行为。若检测到 host 变化且本地有 agents，会抛
  ///   [GatewayChangeRequiredException]，调用方应弹窗后用用户选择重试。
  /// - [GatewayChangeResolution.keepLocal]：跳过 host 检测，直接保存
  ///   （旧 agents 残留，新 Gateway 的 agents 与本地合并）。即使
  ///   testConnection 返回 false 也照常 save（离线只是网络抖动）。
  /// - [GatewayChangeResolution.purgeLocal]：跳过 host 检测；执行三重护栏：
  ///   testConnection 必须返回 true（否则抛 [GatewayUnreachableException]）+
  ///   host 必须确实变化（否则跳过 delete）+ delete 失败时抛
  ///   [PurgeFailedException]。
  Future<Instance> execute({
    required String name,
    required String gatewayUrl,
    required String token,
    String? instanceId,
    GatewayChangeResolution? onGatewayChange,
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

    // 4. Gateway host 变化检测（仅编辑模式 + 用户未给出 resolution）
    //
    //    用户已选择 keepLocal/purgeLocal 时跳过检测 — 避免在重试调用时
    //    重复抛异常造成 UI 死循环。
    if (isUpdate && onGatewayChange == null) {
      final oldHost = _normalizeHost(existing!.gatewayUrl);
      final newHost = _normalizeHost(trimmedUrl);
      if (oldHost != null && newHost != null && oldHost != newHost) {
        final localAgents = await _agentRepo.getByInstanceId(instanceId);
        if (localAgents.isNotEmpty) {
          throw GatewayChangeRequiredException(
            localAgentCount: localAgents.length,
          );
        }
      }
    }

    // 5. 连通性测试 — 必须在 purge 之前
    //    若新 Gateway 不可达且抛异常，本地数据不应已被清除。
    final isOnline = await _gatewayClient.testConnection(instance);

    // 6. purgeLocal — 数据安全护栏，按"先验证后销毁"原则三重校验：
    //    (a) testConnection 必须返回 true —— 新 Gateway 确认可达后才允许清空
    //        本地数据。返回 false（TCP 可达但握手失败 / DNS 解析延迟）一律
    //        拒绝 purge 并抛 [GatewayUnreachableException]，避免"为了切换到
    //        不可达 Gateway 而把本地 agents/conversations/messages 全部
    //        销毁"的不可逆数据丢失。
    //    (b) host 必须确实变化 —— 防御性二次比对，避免调用方传错 resolution
    //        时静默清空本实例下的所有 agents。
    //    (c) testConnection 自身抛异常时，await 已经把异常抛到调用方，
    //        purge 分支不会进入。
    if (isUpdate && onGatewayChange == GatewayChangeResolution.purgeLocal) {
      if (!isOnline) {
        throw const GatewayUnreachableException();
      }
      final oldHost = _normalizeHost(existing!.gatewayUrl);
      final newHost = _normalizeHost(trimmedUrl);
      final hostChanged =
          oldHost != null && newHost != null && oldHost != newHost;
      if (hostChanged) {
        try {
          await _agentRepo.deleteByInstanceId(instanceId);
          _logger?.info(
            '[SaveInstanceUseCase] Purged local agents for $instanceId '
            'before Gateway switch',
          );
        } catch (error, stackTrace) {
          _logger?.error(
            '[SaveInstanceUseCase] Purge failed for $instanceId: $error',
            stackTrace,
          );
          throw PurgeFailedException(message: '清除本地数据失败，请重试', cause: error);
        }
      } else {
        _logger?.info(
          '[SaveInstanceUseCase] Skipped purge for $instanceId '
          '— host unchanged (resolution=purgeLocal ignored)',
        );
      }
    }

    // 7. 保存（标记在线/离线）
    final saved = await _instanceRepo.save(
      instance.copyWith(
        healthStatus: isOnline ? HealthStatus.online : HealthStatus.offline,
        lastConnectedAt: isOnline
            ? DateTime.now().millisecondsSinceEpoch ~/ 1000
            : null,
      ),
    );
    // 8. 通知生命周期层（编排 WebSocket 连接），始终调用。
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
    } catch (error, stackTrace) {
      // 编排失败不应阻止 save 返回成功 — 实例已持久化。
      // 连接错误由 ConnectionOrchestrator 内部的自动重连机制自行处理。
      _logger?.error(
        '[SaveInstanceUseCase] Lifecycle callback failed for '
        '${saved.id}: $error',
        stackTrace,
      );
    }

    return saved;
  }
}
