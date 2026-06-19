import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/router/smart_back.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/widgets/profile_header.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Agent 详情页 — 展示 Agent 信息、统计、成就占位
///
/// 与 AgentConfigPage 共享同一个 AgentProfileViewModel。
/// 从 ChatRoomPage AppBar 或 AgentListPage 进入。
class AgentProfilePage extends ConsumerStatefulWidget {
  final String agentId;
  final String? source;

  const AgentProfilePage({super.key, required this.agentId, this.source});

  @override
  ConsumerState<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends ConsumerState<AgentProfilePage> {
  void _handleBack() {
    if (mounted) smartBack(context, source: widget.source);
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
          leading: XiaBackButton(onPressed: _handleBack),
          title: switch (state.detailLoadState) {
            LoadData(:final value) => Text(value.agent.displayName),
            _ => const Text('虾详情'),
          },
          actions: [
            if (state.detailLoadState is LoadData<AgentDetailData>)
              Padding(
                padding: const EdgeInsets.only(right: XiaSpacing.s2),
                child: HeaderButton(
                  icon: Icons.edit,
                  tooltip: '个性化配置',
                  onPressed: () {
                    context.push(
                      AppRoutes.agentConfigWithParams(widget.agentId),
                    );
                  },
                ),
              ),
          ],
        ),
        body: switch (state.detailLoadState) {
          LoadInProgress() => const LoadingSkeleton(count: 3),
          LoadError(:final error) => LoadErrorView(
            error: error,
            title: '无法加载虾信息',
            onRetry: () => vm.refresh(),
          ),
          LoadData(:final value) => ListView(
            children: [
              ProfileHeader(agent: value.agent, instance: value.instance),
              StatsGrid(messageCount: value.messageCount),
              const SizedBox(height: XiaSpacing.s3),
              // Future banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: XiaSpacing.s4,
                    vertical: XiaSpacing.s3,
                  ),
                  decoration: BoxDecoration(
                    color: XiaColors.accentMuted,
                    borderRadius: BorderRadius.circular(XiaRadius.sm),
                    border: Border.all(color: XiaColors.accent.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const Text('📊'),
                      const SizedBox(width: XiaSpacing.s2),
                      Expanded(
                        child: Text(
                          '完整成长数据将在 V1.2 上线后可用',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: XiaColors.text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: XiaSpacing.s5),
              // Achievements placeholder
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏆 成就',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: XiaSpacing.s4),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: XiaSpacing.s6,
                        ),
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
