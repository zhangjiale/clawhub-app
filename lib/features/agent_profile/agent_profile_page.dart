import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/router/smart_back.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/settings/providers/clear_cache_guard.dart';
import 'package:claw_hub/features/agent_profile/widgets/profile_header.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';
import 'package:claw_hub/features/agent_profile/widgets/activity_timeline.dart';
import 'package:claw_hub/features/agent_profile/widgets/achievement_list.dart';
import 'package:claw_hub/features/agent_profile/widgets/empty_growth_view.dart';
import 'package:claw_hub/features/agent_profile/widgets/milestone_celebration.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/detail_tabs.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
import 'package:claw_hub/ui_kit/placeholders/agent_removed_placeholder.dart';
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
    // Major #1 修复: clearAll 进行中 family builder 抛 [ClearedDuringClearError]
    // (由 clearCacheActionProvider 设置的 guard 触发)。捕获取消本次导航，
    // 提示用户并回到上一个 tab。
    final AgentProfileState state;
    try {
      state = ref.watch(agentProfileViewModelProvider(widget.agentId));
    } on ClearedDuringClearError {
      handleClearedDuringClear(context, source: widget.source);
      return const Scaffold(body: SizedBox.shrink());
    }
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final theme = Theme.of(context);

    // US-021 v1.1: tombstoned agent 显示占位页（与 ChatRoom AC8 同模式）。
    // Step 6: 直接读 vm.agent.isRemoved —— 不再依赖 state.isAgentRemoved
    // 字段。看似绕过 ref.watch，但 _setAgent 调用会同步 bump
    // state.contentRevision 触发本 build 重建，getter 拿到的是最新 _agent。
    // data 可空 —— init 中途失败时 detailLoadState 仍为 LoadInProgress /
    // LoadError，agentName=null，placeholder 仍渲染「已移除」核心信息。
    if (vm.agent.isTombstoned) {
      final data = switch (state.detailLoadState) {
        LoadData<AgentDetailData>(:final value) => value,
        _ => null,
      };
      return AgentRemovedPlaceholder(
        agentName: data?.agent.displayName,
        source: widget.source,
        onBack: _handleBack,
      );
    }

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
  ///
  /// US-019 AC-3: 当 messageCount == 0 时（新装 App / 清空虾对话后），
  /// 用 [EmptyGrowthView] 引导用户去对话，替代显示一排 `--` 的统计网格。
  /// 仅依据 messageCount（独立 COUNT 查询，权威值）—— stats 是派生缓存，
  /// 可能因聚合失败而 null，但消息数为 0 时统计天然为空，单条件足够。
  Widget _buildGrowthTab(AgentDetailData value) {
    if (value.messageCount == 0) {
      return Column(
        children: [
          ProfileHeader(agent: value.agent, instance: value.instance),
          Expanded(
            child: EmptyGrowthView(
              onStartChat: () {
                context.push(
                  AppRoutes.chatWithParams(
                    value.agent.localId,
                    value.agent.instanceId,
                    source: widget.source,
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: XiaSpacing.s7),
      children: [
        ProfileHeader(agent: value.agent, instance: value.instance),
        StatsGrid(stats: value.stats, fallbackMessageCount: value.messageCount),
        const SizedBox(height: XiaSpacing.s4),
        ActivityTimeline(activities: value.dailyActivity),
        const SizedBox(height: XiaSpacing.s5),
      ],
    );
  }
}
