import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

/// Agent 列表页 (P0 MVP Phase 4)
/// 按实例分组展示所有 Agent，支持搜索过滤，点击进入聊天
class AgentListPage extends ConsumerStatefulWidget {
  const AgentListPage({super.key});

  @override
  ConsumerState<AgentListPage> createState() => _AgentListPageState();
}

class _AgentListPageState extends ConsumerState<AgentListPage> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _query = '';

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

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sortedKeys.length,
            itemBuilder: (context, index) {
              final key = sortedKeys[index];
              final groupAgents = groups[key]!;
              final header = key ?? 'Unknown Instance';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      header,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  ...groupAgents.map(
                    (agent) => AgentCard(
                      agent: agent,
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
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
