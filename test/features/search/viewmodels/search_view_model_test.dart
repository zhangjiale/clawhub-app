import 'dart:async';

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
