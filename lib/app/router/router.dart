import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/instance_manager/instance_list_page.dart';
import 'package:claw_hub/features/instance_manager/add_instance_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/features/agent_list/agent_list_page.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/message_hub/message_hub_page.dart';
import 'package:claw_hub/features/agent_profile/agent_profile_page.dart';
import 'package:claw_hub/features/agent_profile/agent_config_page.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';

/// Route path constants.
class AppRoutes {
  AppRoutes._();

  static const String claws = '/claws';
  static const String messages = '/messages';
  static const String instances = '/instances';
  static const String chat = '/chat/:agentId';
  static const String agentProfile = '/agent-profile/:agentId';
  static const String addInstance = '/instances/add';
  static const String editInstance = '/instances/edit/:instanceId';

  static String chatWithParams(
    String agentId,
    String instanceId, {
    String? source,
  }) {
    final params = <String, String>{'instanceId': instanceId};
    if (source != null) params['source'] = source;
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    // Use absolute path — the chat route exists under both /claws and /messages
    // branches, so we use source to pick the correct branch prefix.
    final branch = source == 'messages' ? '/messages' : '/claws';
    return '$branch/chat/$agentId?$query';
  }

  // Agent profile and config routes only exist under /claws (not /messages).
  // This is intentional: agent identity and configuration are owned by the
  // "虾列表" (Claws) tab.  Navigating from a messages-branch chat to the
  // agent profile will switch the bottom-nav tab to Claws.
  //
  // Unlike chatWithParams, these helpers ignore the source parameter
  // because there is no /messages-branch route to redirect to.
  static String agentProfileWithParams(String agentId, {String? source}) {
    if (source != null) return '/claws/agent-profile/$agentId?source=$source';
    return '/claws/agent-profile/$agentId';
  }

  static String agentConfigWithParams(String agentId) {
    return '/claws/agent-profile/config/$agentId';
  }

  static String editInstanceWithParams(String instanceId) {
    return '/instances/edit/$instanceId';
  }
}

/// Global router with StatefulShellRoute (3-tab bottom nav).
class AppRouter {
  AppRouter._();

  static final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static final GlobalKey<NavigatorState> _clawsNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'claws');

  static final GlobalKey<NavigatorState> _messagesNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'messages');

  static final GlobalKey<NavigatorState> _instancesNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'instances');

  static final GoRouter _router = _createRouter();

  static GoRouter get router => _router;

  static GoRoute _chatRoute() {
    return GoRoute(
      path: 'chat/:agentId',
      builder: (context, state) {
        final agentId = state.pathParameters['agentId']!;
        final instanceId = state.uri.queryParameters['instanceId'] ?? '';
        final source = state.uri.queryParameters['source'];
        return ChatRoomPage(
          agentId: agentId,
          instanceId: instanceId,
          source: source,
        );
      },
    );
  }

  /// Simple error page shown when no route matches.
  /// Reuses [LoadErrorView] to keep the error layout consistent across the app.
  static Widget _errorPageBuilder(BuildContext context, GoRouterState state) {
    final location = state.uri.toString();
    debugPrint('❌ GoRouter: no routes for location: $location');
    return Scaffold(
      appBar: AppBar(title: const Text('Navigation Error')),
      body: LoadErrorView(
        title: 'Page Not Found',
        error: 'No route matched:\n$location',
      ),
    );
  }

  static GoRouter _createRouter() {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: AppRoutes.claws,
      errorBuilder: _errorPageBuilder,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return _TabScaffold(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              navigatorKey: _clawsNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.claws,
                  builder: (context, state) => const AgentListPage(),
                  routes: [
                    _chatRoute(),
                    GoRoute(
                      path: 'agent-profile/:agentId',
                      builder: (context, state) {
                        final agentId = state.pathParameters['agentId']!;
                        final source = state.uri.queryParameters['source'];
                        return AgentProfilePage(
                          agentId: agentId,
                          source: source,
                        );
                      },
                    ),
                    GoRoute(
                      path: 'agent-profile/config/:agentId',
                      builder: (context, state) {
                        final agentId = state.pathParameters['agentId']!;
                        return AgentConfigPage(agentId: agentId);
                      },
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _messagesNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.messages,
                  builder: (context, state) => const MessageHubPage(),
                  routes: [_chatRoute()],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _instancesNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.instances,
                  builder: (context, state) => const InstanceListPage(),
                  routes: [
                    GoRoute(
                      path: 'add',
                      builder: (context, state) {
                        final scanResult = state.extra as QrScanResult?;
                        return AddInstancePage(scanResult: scanResult);
                      },
                    ),
                    GoRoute(
                      path: 'edit/:instanceId',
                      builder: (context, state) {
                        final instanceId = state.pathParameters['instanceId']!;
                        return AddInstancePage(instanceId: instanceId);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Three-tab scaffold with glassmorphism bottom nav.
class _TabScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _TabScaffold({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: XiaGlass.navBlur,
            sigmaY: XiaGlass.navBlur,
          ),
          child: Container(
            height: 72,
            decoration: const BoxDecoration(
              color: XiaGlass.navBackground,
              border: Border(top: BorderSide(color: XiaColors.divider)),
            ),
            child: Row(
              children: [
                _NavTab(
                  icon: Icons.pets,
                  label: '虾列表',
                  isActive: navigationShell.currentIndex == 0,
                  onTap: () => navigationShell.goBranch(0),
                ),
                _NavTab(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: '消息',
                  isActive: navigationShell.currentIndex == 1,
                  onTap: () => navigationShell.goBranch(1),
                ),
                _NavTab(
                  icon: Icons.dns_outlined,
                  activeIcon: Icons.dns,
                  label: '实例',
                  isActive: navigationShell.currentIndex == 2,
                  onTap: () => navigationShell.goBranch(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? XiaColors.accent : XiaColors.text4;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: XiaSpacing.s6,
            vertical: XiaSpacing.s2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? (activeIcon ?? icon) : icon,
                size: 22,
                color: color,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
