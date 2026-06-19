import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/search/models/search_result.dart';

void main() {
  group('SearchResult', () {
    test('construction with all required fields', () {
      final result = SearchResult(
        messageClientId: 'msg-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: 'Test Agent',
        agentThemeColor: '#007AFF',
        messageContent: 'Hello world',
        messageTimestamp: 1700000000000,
        highlightQuery: 'hello',
      );

      expect(result.messageClientId, 'msg-1');
      expect(result.conversationId, 'conv-1');
      expect(result.agentId, 'agent-1');
      expect(result.instanceId, 'inst-1');
      expect(result.agentName, 'Test Agent');
      expect(result.agentAvatarUrl, isNull);
      expect(result.agentThemeColor, '#007AFF');
      expect(result.messageContent, 'Hello world');
      expect(result.messageTimestamp, 1700000000000);
      expect(result.highlightQuery, 'hello');
    });

    test('equality based on messageClientId', () {
      final a = SearchResult(
        messageClientId: 'msg-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: 'A',
        agentThemeColor: '#111',
        messageContent: 'x',
        messageTimestamp: 1,
      );
      final b = SearchResult(
        messageClientId: 'msg-1',
        conversationId: 'conv-2',
        agentId: 'agent-2',
        instanceId: 'inst-2',
        agentName: 'B',
        agentThemeColor: '#222',
        messageContent: 'y',
        messageTimestamp: 2,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different messageClientId are not equal', () {
      final a = SearchResult(
        messageClientId: 'msg-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: 'A',
        agentThemeColor: '#111',
        messageContent: 'x',
        messageTimestamp: 1,
      );
      final b = SearchResult(
        messageClientId: 'msg-2',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: 'A',
        agentThemeColor: '#111',
        messageContent: 'x',
        messageTimestamp: 1,
      );

      expect(a, isNot(equals(b)));
    });

    test('copyWith preserves unset fields', () {
      final original = SearchResult(
        messageClientId: 'msg-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: 'Agent',
        agentThemeColor: '#007AFF',
        messageContent: 'content',
        messageTimestamp: 1,
      );

      final copy = original.copyWith(messageContent: 'new content');

      expect(copy.messageClientId, original.messageClientId);
      expect(copy.agentName, original.agentName);
      expect(copy.messageContent, 'new content');
    });

    test('copyWith with null clears nullable field (CopyWithSentinel)', () {
      final original = SearchResult(
        messageClientId: 'msg-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: 'Agent',
        agentAvatarUrl: 'http://example.com/avatar.png',
        agentThemeColor: '#007AFF',
        messageContent: 'content',
        messageTimestamp: 1,
      );

      // null explicitly clears agentAvatarUrl (uses sentinel to distinguish
      // "not provided" from "explicitly set to null")
      final copy = original.copyWith(agentAvatarUrl: null);
      expect(copy.agentAvatarUrl, isNull);

      // Not providing the param leaves it unchanged
      final unchangedCopy = original.copyWith(messageContent: 'new');
      expect(unchangedCopy.agentAvatarUrl, original.agentAvatarUrl);
    });
  });
}
