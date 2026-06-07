import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/domain/usecases/add_instance.dart';

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

// --- Repositories ---

final instanceRepoProvider = Provider<IInstanceRepo>((ref) {
  return InMemoryInstanceRepo();
});

final agentRepoProvider = Provider<IAgentRepo>((ref) {
  return InMemoryAgentRepo();
});

final messageRepoProvider = Provider<IMessageRepo>((ref) {
  return InMemoryMessageRepo();
});

final conversationRepoProvider = Provider<IConversationRepo>((ref) {
  return InMemoryConversationRepo();
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

final addInstanceUseCaseProvider = Provider<AddInstanceUseCase>((ref) {
  return AddInstanceUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
  );
});
