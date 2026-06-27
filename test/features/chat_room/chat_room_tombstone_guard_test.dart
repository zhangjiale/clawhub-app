// US-021 AC8: 打开已被 Gateway 删除（tombstoned）的 agent 聊天页时，
// 不渲染聊天界面，而是显示"已移除"占位页（统一使用 AgentRemovedPlaceholder
// widget,与 AgentProfilePage / AgentConfigPage 一致 —— US-021 v1.2 迁移）。
//
// Step 4 改造:tombstone 不再用 state.isAgentRemoved bool 字段，改读
// vm.agent.isRemoved。stub 直接 override `agent` getter 返回预设 Agent
// (含或不含 removedAt) —— ChatRoomPage 的 guard 直接读 agent.isRemoved
// 触发占位页分支,无需再预置 state。
//
// 用 stub 子类 override `agent` getter，**不调用 vm.init()** —— init()
// 会订阅 MockGatewayClient 的流，而 overrideWith 无法注册 onDispose
// （StateNotifier debugIsMounted 限制），流订阅泄漏会导致 tearDownAll
// 挂起。guard 路径只读 vm.agent.isRemoved 就早退，不会触发任何流/定时器。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/placeholders/agent_removed_placeholder.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

const _key = (instanceId: 'inst-1', agentId: 'local-1');

/// Stub ChatViewModel：override `agent` 返回预设值（供占位页 displayName）
/// 模拟 tombstone 状态。Step 4: 不再预置 state.isAgentRemoved —— UI 改读
/// vm.agent.isRemoved,agent 自身的 removedAt 字段就是 tombstone 信号。
/// 不调 init()，无流订阅。
class _StubAgentVm extends ChatViewModel {
  final Agent? _stubAgent;
  _StubAgentVm(this._stubAgent)
    : super(
        agentRepo: InMemoryAgentRepo(),
        conversationRepo: InMemoryConversationRepo(),
        messageRepo: InMemoryMessageRepo(),
        instanceRepo: InMemoryInstanceRepo(),
        gatewayClient: MockGatewayClient(),
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: InMemoryMessageRepo(),
          conversationRepo: InMemoryConversationRepo(),
          instanceRepo: InMemoryInstanceRepo(),
          gatewayClient: MockGatewayClient(),
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );

  @override
  Agent? get agent => _stubAgent;
}

void main() {
  testWidgets('tombstoned agent ChatRoom shows removed placeholder instead '
      'of chat UI (US-021)', (tester) async {
    final vm = _StubAgentVm(
      Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
        removedAt: 1719200000000,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
        child: const MaterialApp(
          home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
        ),
      ),
    );
    await tester.pump();

    // 聊天界面未渲染（无输入框）
    expect(find.byType(TextField), findsNothing);
    // US-021 v1.2: 必须使用 AgentRemovedPlaceholder widget,
    // 不能继续 inline 占位页 —— 否则三处文案/样式 drift。
    expect(
      find.byType(AgentRemovedPlaceholder),
      findsOneWidget,
      reason:
          'chat_room_page 必须使用统一的 AgentRemovedPlaceholder widget '
          '(与 AgentProfilePage / AgentConfigPage 一致)',
    );
    // 占位页基本文案仍存在
    expect(find.text('该 Agent 已从 Gateway 移除'), findsOneWidget);
    expect(find.text('产品虾'), findsOneWidget);
  });

  testWidgets('active agent ChatRoom renders chat UI normally (guard does '
      'not false-positive)', (tester) async {
    final vm = _StubAgentVm(
      Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
        // 无 removedAt —— active
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
        child: const MaterialApp(
          home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
        ),
      ),
    );
    await tester.pump();

    // active agent → 不显示"已移除"占位
    expect(find.text('该 Agent 已从 Gateway 移除'), findsNothing);
    expect(find.text('虾已移除'), findsNothing);
  });
}
