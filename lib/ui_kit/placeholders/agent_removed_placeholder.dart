// US-021 v1.1: Agent 已被 Gateway 删除（tombstoned）时的占位 Scaffold。
// US-021 v1.2 迁移：原 ChatRoom AC8 placeholder 文案/颜色已统一到本 widget，
// 三处调用点（ChatRoom / AgentProfilePage / AgentConfigPage）共用。
//
// onBack 是 required —— 三处调用点都显式传入 page-level back handler
// （保留 PopScope / smartBack 各自的 smartBack 契约）。如果未来新增调用点
// 忘传，编译期立刻报错，不再依赖运行时 ?? smartBack 兜底（dead code）。
//
// agentName 可空：init 中途失败的边界场景拿不到 agent 信息。
//
// 文案 hardcoded（CLAUDE.md 提到 localization WIP），v2 抽 l10n 资源。

import 'package:flutter/material.dart';
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

  /// 透传给调用方的 source hint（保留以备 v2 多入口接入）;
  /// 当前 onBack 已包含完整 back 逻辑，此字段暂未在 widget 内消费。
  final String? source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: onBack),
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
