import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/features/instance_manager/instance_list_page.dart';
import 'package:claw_hub/features/instance_manager/add_instance_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/features/agent_list/agent_list_page.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/message_hub/message_hub_page.dart';
import 'package:claw_hub/features/agent_profile/agent_profile_page.dart';

/// 路由路径常量
class AppRoutes {
  AppRoutes._();

  static const String claws = '/claws';
  static const String messages = '/messages';
  static const String instances = '/instances';
  static const String chat = '/chat/:agentId';
  static const String agentProfile = '/agent-profile/:agentId';
  static const String addInstance = '/instances/add';
  static const String editInstance = '/instances/edit/:instanceId';

  /// 带参数生成路径（相对路径，用于 context.push 分支内导航）
  static String chatWithParams(
    String agentId,
    String instanceId, {
    String? source,
  }) {
    final params = <String, String>{'instanceId': instanceId};
    if (source != null) params['source'] = source;
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return 'chat/$agentId?$query';
  }

  static String agentProfileWithParams(String agentId, {String? source}) {
    if (source != null) return 'agent-profile/$agentId?source=$source';
    return 'agent-profile/$agentId';
  }

  static String editInstanceWithParams(String instanceId) {
    return 'edit/$instanceId';
  }
}

/// ClawHub 全局路由配置
/// 对齐: 架构 vFinal 5.8 (智能返回栈)
/// 路由器采用懒加载单例，避免 build 时重建导致路由栈丢失和 GlobalKey 冲突
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

  /// 懒加载单例 GoRouter 实例
  static final GoRouter _router = _createRouter();

  /// 获取全局路由器实例
  static GoRouter get router => _router;

  /// Shared sub-route for chat (used in both Claws and Messages branches).
  static GoRoute _chatRoute() {
    return GoRoute(
      path: 'chat/:agentId',
      builder: (context, state) {
        final agentId = state.pathParameters['agentId']!;
        final instanceId =
            state.uri.queryParameters['instanceId'] ?? '';
        final source = state.uri.queryParameters['source'];
        return ChatRoomPage(
          agentId: agentId,
          instanceId: instanceId,
          source: source,
        );
      },
    );
  }

  static GoRouter _createRouter() {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: AppRoutes.claws,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return _TabScaffold(navigationShell: navigationShell);
          },
          branches: [
            // Branch 0: Claws (虾列表)
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
                        return AgentProfilePage(agentId: agentId);
                      },
                    ),
                  ],
                ),
              ],
            ),

            // Branch 1: Messages (消息)
            StatefulShellBranch(
              navigatorKey: _messagesNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.messages,
                  builder: (context, state) => const MessageHubPage(),
                  routes: [
                    _chatRoute(),
                  ],
                ),
              ],
            ),

            // Branch 2: Instances (实例)
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

/// 三 Tab 导航脚手架
class _TabScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _TabScaffold({required this.navigationShell});

  static const _selectedColor = AppColors.primaryBlue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pets),
            selectedIcon: Icon(Icons.pets, color: _selectedColor),
            label: '虾列表',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: _selectedColor),
            label: '消息',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns, color: _selectedColor),
            label: '实例',
          ),
        ],
      ),
    );
  }
}
