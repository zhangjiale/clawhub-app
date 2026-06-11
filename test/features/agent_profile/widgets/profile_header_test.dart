import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/agent_profile/widgets/profile_header.dart';

void main() {
  group('ProfileHeader', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划、需求分析',
      themeColor: '#6c5ce7',
      isPinned: false,
    );

    final testInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
    );

    final onlineInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
      healthStatus: HealthStatus.online,
    );

    Widget buildHeader({
      required Agent agent,
      Instance? instance,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ProfileHeader(agent: agent, instance: instance),
        ),
      );
    }

    testWidgets('renders agent displayName', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('renders agent description', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('产品规划、需求分析'), findsOneWidget);
    });

    testWidgets('renders avatar with first character', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('shows instance name when instance provided', (tester) async {
      await tester.pumpWidget(
          buildHeader(agent: testAgent, instance: testInstance));
      expect(find.text('我的MacBook'), findsOneWidget);
    });

    testWidgets('shows "未知实例" when instance is null', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('未知实例'), findsOneWidget);
    });

    testWidgets('shows green online status when instance is online',
        (tester) async {
      await tester.pumpWidget(
          buildHeader(agent: testAgent, instance: onlineInstance));
      expect(find.text('在线'), findsOneWidget);
    });

    testWidgets('shows "离线" when instance is absent', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('离线'), findsOneWidget);
    });
  });
}
