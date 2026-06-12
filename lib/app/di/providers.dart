import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
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
import 'package:claw_hub/app/connection/connection_orchestrator.dart';

/// ============================================================
/// ClawHub 依赖注入容器 (Riverpod)
/// 对齐: 架构 vFinal 3.0 (系统逻辑架构), 8.2 (app/di/)
/// ============================================================

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

/// 真实 WebSocket Gateway 客户端（当前生产默认实现）。
///
/// 开发/调试时如需使用 Mock 数据，将 [gatewayClientProvider] 的返回值
/// 改回 `ref.watch(mockGatewayClientProvider)` 即可全局切回 Mock。
final wsGatewayClientProvider = Provider<WsGatewayClient>((ref) {
  // TODO: read locale from PlatformDispatcher.instance.locale when
  // i18n is implemented.
  final client = WsGatewayClient(locale: 'zh-CN');
  ref.onDispose(() => client.dispose());
  return client;
});

/// Gateway 防腐层接口（面向接口编程，方便 Mock ↔ 真实实现互换）
///
/// 当前指向 WsGatewayClient（生产环境）。
/// 开发/调试：改为 `return ref.watch(mockGatewayClientProvider);`
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(wsGatewayClientProvider);
});

// --- Network Monitoring ---

/// 网络连接监听器 — 面向 [IConnectivity] 接口，便于单测 mock。
///
/// 由 [ConnectionOrchestrator] 订阅，用于检测 WiFi ↔ 4G 切换，
/// 自动降级/恢复内网实例的连接状态。
final connectivityProvider = Provider<IConnectivity>(
  (ref) => ConnectivityAdapter(),
);

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
    connectivity: ref.watch(connectivityProvider),
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
  return DriftAgentRepo(ref.watch(databaseProvider));
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

final saveInstanceUseCaseProvider = Provider<SaveInstanceUseCase>((ref) {
  return SaveInstanceUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
    lifecycle: ref.watch(connectionOrchestratorProvider),
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
  );
});
