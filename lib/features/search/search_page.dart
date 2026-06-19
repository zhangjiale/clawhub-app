import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/router/smart_back.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/features/search/providers/search_providers.dart';
import 'package:claw_hub/features/search/viewmodels/search_view_model.dart';
import 'package:claw_hub/features/search/widgets/search_bar_widget.dart';
import 'package:claw_hub/features/search/widgets/search_result_tile.dart';

/// Global message search page (US-017).
///
/// Full-screen page that searches across all agents' message history using
/// FTS5 full-text search. Results show agent avatar, name, highlighted
/// content preview, and timestamp. Tapping a result navigates to the
/// corresponding chat room with the target message highlighted.
///
/// [source] tracks which tab the user entered from ('claws' or 'messages'),
/// ensuring the back button returns to the correct tab.
class SearchPage extends ConsumerStatefulWidget {
  final String? source;

  const SearchPage({super.key, this.source});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  void _handleBack() {
    if (mounted) smartBack(context, source: widget.source);
  }

  void _handleResultTap(
    String agentId,
    String instanceId,
    String messageClientId,
    String highlightQuery,
  ) {
    context.push(
      AppRoutes.chatWithParams(
        agentId,
        instanceId,
        source: widget.source,
        highlightMessageId: messageClientId,
        highlightQuery: highlightQuery,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchViewModelProvider);
    final vm = ref.read(searchViewModelProvider.notifier);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: XiaBackButton(onPressed: _handleBack),
          title: const Text('搜索消息'),
        ),
        body: Column(
          children: [
            SearchBarWidget(onChanged: vm.onQueryChanged),
            Expanded(child: _buildBody(state, vm, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SearchState state, SearchViewModel vm, ThemeData theme) {
    return switch (state.results) {
      LoadInProgress() => const LoadingSkeleton(count: 3),
      LoadError(:final error) => LoadErrorView(error: error, title: '搜索失败'),
      LoadData(:final value) when value.isEmpty && state.query.isEmpty =>
        const EmptyState(
          icon: Icon(Icons.search, size: 48),
          title: '搜索所有消息记录',
          subtitle: '输入关键词，跨所有虾的对话历史搜索',
        ),
      LoadData(:final value) when value.isEmpty => EmptyState(
        icon: const Icon(Icons.search_off, size: 48),
        title: '没有找到包含「${state.query}」的消息',
        subtitle: '尝试其他关键词',
      ),
      LoadData(:final value) => ListView.builder(
        itemCount: value.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == value.length) {
            // "Load more" footer.
            return Padding(
              padding: const EdgeInsets.all(XiaSpacing.s4),
              child: state.isLoadingMore
                  ? const Center(child: CircularProgressIndicator())
                  : TextButton(
                      onPressed: () => vm.loadMore(),
                      child: const Text('加载更多'),
                    ),
            );
          }
          final result = value[index];
          return SearchResultTile(
            result: result,
            onTap: () => _handleResultTap(
              result.agentId,
              result.instanceId,
              result.messageClientId,
              result.highlightQuery,
            ),
          );
        },
      ),
    };
  }
}
