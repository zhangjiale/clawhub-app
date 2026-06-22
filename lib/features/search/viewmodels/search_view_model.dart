import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/features/search/models/search_result.dart';

/// Immutable state snapshot for the search page.
class SearchState {
  final LoadState<List<SearchResult>> results;
  final String query; // debounced query (what was actually searched)
  final bool isLoadingMore;
  final bool hasMore;

  const SearchState({
    this.results = const LoadData([]),
    this.query = '',
    this.isLoadingMore = false,
    this.hasMore = false,
  });

  SearchState copyWith({
    LoadState<List<SearchResult>>? results,
    String? query,
    bool? isLoadingMore,
    bool? hasMore,
  }) {
    return SearchState(
      results: results ?? this.results,
      query: query ?? this.query,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState &&
          results == other.results &&
          query == other.query &&
          isLoadingMore == other.isLoadingMore &&
          hasMore == other.hasMore;

  @override
  int get hashCode => Object.hash(results, query, isLoadingMore, hasMore);
}

/// ViewModel for global message search (US-017).
///
/// Orchestrates: debounced FTS5 search → batch enrichment (agent + conversation)
/// → paginated results. All search executes locally — no network requests.
class SearchViewModel extends StateNotifier<SearchState> {
  final IMessageRepo _messageRepo;
  final IAgentRepo _agentRepo;
  final IConversationRepo _conversationRepo;

  Timer? _debounceTimer;
  int _searchGeneration = 0;

  static const _pageSize = 20;
  static const _maxResults = 200;
  static const _debounceMs = 300;

  SearchViewModel({
    required IMessageRepo messageRepo,
    required IAgentRepo agentRepo,
    required IConversationRepo conversationRepo,
  }) : _messageRepo = messageRepo,
       _agentRepo = agentRepo,
       _conversationRepo = conversationRepo,
       super(const SearchState());

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Called on every input change. Debounces 300ms before searching.
  void onQueryChanged(String input) {
    _debounceTimer?.cancel();

    if (input.trim().isEmpty) {
      _updateState(
        (s) =>
            s.copyWith(query: '', results: const LoadData([]), hasMore: false),
      );
      return;
    }

    _debounceTimer = Timer(
      const Duration(milliseconds: _debounceMs),
      () => _search(input.trim()),
    );
  }

  /// Load more results (pagination). No-op if already loading or no more.
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;
    final currentCount = switch (state.results) {
      LoadData(:final value) => value.length,
      _ => 0,
    };
    _updateState((s) => s.copyWith(isLoadingMore: true));
    await _executeSearch(state.query, offset: currentCount);
    _updateState((s) => s.copyWith(isLoadingMore: false));
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _search(String query) async {
    final generation = ++_searchGeneration;
    _updateState(
      (s) => s.copyWith(
        query: query,
        results: const LoadInProgress(),
        isLoadingMore: false, // 新搜索阻止旧搜索的 loadMore 继续
      ),
    );
    await _executeSearch(query, offset: 0, generation: generation);
  }

  Future<void> _executeSearch(
    String query, {
    required int offset,
    int generation = 0,
  }) async {
    try {
      final remaining = _maxResults - offset;
      if (remaining <= 0) {
        _updateState((s) => s.copyWith(hasMore: false));
        return;
      }

      // Request pageSize + 1 to detect hasMore (standard pattern).
      final fetchLimit = _pageSize + 1 <= remaining ? _pageSize + 1 : remaining;

      final messages = await _messageRepo.search(
        query,
        limit: fetchLimit,
        offset: offset,
      );

      // Batch enrichment — run independent lookups concurrently (Law 6).
      final agentIds = messages.map((m) => m.agentId).toSet().toList();
      final conversationIds = messages
          .map((m) => m.conversationId)
          .toSet()
          .toList();

      final enrichment = await Future.wait([
        _agentRepo.getByIds(agentIds),
        _conversationRepo.getByIds(conversationIds),
      ]);
      final agents = enrichment[0] as Map<String, Agent>;
      final conversations = enrichment[1] as Map<String, Conversation>;

      // Detect hasMore before truncating the extra item.
      final hasMore = messages.length > _pageSize;
      final pageMessages = hasMore ? messages.sublist(0, _pageSize) : messages;

      final results = pageMessages.map((m) {
        final agent = agents[m.agentId];
        final conv = conversations[m.conversationId];
        return SearchResult(
          messageClientId: m.clientId,
          conversationId: m.conversationId,
          agentId: m.agentId,
          instanceId: conv?.instanceId ?? '',
          agentName: agent?.displayName ?? m.agentId,
          agentAvatarUrl: agent?.avatarUrl,
          agentThemeColor: agent?.themeColor ?? '#4F83FF',
          messageContent: m.content ?? '',
          messageTimestamp: m.timestamp,
          highlightQuery: query,
        );
      }).toList();

      final totalFetched = offset + results.length;

      // Merge into existing results if paginating, else replace.
      final merged = offset == 0
          ? results
          : <SearchResult>[
              ...switch (state.results) {
                LoadData(:final value) => value,
                _ => <SearchResult>[],
              },
              ...results,
            ];

      // 丢弃过期的搜索结果（更新一代搜索已启动）
      if (generation != _searchGeneration) return;
      _updateState(
        (s) => s.copyWith(
          results: LoadData(merged),
          hasMore: hasMore && totalFetched < _maxResults,
        ),
      );
    } catch (error, stackTrace) {
      if (generation != _searchGeneration) return;
      debugPrint(
        '[SearchViewModel] _executeSearch failed: $error\n$stackTrace',
      );
      _updateState(
        (s) => s.copyWith(
          results: LoadError(error, stackTrace),
          isLoadingMore: false,
          hasMore: false,
        ),
      );
    }
  }

  void _updateState(SearchState Function(SearchState) transform) {
    if (!mounted) return;
    state = transform(state);
  }

  /// 清除内部状态（Major #1 修复: clearCacheActionProvider 调用）。
  ///
  /// 保留 VM 实例本身（不 dispose），只清空 results/query/hasMore，
  /// 让 UI 立即回到"无搜索结果"的初始视图。`_searchGeneration` 自增
  /// 是为了取消任何 in-flight `_executeSearch`（虽然已 clearAll 的 DB
  /// 已空，但防止并发回填污染状态）。
  void clear() {
    _debounceTimer?.cancel();
    _searchGeneration++;
    _updateState(
      (s) => s.copyWith(
        results: const LoadData([]),
        query: '',
        isLoadingMore: false,
        hasMore: false,
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
