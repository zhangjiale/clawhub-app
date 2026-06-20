import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/router/smart_back.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/widgets/profile_header.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';
import 'package:claw_hub/features/agent_profile/widgets/achievement_list.dart';
import 'package:claw_hub/features/agent_profile/widgets/milestone_celebration.dart';
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
      child: Stack(
        children: [
          Scaffold(
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
                  StatsGrid(
                    stats: value.stats,
                    fallbackMessageCount: value.messageCount,
                  ),
                  const SizedBox(height: XiaSpacing.s5),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: XiaSpacing.s6,
                    ),
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
                        AchievementList(achievements: value.achievements),
                      ],
                    ),
                  ),
                  const SizedBox(height: XiaSpacing.s8),
                ],
              ),
            },
          ),
          // Celebration overlay — shown when new achievements are unlocked
          if (state.newUnlocks.isNotEmpty)
            MilestoneCelebrationOverlay(
              achievement: state.newUnlocks.first,
              onDismiss: vm.clearNewUnlocks,
            ),
        ],
      ),
    );
  }
}
