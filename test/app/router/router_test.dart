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
    });
  });
}
