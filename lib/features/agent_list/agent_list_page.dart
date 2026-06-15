import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/features/agent_list/providers/stats_providers.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/features/agent_list/widgets/stats_bar.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/status_banner.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Agent 列表页 — 按实例分组展示所有 Agent，支持折叠分组、在线状态。
///
/// 设计稿对齐：无搜索框，仅保留设置按钮。
class AgentListPage extends ConsumerStatefulWidget {
  const AgentListPage({super.key});

  @override
  ConsumerState<AgentListPage> createState() => _AgentListPageState();
}

// ---------------------------------------------------------------------------
// State — local UI-only state (collapse) per Law 5 exception
// ---------------------------------------------------------------------------

class _AgentListPageState extends ConsumerState<AgentListPage> {
  /// 已折叠的分组 header（按 instanceName 标识）
  final Set<String> _collapsedGroups = {};

  void _toggleGroup(String key) {
    setState(() {
      if (_collapsedGroups.contains(key)) {
        _collapsedGroups.remove(key);
      } else {
        _collapsedGroups.add(key);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(agentListProvider);
    final statsAsync = ref.watch(statsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('虾Hub'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: XiaSpacing.s2),
            child: HeaderButton(
              icon: Icons.dns_outlined,
              tooltip: '实例管理',
              onPressed: () => context.go(AppRoutes.instances),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: XiaSpacing.s2),
            child: HeaderButton(
              icon: Icons.settings_outlined,
              tooltip: '设置',
              onPressed: () => context.push(AppRoutes.settings),
            ),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const LoadingSkeleton(count: 3),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(XiaSpacing.s7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: XiaSpacing.s3),
                Text('Failed to load agents', style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        data: (data) => _buildDataView(data, statsAsync),
      ),
    );
  }

  /// Route to the correct content view based on data.
  Widget _buildDataView(AgentListData data, AsyncValue<StatsData> statsAsync) {
    if (data.agents.isEmpty) {
      final hasSyncErrors = data.syncErrors.isNotEmpty;
      return Column(
        children: [
          if (hasSyncErrors)
            const StatusBanner(
              message: '无法获取最新列表',
              foregroundColor: XiaColors.yellow,
              backgroundColor: XiaColors.yellowMuted,
              icon: Icons.cloud_off,
            ),
          Expanded(
            child: hasSyncErrors
                ? const EmptyState(
                    icon: Icon(Icons.cloud_off),
                    title: '无法获取 Agent 列表',
                    subtitle: '请检查实例连接后下拉刷新重试',
                  )
                : const EmptyState(
                    icon: Text('🦐', style: TextStyle(fontSize: 48)),
                    title: '还没有虾',
                    subtitle: '添加一个 OpenClaw 实例\n开始养虾之旅',
                  ),
          ),
        ],
      );
    }

    return _AgentListContent(
      data: data,
      agents: data.agents,
      statsAsync: statsAsync,
      collapsedGroups: _collapsedGroups,
      onToggleGroup: _toggleGroup,
    );
  }
}

// ---------------------------------------------------------------------------
// Lightweight list-item descriptors (Law 11 — true lazy building)
// ---------------------------------------------------------------------------

sealed class _AgentListItem {
  const _AgentListItem();
}

final class _StatsItem extends _AgentListItem {
  final AsyncValue<StatsData> statsAsync;
  const _StatsItem(this.statsAsync);
}

final class _GroupHeaderItem extends _AgentListItem {
  final String header;
  final int agentCount;
  final bool isInstanceOnline;
  final bool isCollapsed;
  final VoidCallback onToggle;
  const _GroupHeaderItem({
    required this.header,
    required this.agentCount,
    required this.isInstanceOnline,
    required this.isCollapsed,
    required this.onToggle,
  });
}

final class _AgentCardItem extends _AgentListItem {
  final Agent agent;
  final bool isOnline;
  final int cardIndex; // B5: staggered enter delay index
  final bool isCollapsed; // C3: for AnimatedSize collapse
  const _AgentCardItem({
    required this.agent,
    required this.isOnline,
    required this.cardIndex,
    required this.isCollapsed,
  });
}

// ---------------------------------------------------------------------------
// Content widget — owns the list rendering
// ---------------------------------------------------------------------------

class _AgentListContent extends StatelessWidget {
  final AgentListData data;
  final List<Agent> agents;
  final AsyncValue<StatsData> statsAsync;
  final Set<String> collapsedGroups;
  final void Function(String key) onToggleGroup;

  const _AgentListContent({
    required this.data,
    required this.agents,
    required this.statsAsync,
    required this.collapsedGroups,
    required this.onToggleGroup,
  });

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections();

    return Column(
      children: [
        // Stale-data banner
        if (data.syncErrors.isNotEmpty)
          const StatusBanner(
            message: '无法获取最新列表',
            foregroundColor: XiaColors.yellow,
            backgroundColor: XiaColors.yellowMuted,
            icon: Icons.cloud_off,
          ),
        // List fills remaining space and supports pull-to-refresh.
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(agentListProvider);
                  ref.invalidate(statsProvider);
                  await ref.read(agentListProvider.future);
                  await ref.read(statsProvider.future);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    return _buildItem(context, sections[index]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<_AgentListItem> _buildSections() {
    final sections = <_AgentListItem>[];

    // 1. Stats bar
    sections.add(_StatsItem(statsAsync));

    // 2. Group by instance name
    final groups = <String?, List<Agent>>{};
    for (final agent in agents) {
      final name = data.instanceNames[agent.instanceId];
      groups.putIfAbsent(name, () => []).add(agent);
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });

    for (final key in sortedKeys) {
      final groupAgents = groups[key]!;
      final header = key ?? 'Unknown Instance';
      final firstAgent = groupAgents.first;
      final instanceStatus =
          data.instanceStatuses[firstAgent.instanceId] ?? HealthStatus.unknown;
      final isCollapsed = collapsedGroups.contains(key);

      sections.add(
        _GroupHeaderItem(
          header: header,
          agentCount: groupAgents.length,
          isInstanceOnline: instanceStatus.isConnectable,
          isCollapsed: isCollapsed,
          onToggle: key == null ? () {} : () => onToggleGroup(key),
        ),
      );

      // Agent cards (C3: always included, collapsed via AnimatedSize)
      var cardIndex = 0;
      for (final agent in groupAgents) {
        final agentOnline =
            data.instanceStatuses[agent.instanceId]?.isConnectable ?? false;
        sections.add(
          _AgentCardItem(
            agent: agent,
            isOnline: agentOnline,
            cardIndex: cardIndex,
            isCollapsed: isCollapsed,
          ),
        );
        cardIndex++;
      }
    }

    return sections;
  }

  Widget _buildItem(BuildContext context, _AgentListItem item) {
    return switch (item) {
      _StatsItem(:final statsAsync) => statsAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (stats) => StatsBar(
          activeInstances: stats.activeInstances,
          totalInstances: stats.totalInstances,
          onlineAgents: stats.onlineAgents,
          totalAgents: stats.totalAgents,
          totalMessages: stats.totalMessages,
        ),
      ),
      _GroupHeaderItem(
        :final header,
        :final agentCount,
        :final isInstanceOnline,
        :final isCollapsed,
        :final onToggle,
      ) =>
        _GroupHeaderTile(
          header: header,
          agentCount: agentCount,
          isInstanceOnline: isInstanceOnline,
          isCollapsed: isCollapsed,
          onToggle: onToggle,
        ),
      _AgentCardItem(
        :final agent,
        :final isOnline,
        :final cardIndex,
        :final isCollapsed,
      ) =>
        AnimatedSize(
          duration: XiaMotion.durationMid,
          curve: XiaMotion.ease,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: isCollapsed
              ? const SizedBox(width: double.infinity, height: 0)
              : AgentCard(
                  agent: agent,
                  isOnline: isOnline,
                  lastActiveAt: null,
                  index: cardIndex,
                  onTap: () {
                    final router = GoRouter.of(context);
                    router.push(
                      AppRoutes.chatWithParams(
                        agent.localId,
                        agent.instanceId,
                        source: 'claws',
                      ),
                    );
                  },
                ),
        ), // AnimatedSize
    };
  }
}

// ---------------------------------------------------------------------------
// Group header tile (extracted — Law 10 composition)
// ---------------------------------------------------------------------------

class _GroupHeaderTile extends StatelessWidget {
  final String header;
  final int agentCount;
  final bool isInstanceOnline;
  final bool isCollapsed;
  final VoidCallback onToggle;

  const _GroupHeaderTile({
    required this.header,
    required this.agentCount,
    required this.isInstanceOnline,
    required this.isCollapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        XiaSpacing.s4,
        XiaSpacing.s3,
        XiaSpacing.s4,
        XiaSpacing.s1,
      ),
      child: PressFeedback(
        onTap: onToggle,
        builder: (child, isPressed) => AnimatedOpacity(
          opacity: isPressed ? 0.5 : 1.0,
          duration: XiaMotion.durationFast,
          curve: XiaMotion.ease,
          child: child,
        ),
        child: Row(
          children: [
            // Online status dot for the instance
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isInstanceOnline ? XiaColors.green : XiaColors.text4,
                shape: BoxShape.circle,
                boxShadow: isInstanceOnline ? XiaShadow.onlineGlow : null,
              ),
            ),
            const SizedBox(width: XiaSpacing.s2),
            // Instance name with emoji
            Expanded(
              child: Text(
                '🖥️ $header',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isInstanceOnline ? XiaColors.accent : XiaColors.text3,
                  fontWeight: FontWeight.w600,
                  fontSize: XiaTypography.sectionLabel,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            // Agent count badge with "只虾"
            Text(
              '$agentCount 只虾',
              style: theme.textTheme.labelSmall?.copyWith(
                color: XiaColors.text4,
              ),
            ),
            const SizedBox(width: XiaSpacing.s1),
            // Collapse/expand icon
            AnimatedRotation(
              turns: isCollapsed ? -0.25 : 0.0,
              duration: XiaMotion.durationFast,
              curve: XiaMotion.ease,
              child: const Icon(
                Icons.expand_more,
                size: 20,
                color: XiaColors.text4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
