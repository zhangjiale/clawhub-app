import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/widgets/profile_header.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

/// Agent 详情页 — 展示 Agent 信息、统计、成就占位
///
/// 与 AgentConfigPage 共享同一个 AgentProfileViewModel。
/// 从 ChatRoomPage AppBar 或 AgentListPage 进入。
class AgentProfilePage extends ConsumerStatefulWidget {
  final String agentId;
  final String? source;

  const AgentProfilePage({
    super.key,
    required this.agentId,
    this.source,
  });

  @override
  ConsumerState<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends ConsumerState<AgentProfilePage> {
  /// Smart back navigation (matches ChatRoomPage pattern).
  void _handleBack() {
    if (mounted && context.canPop()) {
      context.pop();
    } else if (mounted) {
      final source = widget.source;
      if (source == 'messages') {
        context.go(AppRoutes.messages);
      } else {
        context.go(AppRoutes.claws);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          title: switch (state.detailLoadState) {
            LoadData(:final value) => Text(value.agent.displayName),
            _ => const Text('虾详情'),
          },
          actions: [
            if (state.detailLoadState is LoadData<AgentDetailData>)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '个性化配置',
                onPressed: () {
                  context.push(
                    AppRoutes.agentConfigWithParams(widget.agentId),
                  );
                },
              ),
          ],
        ),
        body: switch (state.detailLoadState) {
          LoadInProgress() => const LoadingSkeleton(count: 3),
          LoadError(:final error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '无法加载虾信息',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => vm.refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          LoadData(:final value) => ListView(
              children: [
                ProfileHeader(agent: value.agent, instance: value.instance),
                StatsGrid(messageCount: value.messageCount),
                const SizedBox(height: 12),
                // Future banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.primary.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('📊'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '完整成长数据将在 V1.2 上线后可用',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Achievements placeholder
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🏆 成就',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            '更多数据积累后解锁成就系统…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        },
      ),
    );
  }
}
