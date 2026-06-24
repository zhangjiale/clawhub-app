// US-021 v1.1: Agent 已被 Gateway 删除（tombstoned）时的占位 Scaffold。
// 复用 ChatRoom AC8 placeholder 文案/颜色（chat_room_page.dart:146-175）。
// 三处使用：ChatRoom（已存在，迁移目标）、AgentProfilePage、AgentConfigPage。
//
// onBack 走 smartBack(context, source: source) 而非 Navigator.pop，保证
// 智能返回栈契约（US-011）：从不同 tab 进入的回退到正确源。
//
// agentName 可空：init 中途失败的边界场景拿不到 agent 信息。
//
// 文案 hardcoded（CLAUDE.md 提到 localization WIP），v2 抽 l10n 资源。

import 'package:flutter/material.dart';
import 'package:claw_hub/app/router/smart_back.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

class AgentRemovedPlaceholder extends StatelessWidget {
  const AgentRemovedPlaceholder({
    super.key,
    required this.onBack,
    this.agentName,
    this.source,
  });

  final VoidCallback onBack;
  final String? agentName;
  final String? source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(
          onPressed: () => smartBack(context, source: source),
        ),
        title: const Text('虾已移除'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, size: 48, color: XiaColors.red),
              const SizedBox(height: 16),
              const Text('该 Agent 已从 Gateway 移除', textAlign: TextAlign.center),
              if (agentName != null) ...[
                const SizedBox(height: 8),
                Text(
                  agentName!,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
