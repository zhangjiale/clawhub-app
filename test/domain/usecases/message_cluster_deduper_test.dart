import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/usecases/message_cluster_deduper.dart';

/// MessageClusterDeduper 当前没有任何直接单元测试 —— 由
/// `merge_inbound_message_test.dart`（只通过间接 import 验证符号存在）和
/// `drift_message_repo_integration_test.dart`（端到端 Drift）覆盖。
///
/// Law 17 要求 domain 层逐文件 TDD。本文件填补此缺口，并锁定链式聚簇
/// 拓扑（chained adjacency）的回归测试 —— 上一版本曾把 t=0/30s/90s
/// 三条相同消息全部合并，违反 ±60s 窗口保证。
void main() {
  Message makeMsg({
    required String clientId,
    required MessageRole role,
    required String content,
    required int timestamp,
    String? serverId,
    int clock = 0,
  }) {
    return Message(
      clientId: clientId,
      serverId: serverId,
      conversationId: 'conv-test',
      agentId: 'agent-test',
      role: role,
      content: content,
      type: MessageType.text,
      status: role == MessageRole.user
          ? MessageStatus.sent
          : MessageStatus.delivered,
      logicalClock: clock,
      timestamp: timestamp,
    );
  }

  group('MessageClusterDeduper.plan — chaining regression', () {
    test('three identical messages at t=0, t=30s, t=90s are NOT all clustered '
        '(first and last are 90s apart > 60s window)', () {
      final msgs = [
        makeMsg(
          clientId: 'c0',
          role: MessageRole.user,
          content: '好的',
          timestamp: 1718000000000,
          serverId: 's0',
          clock: 100,
        ),
        makeMsg(
          clientId: 'c1',
          role: MessageRole.user,
          content: '好的',
          timestamp: 1718000000000 + 30000, // +30s
          serverId: 's1',
          clock: 101,
        ),
        makeMsg(
          clientId: 'c2',
          role: MessageRole.user,
          content: '好的',
          timestamp: 1718000000000 + 90000, // +90s
          serverId: 's2',
          clock: 102,
        ),
      ];

      final doomed = MessageClusterDeduper.plan(msgs);

      // t=0 与 t=30s 在窗口内 → 可合并；t=0 与 t=90s 跨窗口 → 不能合并。
      // 修复后的算法应当：c0 保留，c1 与 c0 合并被删（或反之），c2 保留。
      // 旧（链式）实现：c0 + c1 + c2 全部合并，c0/c2 被删，c1 保留。
      expect(
        doomed.length,
        lessThanOrEqualTo(1),
        reason:
            '三个相距 >60s 的相同消息不应全部合并 —— t=0 与 t=90s '
            'delta=90s>60s，应保留为两条独立消息。',
      );
      expect(
        doomed.contains('c2') && doomed.contains('c0'),
        isFalse,
        reason: 't=90s 与 t=0 跨窗口，必须至少保留其中一条（不能两条都删）',
      );
    });

    test(
      'messages within ±60s DO cluster (adjacent within window is correct)',
      () {
        final msgs = [
          makeMsg(
            clientId: 'c0',
            role: MessageRole.user,
            content: 'hello',
            timestamp: 1718000000000,
            serverId: 's0',
            clock: 100,
          ),
          makeMsg(
            clientId: 'c1',
            role: MessageRole.user,
            content: 'hello',
            timestamp: 1718000000000 + 50000, // +50s, within ±60s
            serverId: null,
            clock: 101,
          ),
        ];

        final doomed = MessageClusterDeduper.plan(msgs);

        expect(doomed.length, 1, reason: '两条窗口内的相同消息应合并');
        expect(
          doomed.contains('c1'),
          isTrue,
          reason: '无 serverId 的应被删，保留有 serverId 的 c0',
        );
      },
    );

    test('messages with delta exactly 60s DO cluster (boundary inclusive)', () {
      final msgs = [
        makeMsg(
          clientId: 'c0',
          role: MessageRole.user,
          content: 'hi',
          timestamp: 1718000000000,
          serverId: 's0',
          clock: 100,
        ),
        makeMsg(
          clientId: 'c1',
          role: MessageRole.user,
          content: 'hi',
          timestamp: 1718000000000 + 60000, // exactly 60s
          serverId: null,
          clock: 101,
        ),
      ];

      final doomed = MessageClusterDeduper.plan(msgs);

      expect(doomed.length, 1, reason: '|Δ|=60s 在窗口内（≤60s）应合并');
    });

    test('messages with delta 61s do NOT cluster (boundary exclusive)', () {
      final msgs = [
        makeMsg(
          clientId: 'c0',
          role: MessageRole.user,
          content: 'hi',
          timestamp: 1718000000000,
          serverId: 's0',
          clock: 100,
        ),
        makeMsg(
          clientId: 'c1',
          role: MessageRole.user,
          content: 'hi',
          timestamp: 1718000000000 + 61000, // 61s, just over window
          serverId: 's1',
          clock: 101,
        ),
      ];

      final doomed = MessageClusterDeduper.plan(msgs);

      expect(doomed, isEmpty, reason: '|Δ|=61s 超出窗口（>60s）不合并');
    });

    // -------------------------------------------------------------------------
    // toolResult 空 stdout 不应被清理：它承载工具执行记录，按 content 聚簇
    // 删除会把工具卡整个移除。
    // -------------------------------------------------------------------------
    test('empty-content toolResult message is NOT deleted', () {
      final msgs = [
        makeMsg(
          clientId: 'tool-empty',
          role: MessageRole.toolResult,
          content: '',
          timestamp: 1718000000000,
          serverId: 'srv-tool',
          clock: 100,
        ),
      ];

      final doomed = MessageClusterDeduper.plan(msgs);

      expect(
        doomed.contains('tool-empty'),
        isFalse,
        reason: '空 content 的 toolResult 必须保留',
      );
    });
  });
}
