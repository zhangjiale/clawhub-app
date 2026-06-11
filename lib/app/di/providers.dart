import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/data/repositories/drift_conversation_repo.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/domain/usecases/save_instance.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';

/// ============================================================
/// ClawHub 依赖注入容器 (Riverpod)
/// 对齐: 架构 vFinal 3.0 (系统逻辑架构), 8.2 (app/di/)
/// ============================================================

// --- Gateway Client ---

/// Mock Gateway 客户端（MVP 阶段使用，后期替换为真实实现）
final mockGatewayClientProvider = Provider<MockGatewayClient>((ref) {
  final client = MockGatewayClient();
  ref.onDispose(() => client.dispose());
  return client;
});

/// Gateway 防腐层接口（面向接口编程，方便后期替换）
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(mockGatewayClientProvider);
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
  );
});

final syncAgentsUseCaseProvider = Provider<SyncAgentsUseCase>((ref) {
  return SyncAgentsUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
  );
});
