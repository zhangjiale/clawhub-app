import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/features/agent_list/providers/stats_providers.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/features/agent_list/widgets/stats_bar.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

/// Agent 列表页 (P0 MVP Phase 4)
/// 按实例分组展示所有 Agent，支持搜索过滤、折叠分组、在线状态
class AgentListPage extends ConsumerStatefulWidget {
  const AgentListPage({super.key});

  @override
  ConsumerState<AgentListPage> createState() => _AgentListPageState();
}

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

  List<Agent> _filter(List<Agent> agents) {
    if (_query.isEmpty) return agents;
    final lower = _query.toLowerCase();
    return agents.where((a) {
      return a.displayName.toLowerCase().contains(lower) ||
          (a.description?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

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
            : const Text('Claws'),
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
        data: (data) {
          final filtered = _filter(data.agents);
          if (filtered.isEmpty && _query.isEmpty) {
            return const EmptyState(
              icon: Icons.pets,
              title: 'No Agents',
              subtitle: 'Connect to an OpenClaw instance to see agents',
            );
          }
          if (filtered.isEmpty) {
            return Center(
              child: Text(
                'No agents match "$_query"',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            );
          }

          // Group by instanceId
          final groups = <String?, List<Agent>>{};
          for (final agent in filtered) {
            final name = data.instanceNames[agent.instanceId];
            groups.putIfAbsent(name, () => []).add(agent);
          }

          final sortedKeys = groups.keys.toList()
            ..sort((a, b) {
              if (a == null) return 1;
              if (b == null) return -1;
              return a.compareTo(b);
            });

          // Build flat list: stats bar + group headers + agent cards
          final items = <Widget>[];

          // Stats bar
          items.add(
            statsAsync.when(
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
          );

          for (final key in sortedKeys) {
            final groupAgents = groups[key]!;
            final header = key ?? 'Unknown Instance';

            // Determine instance online status from first agent in group
            final firstAgent = groupAgents.first;
            final instanceStatus =
                data.instanceStatuses[firstAgent.instanceId] ??
                    HealthStatus.unknown;
            final isInstanceOnline = instanceStatus.isConnectable;
            final isCollapsed = _collapsedGroups.contains(key);

            // Group header with collapse toggle and online dot
            items.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: InkWell(
                  onTap: () => _toggleGroup(key!),
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
                      // Instance name
                      Expanded(
                        child: Text(
                          header,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: isInstanceOnline
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Agent count badge
                      Text(
                        '${groupAgents.length}',
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
              ),
            );

            // Agent cards (hidden if collapsed)
            if (!isCollapsed) {
              for (final agent in groupAgents) {
                // Determine agent online status
                final agentOnline = data
                    .instanceStatuses[agent.instanceId]
                    ?.isConnectable ?? false;

                // Last active: use instance lastConnectedAt
                // In the future, this would come from agent-specific stats
                items.add(
                  AgentCard(
                    agent: agent,
                    isOnline: agentOnline,
                    lastActiveAt: _getLastActiveForAgent(
                        agent, data.instanceStatuses),
                    onTap: () {
                      context.push(
                        AppRoutes.chatWithParams(
                          agent.localId,
                          agent.instanceId,
                          source: 'claws',
                        ),
                      );
                    },
                  ),
                );
              }
            }
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: items,
          );
        },
      ),
    );
  }

  /// Get last active timestamp for an agent.
  /// Uses instance lastConnectedAt as a proxy in MVP.
  int? _getLastActiveForAgent(
    Agent agent,
    Map<String, HealthStatus> statuses,
  ) {
    // In MVP, we don't have per-agent last active time yet.
    // Return null to show "Never" — will be populated when
    // per-agent stats are implemented (US-019).
    return null;
  }
}
