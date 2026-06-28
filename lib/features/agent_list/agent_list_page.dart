import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/features/agent_list/providers/stats_providers.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/inline_stats.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/status_banner.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Agent 列表页 — V2 ComponentSpec §2.
///
/// Header: title 24px + InlineStats row (2/3 ● 5/8 ● 142 消息) + 2 actions
/// (search, settings). Body: instance groups → agent cards.
class AgentListPage extends ConsumerStatefulWidget {
  const AgentListPage({super.key});

  @override
  ConsumerState<AgentListPage> createState() => _AgentListPageState();
}

class _AgentListPageState extends ConsumerState<AgentListPage> {
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

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(agentListProvider);
    final statsAsync = ref.watch(statsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('虾Hub'),
        toolbarHeight: 56,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: XiaSpacing.s2),
            child: HeaderButton(
              tooltip: '搜索',
              onPressed: () =>
                  context.push(AppRoutes.searchWithParams(source: 'claws')),
              child: const Icon(Icons.search, size: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: XiaSpacing.s4),
            child: HeaderButton(
              tooltip: '设置',
              onPressed: () => context.push(AppRoutes.settings),
              child: const Icon(Icons.settings_outlined, size: 18),
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
  final int cardIndex;
  final bool isCollapsed;
  const _AgentCardItem({
    required this.agent,
    required this.isOnline,
    required this.cardIndex,
    required this.isCollapsed,
  });
}

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
        if (data.syncErrors.isNotEmpty)
          const StatusBanner(
            message: '无法获取最新列表',
            foregroundColor: XiaColors.yellow,
            backgroundColor: XiaColors.yellowMuted,
            icon: Icons.cloud_off,
          ),
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
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
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

    sections.add(_StatsItem(statsAsync));

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
        data: (stats) => InlineStats(
          items: [
            InlineStatItem(
              value: '${stats.activeInstances}',
              unit: '/${stats.totalInstances}',
              showStatusDot: true,
              isOnline: stats.activeInstances > 0,
            ),
            InlineStatItem(
              value: '${stats.onlineAgents}',
              unit: '/${stats.totalAgents} 在线',
            ),
            InlineStatItem(value: '${stats.totalMessages}', unit: '消息'),
          ],
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
        ),
    };
  }
}

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
    return PressFeedback(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH,
          vertical: XiaSpacing.s3,
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isInstanceOnline ? XiaColors.green : XiaColors.text4,
                shape: BoxShape.circle,
                boxShadow: isInstanceOnline ? XiaShadow.onlineGlow : null,
              ),
            ),
            const SizedBox(width: XiaSpacing.s2),
            Expanded(
              child: Text(
                header,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isInstanceOnline ? XiaColors.accent : XiaColors.text3,
                  fontWeight: FontWeight.w600,
                  fontSize: XiaTypography.sectionLabel,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Text(
              '$agentCount 只',
              style: const TextStyle(
                fontSize: 11,
                color: XiaColors.text3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: isCollapsed ? -0.25 : 0.0,
              duration: XiaMotion.durationFast,
              curve: XiaMotion.ease,
              child: const Icon(
                Icons.expand_more,
                size: 14,
                color: XiaColors.text4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
