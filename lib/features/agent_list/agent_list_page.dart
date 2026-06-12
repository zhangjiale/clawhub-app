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
import 'package:claw_hub/app/theme/tokens.dart';

/// Agent 列表页 (P0 MVP Phase 4)
/// 按实例分组展示所有 Agent，支持搜索过滤、折叠分组、在线状态
class AgentListPage extends ConsumerStatefulWidget {
  const AgentListPage({super.key});

  @override
  ConsumerState<AgentListPage> createState() => _AgentListPageState();
}

// ---------------------------------------------------------------------------
// State — local UI-only state (search, collapse) per Law 5 exception
// ---------------------------------------------------------------------------

class _AgentListPageState extends ConsumerState<AgentListPage> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _query = '';

  /// 已折叠的分组 header（按 instanceName 标识）
  final Set<String> _collapsedGroups = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

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
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search agents...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('🦐 ClawHub'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const LoadingSkeleton(count: 3),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('Failed to load agents',
                    style: theme.textTheme.bodyLarge),
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
    final filtered = _filter(data.agents, _query);
    if (filtered.isEmpty && _query.isEmpty) {
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
            child: EmptyState(
              icon: hasSyncErrors ? Icons.cloud_off : Icons.pets,
              title: hasSyncErrors ? '无法获取 Agent 列表' : 'No Agents',
              subtitle: hasSyncErrors
                  ? '请检查实例连接后下拉刷新重试'
                  : 'Connect to an OpenClaw instance to see agents',
            ),
          ),
        ],
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No agents match "$_query"',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    return _AgentListContent(
      data: data,
      filteredAgents: filtered,
      statsAsync: statsAsync,
      collapsedGroups: _collapsedGroups,
      onToggleGroup: _toggleGroup,
    );
  }

  static List<Agent> _filter(List<Agent> agents, String query) {
    if (query.isEmpty) return agents;
    final lower = query.toLowerCase();
    return agents.where((a) {
      return a.displayName.toLowerCase().contains(lower) ||
          (a.description?.toLowerCase().contains(lower) ?? false);
    }).toList();
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
  const _AgentCardItem({
    required this.agent,
    required this.isOnline,
  });
}

// ---------------------------------------------------------------------------
// Content widget — owns the list rendering
// ---------------------------------------------------------------------------

class _AgentListContent extends StatelessWidget {
  final AgentListData data;
  final List<Agent> filteredAgents;
  final AsyncValue<StatsData> statsAsync;
  final Set<String> collapsedGroups;
  final void Function(String key) onToggleGroup;

  const _AgentListContent({
    required this.data,
    required this.filteredAgents,
    required this.statsAsync,
    required this.collapsedGroups,
    required this.onToggleGroup,
  });

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections();

    return Column(
      children: [
        // Stale-data banner: shown when one or more Gateways
        // failed to sync and the list is showing cached data (US-004 AC4).
        if (data.syncErrors.isNotEmpty)
          const StatusBanner(
            message: '无法获取最新列表',
            foregroundColor: XiaColors.yellow,
            backgroundColor: XiaColors.yellowMuted,
            icon: Icons.cloud_off,
          ),
        // List fills remaining space and supports pull-to-refresh.
        Expanded(
          child: _buildRefreshableList(context, sections),
        ),
      ],
    );
  }

  /// Build the flat list of section descriptors.
  ///
  /// Groups agents by instance name, one [_StatsItem] for the stats bar,
  /// one [_GroupHeaderItem] per group, and one [_AgentCardItem] per agent
  /// (skipped when its group is collapsed).
  List<_AgentListItem> _buildSections() {
    final sections = <_AgentListItem>[];

    // 1. Stats bar
    sections.add(_StatsItem(statsAsync));

    // 2. Group by instance name
    final groups = <String?, List<Agent>>{};
    for (final agent in filteredAgents) {
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

      // Agent cards (hidden when collapsed)
      if (!isCollapsed) {
        for (final agent in groupAgents) {
          final agentOnline =
              data.instanceStatuses[agent.instanceId]?.isConnectable ?? false;
          sections.add(
            _AgentCardItem(
              agent: agent,
              isOnline: agentOnline,
            ),
          );
        }
      }
    }

    return sections;
  }

  Widget _buildRefreshableList(
    BuildContext context,
    List<_AgentListItem> sections,
  ) {
    // RefreshIndicator requires a Riverpod ref — grab it via Consumer
    return Consumer(
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
    );
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
      _AgentCardItem(:final agent, :final isOnline) =>
        AgentCard(
          agent: agent,
          isOnline: isOnline,
          lastActiveAt: null, // MVP: per-agent stats not yet available (US-019)
          onTap: () {
            // Navigate via GoRouter
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            // Online status dot for the instance
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isInstanceOnline
                    ? AppColors.statusOnline
                    : AppColors.statusOffline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            // Instance name with emoji
            Expanded(
              child: Text(
                '🖥️ $header',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isInstanceOnline
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Agent count badge with "只虾"
            Text(
              '$agentCount 只虾',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 4),
            // Collapse/expand icon
            AnimatedRotation(
              turns: isCollapsed ? -0.25 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
