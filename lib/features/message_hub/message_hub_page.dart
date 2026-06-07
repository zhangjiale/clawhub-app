import 'package:flutter/material.dart';

/// 消息页 (P0 MVP)
/// Stub — 将在 Phase 6 完整实现
class MessageHubPage extends StatelessWidget {
  const MessageHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: const Center(child: Text('No messages yet')),
    );
  }
}
