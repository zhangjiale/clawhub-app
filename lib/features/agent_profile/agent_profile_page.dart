import 'package:flutter/material.dart';

/// Agent 详情页 (P0 MVP)
/// Stub — 将在 Phase 7 完整实现
class AgentProfilePage extends StatelessWidget {
  final String agentId;

  const AgentProfilePage({super.key, required this.agentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent Profile')),
      body: const Center(child: Text('Agent details')),
    );
  }
}
