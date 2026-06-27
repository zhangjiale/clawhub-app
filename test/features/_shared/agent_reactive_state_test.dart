// Finding #8 (2026-06-27 重构): mixin 行为 unit test。
//
// 共享逻辑：
// - contentEquals 守卫过滤同内容重复 emit（避免 contentRevision 无意义 bump）
// - null 转换总是 propagate（identity 变化 → 必须 bump）
// - debugSetAgent 等价于 setAgent（测试钩子）

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/_shared/agent_reactive_state.dart';
import 'package:claw_hub/domain/models/agent.dart';

/// 最小 host class —— 不依赖 StateNotifier / Riverpod，验证 mixin
/// 可独立组合。`onAgentUpdated` 由 host 实现，记录调用次数与最新
/// `revision` 模拟 VM 的 contentRevision bump。
class _MixinHost with AgentReactiveState {
  int revision = 0;
  final List<Agent?> emitted = [];

  @override
  void onAgentUpdated() {
    revision++;
    emitted.add(agent);
  }
}

Agent _alive({String? localId, String? name}) => Agent(
  localId: localId ?? 'local-1',
  remoteId: 'r-1',
  instanceId: 'inst-1',
  name: name ?? '产品虾',
  themeColor: '#6c5ce7',
);

Agent _tombstoned({String? localId}) => Agent(
  localId: localId ?? 'local-1',
  remoteId: 'r-1',
  instanceId: 'inst-1',
  name: '产品虾',
  themeColor: '#6c5ce7',
  removedAt: 1719200000000,
);

void main() {
  group('AgentReactiveState mixin (Finding #8)', () {
    test('初始化后 agent getter 返回 null，revision == 0', () {
      final host = _MixinHost();
      expect(host.agent, isNull);
      expect(host.revision, 0);
    });

    test('首次写入非 null agent → revision bump + agent getter 返回新值', () {
      final host = _MixinHost();
      host.setAgent(_alive());

      expect(host.agent, isNotNull);
      expect(host.agent!.localId, 'local-1');
      expect(host.revision, 1);
    });

    test('同内容重复 emit → contentEquals 守卫过滤，不 bump revision', () {
      // 关键不变量：Drift `.watchSingleOrNull()` 的 seed event 经常与已有
      // _agent 内容完全相同，guard 必须吃掉避免 revision 噪声。
      final host = _MixinHost();
      final first = _alive(name: '小明虾');
      host.setAgent(first);
      expect(host.revision, 1);

      host.setAgent(_alive(name: '小明虾')); // 内容完全相同
      expect(host.revision, 1, reason: 'contentEquals guard 应阻止重复 bump');
    });

    test('内容变更（nickname 变） → revision bump', () {
      final host = _MixinHost();
      host.setAgent(_alive(name: '小明虾'));
      host.setAgent(_alive(name: '小红虾')); // 名字变了
      expect(host.revision, 2);
    });

    test('null → alive 转换 → revision bump（首次加载）', () {
      final host = _MixinHost();
      host.setAgent(_alive());
      expect(host.revision, 1);
    });

    test('alive → tombstoned 转换 → revision bump（守墓碑占位页响应）', () {
      final host = _MixinHost();
      host.setAgent(_alive());
      expect(host.revision, 1);

      host.setAgent(_tombstoned());
      expect(host.revision, 2, reason: 'tombstone 翻转必须 propagate');
      expect(host.agent!.isRemoved, isTrue);
    });

    test('tombstoned → alive 复活 → revision bump', () {
      final host = _MixinHost();
      host.setAgent(_tombstoned());
      expect(host.revision, 1);

      host.setAgent(_alive());
      expect(host.revision, 2);
    });

    test('debugSetAgent 等价于 setAgent（测试钩子）', () {
      final host = _MixinHost();
      host.debugSetAgent(_alive());
      expect(host.revision, 1);
      expect(host.agent, isNotNull);

      host.debugSetAgent(_tombstoned());
      expect(host.revision, 2);
      expect(host.agent!.isRemoved, isTrue);
    });

    test('debugSetAgent 同样受 contentEquals 守卫约束', () {
      final host = _MixinHost();
      host.debugSetAgent(_alive(name: '小明虾'));
      expect(host.revision, 1);

      host.debugSetAgent(_alive(name: '小明虾'));
      expect(host.revision, 1, reason: 'debugSetAgent 也走 setAgent，guard 同样生效');
    });

    test('emitted 列表记录每次 onAgentUpdated 触发的最新 agent', () {
      final host = _MixinHost();
      final a = _alive();
      final b = _tombstoned();
      host.setAgent(a);
      host.setAgent(b);
      host.setAgent(null);

      expect(host.emitted.length, 3);
      expect(host.emitted[0], same(a));
      expect(host.emitted[1], same(b));
      expect(host.emitted[2], isNull);
    });
  });
}
