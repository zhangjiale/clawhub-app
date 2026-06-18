import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:claw_hub/core/acl/ed25519_identity_provider.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_device_identity_provider.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:claw_hub/data/services/avatar_storage_service.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/iconnectivity.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/data/repositories/drift_conversation_repo.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/domain/usecases/save_instance.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/domain/usecases/delete_instance.dart';
import 'package:claw_hub/domain/usecases/outbox_processor.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/app/config/app_config.dart';
import 'package:claw_hub/app/config/platform_info.dart';

/// ============================================================
/// ClawHub 依赖注入容器 (Riverpod)
/// 对齐: 架构 vFinal 3.0 (系统逻辑架构), 8.2 (app/di/)
/// ============================================================

// --- Shared invalidation tokens (no circular deps) ---

/// Agent 同步完成信号 — [ConnectionOrchestrator] 在 _syncAgentsForInstance
/// 成功后递增，[agentListProvider] 通过 watch 此值自动 refresh UI。
final agentSyncTickerProvider = StateProvider<int>((ref) => 0);

/// Outbox 冲刷信号 — [OutboxProcessor.flushOutbox] 成功发送至少一条消息后递增。
///
/// 按 instanceId 隔离，避免实例 A 冲刷时触发实例 B/C/D 的 ChatViewModel
/// 不必要的 refreshOutbox() 调用（广播风暴）。
///
/// [ChatViewModel] 通过 listen 此值，在重连后自动刷新消息列表和 outbox 计数 —
/// 因为 OutboxProcessor 在后台冲刷时，ChatViewModel 自身的消息流不会感知
/// 这些状态变化（PENDING → SENT 是数据库直接更新，不经过 messageStream）。
final outboxFlushTickerProvider = StateProvider.family<int, String>(
  (ref, instanceId) => 0,
);

/// 配对信息 — instanceId → GatewayPairingInfo。
///
/// [ConnectionOrchestrator] 在收到 PAIRING_REQUIRED 时写入，
/// UI 层 watch 此 provider 以在实例卡片上展示审批指引。
final pairingInfoProvider = StateProvider<Map<String, GatewayPairingInfo>>(
  (ref) => {},
);

// --- Connection Initialization State ---

/// 连接编排器初始化状态。
///
/// [ConnectionOrchestrator.initialize] 完成后设置为 [AsyncValue.data]，
/// 失败时设置为 [AsyncValue.error]。UI 可 watch 此 provider 以在
/// 初始化失败时展示 SnackBar 或重试按钮。
final connectionInitStateProvider = StateProvider<AsyncValue<void>?>(
  (ref) => null,
);

// --- Gateway Client ---

/// Mock Gateway 客户端（开发/调试用，生产环境默认使用 [wsGatewayClientProvider]）
final mockGatewayClientProvider = Provider<MockGatewayClient>((ref) {
  final client = MockGatewayClient();
  ref.onDispose(() => client.dispose());
  return client;
});

/// 设备身份提供者 — Ed25519 密钥管理 + V3 签名。
///
/// 使用 [FlutterSecureStorage] 持久化密钥对。
/// 可通过 override 注入 fake 以进行单元测试。
final deviceIdentityProvider = Provider<IDeviceIdentityProvider>((ref) {
  return Ed25519IdentityProvider(
    secureStorage: const FlutterSecureStorage(),
    logger: ref.watch(loggerProvider),
  );
});

/// 真实 WebSocket Gateway 客户端（当前生产默认实现）。
///
/// 开发/调试时如需使用 Mock 数据，将 [gatewayClientProvider] 的返回值
/// 改回 `ref.watch(mockGatewayClientProvider)` 即可全局切回 Mock。
///
/// 自动检测运行平台（iOS / Android），选择对应的 [ClientIds] 枚举值，
/// 确保 Gateway 将虾Hub 识别为官方客户端。
final wsGatewayClientProvider = Provider<WsGatewayClient>((ref) {
  final os = platformOS(); // 'ios', 'android', 'macos', 'web', ...
  final clientId = ClientIds.forPlatform(os);
  final deviceFamily = os == 'ios' || os == 'android' ? 'phone' : 'desktop';

  // TODO: read locale from PlatformDispatcher.instance.locale when
  // i18n is implemented.
  // TODO: read modelIdentifier from device_info_plus for accurate
  // device reporting (e.g. "iPhone 15", "Pixel 8").
  final client = WsGatewayClient(
    identityProvider: ref.watch(deviceIdentityProvider),
    config: ConnectionConfig(
      locale: 'zh-CN',
      platform: os,
      clientId: clientId,
      deviceFamily: deviceFamily,
      clientDisplayName: '虾Hub',
      clientVersion: AppClientInfo.version,
    ),
  );
  ref.onDispose(() => client.dispose());
  return client;
});

/// Gateway 防腐层接口（面向接口编程，方便 Mock ↔ 真实实现互换）
///
/// 当前指向 MockGatewayClient（MVP / 开发阶段默认，可离线开发）。
/// 生产环境：改为 `return ref.watch(wsGatewayClientProvider);`
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(wsGatewayClientProvider);
});

// --- Network Monitoring ---

/// 日志接口 — 生产环境使用 [DebugPrintLogger]。
///
/// 测试可通过 override 注入 fake 以验证日志输出。
final loggerProvider = Provider<ILogger>((ref) => const DebugPrintLogger());

/// 网络连接监听器 — 面向 [IConnectivity] 接口，便于单测 mock。
///
/// 由 [ConnectionOrchestrator] 订阅，用于检测 WiFi ↔ 4G 切换，
/// 自动降级/恢复内网实例的连接状态。
final connectivityProvider = Provider<IConnectivity>(
  (ref) => ConnectivityAdapter(),
);

// --- Avatar Storage ---

/// 头像文件存储服务 — 面向 [IAvatarStorageService] 接口，便于单测 mock。
///
/// 头像文件存储在 `{appDocDir}/avatars/{agentLocalId}.jpg`。
/// [AgentProfileViewModel] 通过此接口保存/删除/检查头像文件。
final avatarStorageServiceProvider = Provider<IAvatarStorageService>((ref) {
  return AvatarStorageService();
});

// --- Connection Orchestrator ---

/// 全局连接编排器 — 管理所有 Gateway 实例的连接生命周期。
///
/// 生命周期与 App 一致；由 `_ConnectionInitializer.initState`（见 main.dart）
/// 在 widget 树首次 build 时调用 [ConnectionOrchestrator.initialize]，
/// 以确保 ProviderScope 已就绪后才启动自动连接和网络监听。
///
/// 同时作为 [IInstanceLifecycle] 注入到 [SaveInstanceUseCase]，
/// 使 UseCase 在持久化完成后自动触发 WebSocket 连接编排，
/// UI 层无需直接依赖编排器。
final connectionOrchestratorProvider = Provider<ConnectionOrchestrator>((ref) {
  final orchestrator = ConnectionOrchestrator(
    gatewayClient: ref.watch(gatewayClientProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    connectivity: ref.watch(connectivityProvider),
    onAgentsSynced: () => ref.read(agentSyncTickerProvider.notifier).state++,
    onPairingInfo: (instanceId, info) {
      final notifier = ref.read(pairingInfoProvider.notifier);
      final newMap = Map<String, GatewayPairingInfo>.from(notifier.state);
      if (info == null) {
        newMap.remove(instanceId);
      } else {
        newMap[instanceId] = info;
      }
      notifier.state = newMap;
    },
    onInstanceConnected: (instanceId) {
      // 在 agent sync 完成后触发 — 冲刷待发送队列（US-015）。fire-and-forget。
      // 外层 try-catch：集成测试可能只 override 部分 provider，未 override
      // messageRepo/databaseProvider 时 outboxProcessorProvider 解析会抛
      // UnimplementedError — 静默即可，不影响业务流程。
      try {
        ref
            .read(outboxProcessorProvider)
            .flushOutbox(instanceId)
            .then((sent) {
              if (sent > 0) {
                // 通知 ChatViewModel 刷新 outbox count（监听 outboxFlushTickerProvider）
                ref
                    .read(outboxFlushTickerProvider(instanceId).notifier)
                    .state++;
              }
            })
            .catchError((Object e, StackTrace st) {
              // loggerProvider 有 DebugPrintLogger 默认实现，解析不会抛。
              ref
                  .read(loggerProvider)
                  .error(
                    '[OutboxProcessor] Flush failed for $instanceId: $e',
                    st,
                  );
            });
      } catch (_) {
        // iron-law-allow: Law8 -- outboxProcessorProvider unavailable in test env with partial overrides
      }
    },
  );
  ref.onDispose(() => orchestrator.dispose());
  return orchestrator;
});

// --- Database ---

/// Drift/SQLite 数据库实例。
///
/// 默认实现会创建磁盘上的数据库，并在 provider 被 dispose 时自动 close。
/// [main()] 通过 `overrideWith` 提前创建好实例并注入，同样会注册 dispose 钩子
/// 以保证应用退出时数据库被正确关闭。测试侧可用内存 DB 替换。
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden in main() via '
    'databaseProvider.overrideWith(...) so the AppDatabase lifecycle '
    '(creation + close) is owned by a single place.',
  );
});

// --- Repositories ---

final instanceRepoProvider = Provider<IInstanceRepo>((ref) {
  return DriftInstanceRepo(ref.watch(databaseProvider));
});

final agentRepoProvider = Provider<IAgentRepo>((ref) {
  return DriftAgentRepo(
    ref.watch(databaseProvider),
    avatarStorage: ref.watch(avatarStorageServiceProvider),
  );
});

final messageRepoProvider = Provider<IMessageRepo>((ref) {
  return DriftMessageRepo(ref.watch(databaseProvider));
});

final conversationRepoProvider = Provider<IConversationRepo>((ref) {
  return DriftConversationRepo(ref.watch(databaseProvider));
});

// --- Use Cases ---

final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  return SendMessageUseCase(
    messageRepo: ref.watch(messageRepoProvider),
    conversationRepo: ref.watch(conversationRepoProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
  );
});

/// OutboxProcessor — 离线消息队列冲刷处理器（US-015）。
///
/// 在 [ConnectionOrchestrator] 检测到实例重连成功且 agent 同步完成后触发，
/// 按 [Message.logicalClock] 升序冲刷 PENDING + FAILED 消息。
final outboxProcessorProvider = Provider<OutboxProcessor>((ref) {
  return OutboxProcessor(
    messageRepo: ref.watch(messageRepoProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    sendMessageUseCase: ref.watch(sendMessageUseCaseProvider),
    logger: ref.watch(loggerProvider),
  );
});

final saveInstanceUseCaseProvider = Provider<SaveInstanceUseCase>((ref) {
  return SaveInstanceUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
    lifecycle: ref.watch(connectionOrchestratorProvider),
    logger: ref.watch(loggerProvider),
  );
});

final deleteInstanceUseCaseProvider = Provider<DeleteInstanceUseCase>((ref) {
  return DeleteInstanceUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    lifecycle: ref.watch(connectionOrchestratorProvider),
  );
});

final syncAgentsUseCaseProvider = Provider<SyncAgentsUseCase>((ref) {
  return SyncAgentsUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
    logger: ref.watch(loggerProvider),
  );
});
