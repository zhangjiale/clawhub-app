import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/app/di/providers.dart';

/// 刷新计数器 — 每次递增时对应会话的 chatMessagesProvider 重新拉取消息列表
final chatRefreshProvider = StateProvider.family<int, String>((ref, conversationId) => 0);

/// 会话消息列表 Provider
final chatMessagesProvider = FutureProvider.family<List<Message>, String>(
  (ref, conversationId) async {
    ref.watch(chatRefreshProvider(conversationId)); // 监听该会话的刷新信号
    return ref.watch(messageRepoProvider).getByConversation(conversationId);
  },
);
