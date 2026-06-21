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
import 'package:claw_hub/ui_kit/detail_tabs.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Agent 详情页 — V2 §5.
///
/// V2: Adds DetailTabs switcher (成长面板 / 成就).
/// 成长面板 tab: profile header + stats grid + timeline + actions.
/// 成就 tab: achievement list.
enum _ProfileTab { growth, achievements }

class AgentProfilePage extends ConsumerStatefulWidget {
  final String agentId;
  final String? source;

  const AgentProfilePage({super.key, required this.agentId, this.source});

  @override
  ConsumerState<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends ConsumerState<AgentProfilePage> {
  _ProfileTab _currentTab = _ProfileTab.growth;

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
              toolbarHeight: 52, // V2: 52px compact chat-header-like
              title: switch (state.detailLoadState) {
                LoadData(:final value) => Text(value.agent.displayName),
                _ => const Text('虾详情'),
              },
              actions: [
                if (state.detailLoadState is LoadData<AgentDetailData>)
                  Padding(
                    padding: const EdgeInsets.only(right: XiaSpacing.s4),
                    child: HeaderButton(
                      size: 32,
                      tooltip: '编辑',
                      onPressed: () {
                        context.push(
                          AppRoutes.agentConfigWithParams(widget.agentId),
                        );
                      },
                      child: const Icon(Icons.edit_outlined, size: 16),
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
              LoadData(:final value) => Column(
                children: [
                  // V2: detail tab switcher
                  DetailTabs(
                    tabs: const ['成长面板', '成就'],
                    selectedIndex: _currentTab.index,
                    onTabSelected: (i) =>
                        setState(() => _currentTab = _ProfileTab.values[i]),
                  ),
                  Expanded(
                    child: switch (_currentTab) {
                      _ProfileTab.growth => _buildGrowthTab(value),
                      _ProfileTab.achievements => AchievementList(
                        achievements: value.achievements,
                      ),
                    },
                  ),
                ],
              ),
            },
          ),
          if (state.newUnlocks.isNotEmpty)
            MilestoneCelebrationOverlay(
              achievement: state.newUnlocks.first,
              onDismiss: vm.clearNewUnlocks,
            ),
        ],
      ),
    );
  }

  /// V2 成长面板 tab — header + stats grid + timeline + actions.
  Widget _buildGrowthTab(AgentDetailData value) {
    return ListView(
      padding: const EdgeInsets.only(bottom: XiaSpacing.s7),
      children: [
        ProfileHeader(agent: value.agent, instance: value.instance),
        StatsGrid(stats: value.stats, fallbackMessageCount: value.messageCount),
        const SizedBox(height: XiaSpacing.s5),
      ],
    );
  }
}
