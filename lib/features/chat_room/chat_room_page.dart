import 'package:flutter/material.dart';

/// 聊天页 (P0 MVP)
/// Stub — 将在 Phase 5 完整实现
class ChatRoomPage extends StatelessWidget {
  final String agentId;
  final String instanceId;
  final String? source;

  const ChatRoomPage({
    super.key,
    required this.agentId,
    required this.instanceId,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: const Center(child: Text('Chat room')),
    );
  }
}
