import 'dart:async';

import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';

/// 内存版实例仓库（MVP 开发用，后续替换为 drift/SQLite 实现）
class InMemoryInstanceRepo implements IInstanceRepo {
  final Map<String, Instance> _store = {};

  @override
  Future<List<Instance>> getAll() async {
    final list = _store.values.toList();
    list.sort(
      (a, b) => (b.lastConnectedAt ?? 0).compareTo(a.lastConnectedAt ?? 0),
    );
    return list;
  }

  @override
  Future<Instance?> getById(String id) async => _store[id];

  @override
  Future<Instance> save(Instance instance) async {
    _store[instance.id] = instance;
    return instance;
  }

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<bool> nameExists(String name, {String? excludeId}) async {
    return _store.values.any(
      (i) => i.name == name && (excludeId == null || i.id != excludeId),
    );
  }

  @override
  Future<Instance> updateHealthStatus(String id, HealthStatus status) async {
    final instance = _store[id];
    if (instance == null) throw StateError('实例不存在: $id');
    final updated = instance.copyWith(healthStatus: status);
    _store[id] = updated;
    return updated;
  }

  @override
  Future<void> updateLastConnectedAt(String id, int timestamp) async {
    final instance = _store[id];
    if (instance != null) {
      _store[id] = instance.copyWith(lastConnectedAt: timestamp);
    }
  }

  @override
  Future<List<String>> batchUpdateStatusByNetwork({
    required bool isLocalNetwork,
    required HealthStatus status,
  }) async {
    final affected = <String>[];
    for (final entry in _store.entries) {
      if (entry.value.isLocalNetwork == isLocalNetwork) {
        _store[entry.key] = entry.value.copyWith(healthStatus: status);
        affected.add(entry.key);
      }
    }
    return affected;
  }
}

/// 内存版 Agent 仓库
class InMemoryAgentRepo implements IAgentRepo {
  final Map<String, Agent> _store = {}; // localId -> Agent
  final Map<String, Agent> _byCompositeKey =
      {}; // "instanceId:remoteId" -> Agent

  /// Shared sort comparator: pinned first, then by name.
  int _compareAgents(Agent a, Agent b) {
    if (a.isPinned != b.isPinned) return b.isPinned ? 1 : -1;
    return a.name.compareTo(b.name);
  }

  List<Agent> _sorted(Iterable<Agent> agents) {
    final list = agents.toList();
    list.sort(_compareAgents);
    return list;
  }

  String _compositeKey(String instanceId, String remoteId) =>
      '$instanceId:$remoteId';

  @override
  Future<List<Agent>> getByInstanceId(String instanceId) async {
    return _sorted(_store.values.where((a) => a.instanceId == instanceId));
  }

  @override
  Future<List<Agent>> getAll() async {
    return _sorted(_store.values);
  }

  @override
  Future<Agent?> getById(String localId) async => _store[localId];

  @override
  Future<Map<String, Agent>> getByIds(List<String> localIds) async {
    final result = <String, Agent>{};
    for (final id in localIds) {
      final agent = _store[id];
      if (agent != null) result[id] = agent;
    }
    return result;
  }

  @override
  Future<Agent?> findByCompositeKey(String instanceId, String remoteId) async {
    return _byCompositeKey[_compositeKey(instanceId, remoteId)];
  }

  /// Add or update an agent in both indexes.
  void _putAgent(Agent agent) {
    _store[agent.localId] = agent;
    _byCompositeKey[_compositeKey(agent.instanceId, agent.remoteId)] = agent;
  }

  @override
  Future<List<Agent>> syncFromGateway(
    String instanceId,
    List<Agent> remoteAgents,
  ) async {
    final results = <Agent>[];
    for (final remote in remoteAgents) {
      final existing = await findByCompositeKey(instanceId, remote.remoteId);
      if (existing != null) {
        // Update existing agent while preserving local customizations
        final updated = existing.copyWith(
          name: remote.name,
          description: remote.description,
          // Preserve local customizations
          nickname: existing.nickname,
          avatarUrl: existing.avatarUrl,
          themeColor: existing.themeColor,
        );
        _putAgent(updated);
        results.add(updated);
      } else {
        // New agent
        _putAgent(remote);
        results.add(remote);
      }
    }
    return results;
  }

  @override
  Future<Agent> updateLocalProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
  }) async {
    final agent = _store[localId];
    if (agent == null) throw StateError('Agent 不存在: $localId');
    final updated = agent.copyWith(
      nickname: nickname,
      avatarUrl: avatarUrl,
      themeColor: themeColor,
    );
    _putAgent(updated);
    return updated;
  }

  @override
  Future<void> updateFullProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
    List<QuickCommand>? quickCommands,
  }) async {
    final agent = _store[localId];
    if (agent == null) throw StateError('Agent 不存在: $localId');

    // In-memory: single copyWith is inherently atomic (no partial-write risk).
    var updated = agent.copyWith(
      nickname: nickname,
      avatarUrl: avatarUrl,
      themeColor: themeColor,
    );
    if (quickCommands != null) {
      updated = updated.copyWith(
        quickCommands: [...quickCommands]..sort(QuickCommand.sortByOrder),
      );
    }
    _putAgent(updated);
  }

  @override
  Future<void> clearAvatar(String localId) async {
    final agent = _store[localId];
    if (agent == null) throw StateError('Agent 不存在: $localId');
    // 绕过 copyWith 的 ?? 语义 — 直接构造 Agent 将 avatarUrl 置为 null。
    final updated = Agent(
      localId: agent.localId,
      remoteId: agent.remoteId,
      instanceId: agent.instanceId,
      name: agent.name,
      nickname: agent.nickname,
      avatarUrl: null, // 显式清除
      themeColor: agent.themeColor,
      description: agent.description,
      isPinned: agent.isPinned,
      quickCommands: agent.quickCommands,
      createdAt: agent.createdAt,
    );
    _putAgent(updated);
  }

  @override
  Future<Agent> togglePin(String localId) async {
    final agent = _store[localId];
    if (agent == null) throw StateError('Agent 不存在: $localId');
    final updated = agent.copyWith(isPinned: !agent.isPinned);
    _putAgent(updated);
    return updated;
  }

  @override
  Future<void> deleteByInstanceId(String instanceId) async {
    final toRemove = _store.values
        .where((a) => a.instanceId == instanceId)
        .toList();
    for (final agent in toRemove) {
      _store.remove(agent.localId);
      _byCompositeKey.remove(_compositeKey(agent.instanceId, agent.remoteId));
    }
  }
}

/// 内存版消息仓库
class InMemoryMessageRepo implements IMessageRepo {
  final Map<String, Message> _byClientId = {};
  final Map<String, Message> _byServerId = {};

  /// 可选的 conversation repo，用于按 instanceId 过滤 outbox。
  /// 为 null 时 getOutboxByInstance / getOutboxCountByInstance 返回空
  /// （向后兼容不需要 instance 级过滤的旧测试）。
  final InMemoryConversationRepo? _conversationRepo;

  /// 消息变更广播 — 任何写操作后通知 [watchOutboxCount] 订阅者重查。
  /// 对齐 Drift 实现的 stream query 语义（写即重发）。
  final StreamController<void> _messagesChanged =
      StreamController<void>.broadcast();

  InMemoryMessageRepo({InMemoryConversationRepo? conversationRepo})
    : _conversationRepo = conversationRepo;

  /// 通知 outbox 计数订阅者重查（写操作后调用）。
  void _notifyChanged() {
    if (!_messagesChanged.isClosed) _messagesChanged.add(null);
  }

  @override
  Future<Message> insert(Message message) async {
    _byClientId[message.clientId] = message;
    if (message.serverId != null) {
      _byServerId[message.serverId!] = message;
    }
    _notifyChanged();
    return message;
  }

  @override
  Future<Message?> getByClientId(String clientId) async =>
      _byClientId[clientId];

  @override
  Future<Message?> getByServerId(String serverId) async =>
      _byServerId[serverId];

  @override
  Future<List<Message>> getByConversation(
    String conversationId, {
    String? before,
    int limit = 50,
  }) async {
    var messages = _byClientId.values
        .where((m) => m.conversationId == conversationId)
        .toList();
    messages.sort((a, b) => b.logicalClock.compareTo(a.logicalClock));
    if (before != null) {
      final beforeMsg = _byClientId[before];
      if (beforeMsg != null) {
        messages = messages
            .where((m) => m.logicalClock < beforeMsg.logicalClock)
            .toList();
      }
    }
    return messages.take(limit).toList();
  }

  @override
  Future<List<Message>> getAnchorWindow(
    String conversationId, {
    required String targetClientId,
    int before = 5,
    int after = 10,
  }) async {
    final target = _byClientId[targetClientId];
    if (target == null) return [];

    // Bug 6: Target must belong to the requested conversation.
    // _byClientId is a global lookup without conversation filter.
    if (target.conversationId != conversationId) return [];

    // Bounded anchor window mirroring the Drift implementation: take at most
    // `before` older + target + `after` newer, filtered by logicalClock
    // relative to the target. No unbounded full-conversation slice.
    //
    // Bug 5: <= in older filter preserves same-clock messages (treated as
    // "before"). After filter uses strict > to avoid duplication.
    // clientId exclusion prevents the target itself from appearing twice.
    final older =
        _byClientId.values
            .where(
              (m) =>
                  m.conversationId == conversationId &&
                  m.logicalClock <= target.logicalClock &&
                  m.clientId != targetClientId,
            )
            .toList()
          ..sort((a, b) => b.logicalClock.compareTo(a.logicalClock)); // DESC
    final olderBounded = older.take(before).toList().reversed; // back to ASC

    final newer =
        _byClientId.values
            .where(
              (m) =>
                  m.conversationId == conversationId &&
                  m.logicalClock > target.logicalClock,
            )
            .toList()
          ..sort((a, b) => a.logicalClock.compareTo(b.logicalClock)); // ASC
    final newerBounded = newer.take(after);

    return [...olderBounded, target, ...newerBounded];
  }

  @override
  Future<Message> updateStatus(String clientId, MessageStatus status) async {
    final msg = _byClientId[clientId];
    if (msg == null) throw StateError('消息不存在: $clientId');
    final updated = msg.transitionTo(status); // 使用领域模型的状态机验证
    _byClientId[clientId] = updated;
    _notifyChanged();
    return updated;
  }

  @override
  Future<Message> bindServerId(String clientId, String serverId) async {
    final msg = _byClientId[clientId];
    if (msg == null) throw StateError('消息不存在: $clientId');
    final updated = msg.bindServerId(serverId);
    _byClientId[clientId] = updated;
    _byServerId[serverId] = updated;
    _notifyChanged();
    return updated;
  }

  @override
  Future<List<Message>> getOutbox(String agentId) async {
    return _byClientId.values
        .where(
          (m) =>
              m.agentId == agentId &&
              (m.status == MessageStatus.pending ||
                  m.status == MessageStatus.failed),
        )
        .toList();
  }

  @override
  Future<List<Message>> getOutboxByInstance(String instanceId) async {
    if (_conversationRepo == null) return [];

    final convIds = _conversationRepo!.getConversationIdsByInstance(instanceId);
    if (convIds.isEmpty) return [];

    final results = _byClientId.values
        .where(
          (m) =>
              convIds.contains(m.conversationId) &&
              (m.status == MessageStatus.pending ||
                  m.status == MessageStatus.failed),
        )
        .toList();
    results.sort((a, b) => a.logicalClock.compareTo(b.logicalClock));
    return results;
  }

  @override
  Future<int> getOutboxCountByInstance(String instanceId) async {
    if (_conversationRepo == null) return 0;

    final convIds = _conversationRepo!.getConversationIdsByInstance(instanceId);
    if (convIds.isEmpty) return 0;

    return _byClientId.values
        .where(
          (m) =>
              convIds.contains(m.conversationId) &&
              (m.status == MessageStatus.pending ||
                  m.status == MessageStatus.failed),
        )
        .length;
  }

  @override
  Stream<int> watchOutboxCount(String instanceId) async* {
    // 首次订阅发射当前值（对齐 Drift watchSingle 语义），
    // 之后任何写操作触发 _messagesChanged → 重查并发射新值。
    // async* 生成的 stream 支持订阅取消（VM dispose 时自动终止）。
    yield await getOutboxCountByInstance(instanceId);
    await for (final _ in _messagesChanged.stream) {
      yield await getOutboxCountByInstance(instanceId);
    }
  }

  @override
  Future<bool> tryTransitionToSending(
    String clientId,
    MessageStatus expectedStatus,
  ) async {
    final message = _byClientId[clientId];
    if (message == null || message.status != expectedStatus) return false;
    final updated = message.transitionTo(MessageStatus.sending);
    _byClientId[clientId] = updated;
    _notifyChanged();
    return true;
  }

  @override
  Future<int> resetStaleSending(String instanceId) async {
    // 与 Drift 实现一致：仅重置该实例的 SENDING → PENDING，
    // 防止跨实例重置。无 conversationRepo 时无法按实例过滤，返回 0（向后兼容）。
    //
    // server_id 守卫：已绑定 serverId 的 SENDING 消息已被 Gateway ACK
    // （bindServerId 执行了但状态机未推进到 SENT，App 即被 kill）。
    // 重置它会让下一轮 flush 重发 → 服务端收到重复消息。跳过这类消息。
    if (_conversationRepo == null) return 0;

    final convIds = _conversationRepo!.getConversationIdsByInstance(instanceId);
    if (convIds.isEmpty) return 0;

    var count = 0;
    for (final entry in _byClientId.entries.toList()) {
      if (entry.value.status == MessageStatus.sending &&
          entry.value.serverId == null &&
          convIds.contains(entry.value.conversationId)) {
        _byClientId[entry.key] = entry.value.copyWith(
          status: MessageStatus.pending,
        );
        count++;
      }
    }
    if (count > 0) _notifyChanged();
    return count;
  }

  @override
  Future<List<Message>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final lower = query.toLowerCase();
    final results = _byClientId.values
        .where(
          (m) => m.content != null && m.content!.toLowerCase().contains(lower),
        )
        .toList();
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results.skip(offset).take(limit).toList();
  }

  @override
  Future<int> cleanupOldMessages(String agentId, {int keep = 1000}) async {
    final agentMsgs = _byClientId.values
        .where((m) => m.agentId == agentId)
        .toList();
    if (agentMsgs.length <= keep) return 0;

    agentMsgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final toRemove = agentMsgs.skip(keep);
    for (final msg in toRemove) {
      _byClientId.remove(msg.clientId);
      if (msg.serverId != null) _byServerId.remove(msg.serverId);
    }
    if (toRemove.isNotEmpty) _notifyChanged();
    return toRemove.length;
  }

  @override
  Future<int> getMessageCount(String agentId) async {
    return _byClientId.values.where((m) => m.agentId == agentId).length;
  }

  @override
  Future<Map<String, int>> getMessageCountsByAgent(
    List<String> agentIds,
  ) async {
    final counts = <String, int>{};
    for (final id in agentIds) {
      counts[id] = 0;
    }
    // Single pass through all messages — O(messages) instead of O(agents × messages)
    for (final msg in _byClientId.values) {
      final count = counts[msg.agentId];
      if (count != null) {
        counts[msg.agentId] = count + 1;
      }
    }
    return counts;
  }

  @override
  Future<void> deleteByClientId(String clientId) async {
    final msg = _byClientId.remove(clientId);
    if (msg?.serverId != null) _byServerId.remove(msg!.serverId);
    _notifyChanged();
  }

  @override
  Future<List<Message>> batchInsertByIndexedIds(List<Message> messages) async {
    final inserted = <Message>[];
    for (final msg in messages) {
      // Dedup by both clientId and serverId
      if (_byClientId.containsKey(msg.clientId)) continue;
      // bug #12: 对齐 Drift 的空字符串守卫 — serverId="" 不是真实 ID
      if (msg.serverId != null &&
          msg.serverId!.isNotEmpty &&
          _byServerId.containsKey(msg.serverId))
        continue;
      _byClientId[msg.clientId] = msg;
      if (msg.serverId != null && msg.serverId!.isNotEmpty) {
        _byServerId[msg.serverId!] = msg;
      }
      inserted.add(msg);
    }
    if (inserted.isNotEmpty) _notifyChanged();
    return inserted;
  }
}

/// 内存版会话仓库
class InMemoryConversationRepo implements IConversationRepo {
  final Map<String, Conversation> _store = {};

  /// 返回属于指定实例的所有 conversation ID 集合。
  ///
  /// 供 [InMemoryMessageRepo] 按 instanceId 过滤消息使用。
  Set<String> getConversationIdsByInstance(String instanceId) {
    return _store.values
        .where((c) => c.instanceId == instanceId)
        .map((c) => c.id)
        .toSet();
  }

  @override
  Future<Conversation> getOrCreate(String instanceId, String agentId) async {
    final id = Conversation.generateId(instanceId, agentId);
    return _store.putIfAbsent(
      id,
      () => Conversation(agentId: agentId, instanceId: instanceId),
    );
  }

  @override
  Future<List<Conversation>> getAllWithMessages() async {
    final list = _store.values.where((c) => c.lastMessageTime > 0).toList();
    list.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return list;
  }

  @override
  Future<Conversation?> getById(String id) async => _store[id];

  @override
  Future<Map<String, Conversation>> getByIds(List<String> ids) async {
    final result = <String, Conversation>{};
    for (final id in ids) {
      final conv = _store[id];
      if (conv != null) result[id] = conv;
    }
    return result;
  }

  @override
  Future<Conversation> updateLastMessage({
    required String conversationId,
    required String messageId,
    required String preview,
    required int timestamp,
    required MessageRole role,
  }) async {
    final conv = _store[conversationId];
    if (conv == null) throw StateError('会话不存在: $conversationId');
    final updated = conv.updateLastMessage(
      messageId: messageId,
      preview: preview,
      timestamp: timestamp,
      role: role,
    );
    _store[conversationId] = updated;
    return updated;
  }

  @override
  Future<Conversation> incrementUnread(
    String conversationId, {
    int count = 1,
  }) async {
    final conv = _store[conversationId];
    if (conv == null) throw StateError('会话不存在: $conversationId');
    final updated = conv.copyWith(unreadCount: conv.unreadCount + count);
    _store[conversationId] = updated;
    return updated;
  }

  @override
  Future<Conversation> clearUnread(String conversationId) async {
    final conv = _store[conversationId];
    if (conv == null) throw StateError('会话不存在: $conversationId');
    final updated = conv.clearUnread();
    _store[conversationId] = updated;
    return updated;
  }

  @override
  Future<Conversation> toggleMute(String conversationId) async {
    final conv = _store[conversationId];
    if (conv == null) throw StateError('会话不存在: $conversationId');
    final updated = conv.copyWith(isMuted: !conv.isMuted);
    _store[conversationId] = updated;
    return updated;
  }

  @override
  Future<void> deleteByInstanceId(String instanceId) async {
    _store.removeWhere((_, c) => c.instanceId == instanceId);
  }
}
