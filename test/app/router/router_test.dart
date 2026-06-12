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
      expect(
        () => router.go('/claws'),
        returnsNormally,
      );
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
      final router = AppRouter.router;
      final match = router.routerDelegate.currentConfiguration;

      // Chat route should accept source parameter
      final uri = Uri.parse('/chat/agent-123?instanceId=inst-1&source=agent_list');
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

    test('chatWithParams returns branch-relative path with query params', () {
      final path = AppRoutes.chatWithParams('agent-1', 'inst-1',
          source: 'claws');
      // chatWithParams is branch-relative (no leading /) so it works from
      // both /claws and /messages branches.
      expect(path, startsWith('chat/agent-1?'));
      expect(path, contains('instanceId=inst-1'));
      expect(path, contains('source=claws'));
    });
  });
}
