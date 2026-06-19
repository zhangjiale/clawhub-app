import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/router/router.dart';

void main() {
  group('AppRouter', () {
    test('router is GoRouter instance', () {
      final router = AppRouter.router;
      expect(router, isNotNull);
    });

    test('router has correct initial location', () {
      final router = AppRouter.router;
      // StatefulShellRoute defaults to first branch
      expect(() => router.go('/claws'), returnsNormally);
    });

    test('all tab routes can be navigated', () {
      final router = AppRouter.router;

      // Each branch should be navigable
      expect(router.canPop(), isFalse); // at root

      // Navigate to each tab
      router.go('/claws');
      router.go('/messages');
      router.go('/instances');
    });

    test('sourceTag is passed as query parameter in chat route', () {
      // Chat route should accept source parameter
      final uri = Uri.parse(
        '/chat/agent-123?instanceId=inst-1&source=agent_list',
      );
      expect(uri.queryParameters['source'], 'agent_list');
      expect(uri.queryParameters['instanceId'], 'inst-1');
    });

    test('named route locations are defined', () {
      expect(AppRoutes.claws, '/claws');
      expect(AppRoutes.messages, '/messages');
      expect(AppRoutes.instances, '/instances');
      expect(AppRoutes.chat, '/chat/:agentId');
      expect(AppRoutes.agentProfile, '/agent-profile/:agentId');
      expect(AppRoutes.addInstance, '/instances/add');
      expect(AppRoutes.editInstance, '/instances/edit/:instanceId');
    });

    test('editInstanceWithParams returns absolute path', () {
      final path = AppRoutes.editInstanceWithParams('abc-123');
      expect(path, '/instances/edit/abc-123');
    });

    test('chatWithParams returns absolute path with query params', () {
      final path = AppRoutes.chatWithParams(
        'agent-1',
        'inst-1',
        source: 'claws',
      );
      // chatWithParams uses absolute path (leading /) so it works from
      // any branch and avoids go_router relative-path resolution issues.
      expect(path, startsWith('/claws/chat/agent-1?'));
      expect(path, contains('instanceId=inst-1'));
      expect(path, contains('source=claws'));
    });

    test('chatWithParams uses /messages prefix when source is messages', () {
      final path = AppRoutes.chatWithParams(
        'agent-1',
        'inst-1',
        source: 'messages',
      );
      expect(path, startsWith('/messages/chat/agent-1?'));
      expect(path, contains('instanceId=inst-1'));
      expect(path, contains('source=messages'));
    });

    test('agentProfileWithParams returns absolute path', () {
      final path = AppRoutes.agentProfileWithParams('agent-1', source: 'claws');
      expect(path, '/claws/agent-profile/agent-1?source=claws');
    });

    test('agentConfigWithParams returns absolute path', () {
      final path = AppRoutes.agentConfigWithParams('agent-1');
      expect(path, '/claws/agent-profile/config/agent-1');
    });

    // ---------------------------------------------------------------------------
    // Law 16(A): searchWithParams — 参数化路径方法必须有返回值断言
    // ---------------------------------------------------------------------------
    group('searchWithParams', () {
      test('returns claws-branch path when source is claws', () {
        final path = AppRoutes.searchWithParams(source: 'claws');
        expect(path, '/claws/search?source=claws');
      });

      test('returns messages-branch path when source is messages', () {
        final path = AppRoutes.searchWithParams(source: 'messages');
        expect(path, '/messages/search?source=messages');
      });

      test('returns claws-branch path when source is null', () {
        final path = AppRoutes.searchWithParams();
        expect(path, '/claws/search');
      });
    });

    // ---------------------------------------------------------------------------
    // Law 16(A): chatWithParams — 高亮参数必须出现在返回 URL 中
    // ---------------------------------------------------------------------------
    group('chatWithParams highlight params', () {
      test('includes highlightMessageId in query string', () {
        final path = AppRoutes.chatWithParams(
          'agent-1',
          'inst-1',
          highlightMessageId: 'msg-abc',
        );
        expect(path, contains('highlightMessageId=msg-abc'));
      });

      test('includes highlightQuery in query string', () {
        final path = AppRoutes.chatWithParams(
          'agent-1',
          'inst-1',
          highlightQuery: 'hello world',
        );
        expect(path, contains('highlightQuery=hello+world'));
      });

      test('includes both highlight params together', () {
        final path = AppRoutes.chatWithParams(
          'agent-1',
          'inst-1',
          source: 'messages',
          highlightMessageId: 'msg-xyz',
          highlightQuery: 'test query',
        );
        expect(path, startsWith('/messages/chat/agent-1?'));
        expect(path, contains('highlightMessageId=msg-xyz'));
        expect(path, contains('highlightQuery=test+query'));
      });

      test('URL-encodes special characters in highlightQuery', () {
        final path = AppRoutes.chatWithParams(
          'agent-1',
          'inst-1',
          highlightMessageId: 'msg-xyz',
          highlightQuery: 'a & b',
        );
        expect(path, contains('highlightQuery=a+%26+b'));
        // Must NOT contain unencoded & from the query value
        // (only & separating params)
        final paramPart = path.split('?')[1];
        final pairs = paramPart.split('&');
        // instanceId + highlightMessageId + highlightQuery = 3 pairs,
        // no extra params from unencoded &
        expect(pairs.length, 3);
      });
    });
  });
}
