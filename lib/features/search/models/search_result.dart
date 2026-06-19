/// A single search result enriched with agent and instance display information.
///
/// Feature-local DTO (not a domain entity) — constructed by [SearchViewModel]
/// from [IMessageRepo.search] results + batch agent and conversation lookups.
class SearchResult {
  final String messageClientId;
  final String conversationId;
  final String agentId;
  final String instanceId; // required for ChatRoomPage navigation
  final String agentName;
  final String? agentAvatarUrl;
  final String agentThemeColor;
  final String messageContent;
  final int messageTimestamp;
  final String highlightQuery; // original query for UI keyword highlighting

  // 哨兵值用于区分 copyWith 中"未传参"和"显式传 null"。
  static const _sentinel = Object();

  const SearchResult({
    required this.messageClientId,
    required this.conversationId,
    required this.agentId,
    required this.instanceId,
    required this.agentName,
    this.agentAvatarUrl,
    required this.agentThemeColor,
    required this.messageContent,
    required this.messageTimestamp,
    this.highlightQuery = '',
  });

  SearchResult copyWith({
    String? messageClientId,
    String? conversationId,
    String? agentId,
    String? instanceId,
    String? agentName,
    Object? agentAvatarUrl = _sentinel,
    String? agentThemeColor,
    String? messageContent,
    int? messageTimestamp,
    String? highlightQuery,
  }) {
    return SearchResult(
      messageClientId: messageClientId ?? this.messageClientId,
      conversationId: conversationId ?? this.conversationId,
      agentId: agentId ?? this.agentId,
      instanceId: instanceId ?? this.instanceId,
      agentName: agentName ?? this.agentName,
      agentAvatarUrl: identical(agentAvatarUrl, _sentinel)
          ? this.agentAvatarUrl
          : agentAvatarUrl as String?,
      agentThemeColor: agentThemeColor ?? this.agentThemeColor,
      messageContent: messageContent ?? this.messageContent,
      messageTimestamp: messageTimestamp ?? this.messageTimestamp,
      highlightQuery: highlightQuery ?? this.highlightQuery,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult && messageClientId == other.messageClientId;

  @override
  int get hashCode => messageClientId.hashCode;
}
