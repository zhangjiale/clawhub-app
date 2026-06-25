import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_conversation_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/features/search/viewmodels/search_view_model.dart';
import 'package:claw_hub/features/search/models/search_result.dart';

class MockMessageRepo extends Mock implements IMessageRepo {}

class MockAgentRepo extends Mock implements IAgentRepo {}

class MockConversationRepo extends Mock implements IConversationRepo {}

Message _testMessage({
  String clientId = 'msg-1',
  String agentId = 'agent-1',
  String conversationId = 'conv-1',
  String content = 'Hello world',
  int timestamp = 1000,
}) {
  return Message(
    clientId: clientId,
    conversationId: conversationId,
    agentId: agentId,
    role: MessageRole.agent,
    content: content,
    type: MessageType.text,
    logicalClock: 1,
    timestamp: timestamp,
  );
}

Agent _testAgent({String localId = 'agent-1'}) {
  return Agent(
    localId: localId,
    remoteId: 'remote-1',
    instanceId: 'inst-1',
    name: 'Test Agent',
    themeColor: '#007AFF',
  );
}

Conversation _testConversation({String id = 'conv-1'}) {
  return Conversation(id: id, agentId: 'agent-1', instanceId: 'inst-1');
}

void main() {
  group('SearchState', () {
    test('default state has empty results', () {
      const state = SearchState();
      expect(state.results, isA<LoadData>());
      expect((state.results as LoadData).value, isEmpty);
      expect(state.query, '');
      expect(state.isLoadingMore, false);
      expect(state.hasMore, false);
    });

    test('copyWith preserves unset fields', () {
      const original = SearchState();
      final copy = original.copyWith(query: 'test');
      expect(copy.query, 'test');
      expect(copy.results, original.results);
      expect(copy.isLoadingMore, original.isLoadingMore);
    });
  });

  group('SearchViewModel', () {
    late MockMessageRepo messageRepo;
    late MockAgentRepo agentRepo;
    late MockConversationRepo conversationRepo;
    late SearchViewModel vm;

    setUp(() {
      messageRepo = MockMessageRepo();
      agentRepo = MockAgentRepo();
      conversationRepo = MockConversationRepo();

      when(
        () => messageRepo.search(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => []);
      when(() => agentRepo.getByIds(any())).thenAnswer((_) async => {});
      when(() => conversationRepo.getByIds(any())).thenAnswer((_) async => {});

      vm = SearchViewModel(
        messageRepo: messageRepo,
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
      );
    });

    tearDown(() => vm.dispose());

    test('initial state has empty results', () {
      expect(vm.state.results, isA<LoadData>());
      expect(vm.state.query, '');
    });

    test('onQueryChanged with empty string clears results immediately', () {
      vm.onQueryChanged('   ');
      expect(vm.state.query, '');
      expect(vm.state.results, isA<LoadData>());
    });

    test('onQueryChanged triggers search after debounce', () async {
      when(
        () => messageRepo.search(
          'hello',
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => [_testMessage(content: 'hello world')]);
      when(
        () => agentRepo.getByIds(['agent-1']),
      ).thenAnswer((_) async => {'agent-1': _testAgent()});
      when(
        () => conversationRepo.getByIds(['conv-1']),
      ).thenAnswer((_) async => {'conv-1': _testConversation()});

      vm.onQueryChanged('hello');
      expect(vm.state.query, '');

      await Future.delayed(const Duration(milliseconds: 350));

      expect(vm.state.query, 'hello');
      expect(vm.state.results, isA<LoadData>());
      final results =
          (vm.state.results as LoadData).value as List<SearchResult>;
      expect(results.length, 1);
      expect(results.first.messageContent, 'hello world');
      expect(results.first.agentName, 'Test Agent');
      expect(results.first.instanceId, 'inst-1');
      expect(results.first.highlightQuery, 'hello');
    });

    test('search error yields LoadError', () async {
      when(
        () => messageRepo.search(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenThrow(Exception('DB error'));

      vm.onQueryChanged('crash');
      await Future.delayed(const Duration(milliseconds: 350));

      expect(vm.state.results, isA<LoadError>());
    });

    test('loadMore does nothing when hasMore is false', () async {
      await vm.loadMore();
      verifyNever(
        () => messageRepo.search(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      );
    });

    test('hasMore detection — returns pageSize+1 then trims', () async {
      final messages = List.generate(
        21,
        (i) => _testMessage(clientId: 'msg-$i'),
      );
      when(
        () => messageRepo.search('many', limit: 21, offset: 0),
      ).thenAnswer((_) async => messages);
      when(() => agentRepo.getByIds(any())).thenAnswer(
        (_) async => {for (var i = 0; i < 21; i++) 'agent-1': _testAgent()},
      );
      when(() => conversationRepo.getByIds(any())).thenAnswer(
        (_) async => {
          for (var i = 0; i < 21; i++) 'conv-1': _testConversation(),
        },
      );

      vm.onQueryChanged('many');
      await Future.delayed(const Duration(milliseconds: 350));

      expect(vm.state.hasMore, true);
      final results =
          (vm.state.results as LoadData).value as List<SearchResult>;
      expect(results.length, 20);
    });

    test(
      'loadMore uses raw DB offset after tombstoned agents are filtered',
      () async {
        final activeAgent = Agent(
          localId: 'agent-active',
          remoteId: 'r-active',
          instanceId: 'inst-1',
          name: '活虾',
          themeColor: '#6c5ce7',
        );
        final tombstonedAgent = Agent(
          localId: 'agent-tomb',
          remoteId: 'r-tomb',
          instanceId: 'inst-1',
          name: '死虾',
          themeColor: '#6c5ce7',
          removedAt: 1719200000000,
        );

        // First page: 21 raw rows, first 5 belong to tombstoned agent.
        final firstPage = List.generate(
          21,
          (i) => Message(
            clientId: 'msg-$i',
            conversationId: 'conv-${i < 5 ? 'tomb' : 'active'}',
            agentId: i < 5 ? 'agent-tomb' : 'agent-active',
            role: MessageRole.user,
            content: 'hello $i',
            type: MessageType.text,
            logicalClock: i,
            timestamp: 1000 + i,
          ),
        );

        when(
          () => messageRepo.search('raw', limit: 21, offset: 0),
        ).thenAnswer((_) async => firstPage);
        when(() => messageRepo.search('raw', limit: 21, offset: 20)).thenAnswer(
          (_) async => [
            Message(
              clientId: 'msg-21',
              conversationId: 'conv-active',
              agentId: 'agent-active',
              role: MessageRole.user,
              content: 'hello 21',
              type: MessageType.text,
              logicalClock: 21,
              timestamp: 1021,
            ),
          ],
        );
        when(() => agentRepo.getByIds(any())).thenAnswer(
          (_) async => {
            'agent-active': activeAgent,
            'agent-tomb': tombstonedAgent,
          },
        );
        when(() => conversationRepo.getByIds(any())).thenAnswer(
          (_) async => {
            'conv-active': Conversation(
              id: 'conv-active',
              instanceId: 'inst-1',
              agentId: 'agent-active',
            ),
            'conv-tomb': Conversation(
              id: 'conv-tomb',
              instanceId: 'inst-1',
              agentId: 'agent-tomb',
            ),
          },
        );

        vm.onQueryChanged('raw');
        await Future.delayed(const Duration(milliseconds: 400));

        // First page yields 15 visible results (msg-5..msg-19) + hasMore.
        final firstResults = switch (vm.state.results) {
          LoadData(:final value) => value,
          _ => <SearchResult>[],
        };
        expect(firstResults.length, 15);
        expect(vm.state.hasMore, true);

        await vm.loadMore();

        // Critical: second query must use raw offset 20, not filtered offset 15.
        verify(
          () => messageRepo.search('raw', limit: 21, offset: 20),
        ).called(1);

        final allResults = switch (vm.state.results) {
          LoadData(:final value) => value,
          _ => <SearchResult>[],
        };
        final clientIds = allResults.map((r) => r.messageClientId).toList();
        expect(clientIds.toSet().length, clientIds.length);
        expect(
          allResults.any(
            (r) =>
                r.messageClientId == 'msg-19' && r.messageClientId == 'msg-21',
          ),
          isFalse,
        );
        expect(allResults.any((r) => r.messageClientId == 'msg-21'), isTrue);
      },
    );

    test('hasMore=false when entire page is tombstoned '
        '(no load-more affordance for empty visible results)', () async {
      // US-021 v1.2 修复：原 hasMore 用 raw DB 计数
      // (messages.length > _pageSize)，当全页 tombstone 时 hasMore 仍 true，
      // 用户点 load more 反复拿到 0 可见结果,UX 卡死。
      final tombstonedAgent = Agent(
        localId: 'agent-tomb',
        remoteId: 'r-tomb',
        instanceId: 'inst-1',
        name: '死虾',
        themeColor: '#6c5ce7',
        removedAt: DateTime.now().millisecondsSinceEpoch,
      );

      // 21 raw rows (hasMore raw=true), 全部 tombstoned → filtered=0
      final allTombPage = List.generate(
        21,
        (i) => Message(
          clientId: 'msg-$i',
          conversationId: 'conv-tomb',
          agentId: 'agent-tomb',
          role: MessageRole.user,
          content: 'hello $i',
          type: MessageType.text,
          logicalClock: i,
          timestamp: 1000 + i,
        ),
      );

      when(
        () => messageRepo.search('raw', limit: 21, offset: 0),
      ).thenAnswer((_) async => allTombPage);
      when(
        () => agentRepo.getByIds(any()),
      ).thenAnswer((_) async => {'agent-tomb': tombstonedAgent});
      when(() => conversationRepo.getByIds(any())).thenAnswer(
        (_) async => {
          'conv-tomb': Conversation(
            id: 'conv-tomb',
            instanceId: 'inst-1',
            agentId: 'agent-tomb',
          ),
        },
      );

      vm.onQueryChanged('raw');
      await Future.delayed(const Duration(milliseconds: 400));

      final results = switch (vm.state.results) {
        LoadData(:final value) => value,
        _ => <SearchResult>[],
      };
      expect(results, isEmpty, reason: '全 tombstone 页 → 0 可见结果');
      expect(
        vm.state.hasMore,
        isFalse,
        reason:
            'hasMore 必须基于可见结果数 (filtered),不是 raw DB 计数。'
            '全 tombstone 页不应让用户继续点 load more',
      );
    });

    test('dispose cancels debounce timer', () async {
      // Create a separate VM so tearDown doesn't double-dispose.
      // We can't call dispose() on vm from setUp and then again in tearDown.
      final testVm = SearchViewModel(
        messageRepo: messageRepo,
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
      );
      testVm.onQueryChanged('delayed');
      // dispose before tearDown fires on the setUp VM.
      testVm.dispose();

      await Future.delayed(const Duration(milliseconds: 350));

      verifyNever(
        () => messageRepo.search(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      );
    });

    test('enrichment sets instanceId from conversation lookup', () async {
      when(
        () => messageRepo.search(
          'query',
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => [_testMessage()]);
      when(
        () => agentRepo.getByIds(['agent-1']),
      ).thenAnswer((_) async => {'agent-1': _testAgent()});
      when(
        () => conversationRepo.getByIds(['conv-1']),
      ).thenAnswer((_) async => {'conv-1': _testConversation(id: 'conv-1')});

      vm.onQueryChanged('query');
      await Future.delayed(const Duration(milliseconds: 350));

      final results =
          (vm.state.results as LoadData).value as List<SearchResult>;
      expect(results.first.instanceId, 'inst-1');
    });

    test('filters out tombstoned agents from search results', () async {
      // Arrange: 2 messages, one for active agent, one for tombstoned agent
      final activeAgent = Agent(
        localId: 'agent-active',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '活虾',
        themeColor: '#6c5ce7',
      );
      final tombstonedAgent = Agent(
        localId: 'agent-tomb',
        remoteId: 'r-2',
        instanceId: 'inst-1',
        name: '死虾',
        themeColor: '#6c5ce7',
        removedAt: 1719200000000,
      );
      final msgActive = Message(
        clientId: 'm1',
        conversationId: 'c1',
        agentId: 'agent-active',
        role: MessageRole.user,
        content: 'hello active',
        type: MessageType.text,
        logicalClock: 1,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final msgTomb = Message(
        clientId: 'm2',
        conversationId: 'c2',
        agentId: 'agent-tomb',
        role: MessageRole.user,
        content: 'hello tomb',
        type: MessageType.text,
        logicalClock: 2,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      when(
        () => messageRepo.search(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => [msgActive, msgTomb]);
      when(() => agentRepo.getByIds(any())).thenAnswer(
        (_) async => {
          'agent-active': activeAgent,
          'agent-tomb': tombstonedAgent,
        },
      );
      when(() => conversationRepo.getByIds(any())).thenAnswer(
        (_) async => {
          'c1': Conversation(
            id: 'c1',
            instanceId: 'inst-1',
            agentId: 'agent-active',
          ),
          'c2': Conversation(
            id: 'c2',
            instanceId: 'inst-1',
            agentId: 'agent-tomb',
          ),
        },
      );

      vm.onQueryChanged('hello');

      // Wait for debounce + execution
      await Future.delayed(const Duration(milliseconds: 400));

      // Assert: only active agent's result remains
      final results = switch (vm.state.results) {
        LoadData(:final value) => value,
        _ => <SearchResult>[],
      };
      expect(results.length, 1, reason: 'tombstoned agent 必须从搜索结果过滤');
      expect(results[0].agentId, 'agent-active');
      expect(results.any((r) => r.agentId == 'agent-tomb'), isFalse);
    });

    test('preserves non-tombstoned agents in search results', () async {
      final aliveAgent = Agent(
        localId: 'agent-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '活虾',
        themeColor: '#6c5ce7',
      );
      final msg = Message(
        clientId: 'm1',
        conversationId: 'c1',
        agentId: 'agent-1',
        role: MessageRole.user,
        content: 'hello',
        type: MessageType.text,
        logicalClock: 1,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      when(
        () => messageRepo.search(
          any(),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => [msg]);
      when(
        () => agentRepo.getByIds(any()),
      ).thenAnswer((_) async => {'agent-1': aliveAgent});
      when(() => conversationRepo.getByIds(any())).thenAnswer(
        (_) async => {
          'c1': Conversation(
            id: 'c1',
            instanceId: 'inst-1',
            agentId: 'agent-1',
          ),
        },
      );

      vm.onQueryChanged('hello');
      await Future.delayed(const Duration(milliseconds: 400));

      final results = switch (vm.state.results) {
        LoadData(:final value) => value,
        _ => <SearchResult>[],
      };
      expect(results.length, 1, reason: 'alive agent 必须保留');
    });
  });
}
