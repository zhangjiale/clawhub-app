import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

void main() {
  group('Agent', () {
    test('创建有效 Agent（复合键方案）', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'remote-001',
        instanceId: 'inst-001',
        name: '产品虾',
      );

      expect(agent.localId, 'local-a1');
      expect(agent.remoteId, 'remote-001');
      expect(agent.instanceId, 'inst-001');
      expect(agent.name, '产品虾');
      expect(agent.nickname, isNull); // 可选字段
      expect(agent.avatarUrl, isNull);
      expect(agent.themeColor, '#4F83FF'); // V2 sapphire 默认色
      expect(agent.isPinned, isFalse);
    });

    test('同一实例同一 remoteId 视为相同 Agent', () {
      final a1 = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      final a2 = Agent(
        localId: 'local-a2',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾（改名）',
      );

      // 同一 (instanceId, remoteId) 组合应视为同一 Agent
      expect(a1.isSameAgent(a2), isTrue);
    });

    test('不同实例同 remoteId 视为不同 Agent', () {
      final a1 = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      final a2 = Agent(
        localId: 'local-a2',
        remoteId: 'r1',
        instanceId: 'inst-002',
        name: '产品虾',
      );

      expect(a1.isSameAgent(a2), isFalse);
    });

    test('主题色格式校验', () {
      // 有效 Hex 颜色
      final validColors = ['#007AFF', '#6c5ce7', '#00b894', '#FF0000', '#abc'];
      for (final color in validColors) {
        final agent = Agent(
          localId: 'local-test',
          remoteId: 'r-test',
          instanceId: 'inst-001',
          name: '测试虾',
          themeColor: color,
        );
        expect(agent.themeColor, color);
      }
    });

    test('无效主题色应抛异常', () {
      expect(
        () => Agent(
          localId: 'local-test',
          remoteId: 'r-test',
          instanceId: 'inst-001',
          name: '测试虾',
          themeColor: 'blue', // 不是 Hex 格式
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('名称为空应抛异常', () {
      expect(
        () => Agent(
          localId: 'local-test',
          remoteId: 'r-test',
          instanceId: 'inst-001',
          name: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('昵称最大20字符', () {
      final validNick = Agent(
        localId: 'local-test',
        remoteId: 'r-test',
        instanceId: 'inst-001',
        name: '测试虾',
        nickname: '12345678901234567890', // 正好20字
      );
      expect(validNick.nickname!.length, 20);

      expect(
        () => Agent(
          localId: 'local-test2',
          remoteId: 'r-test2',
          instanceId: 'inst-001',
          name: '测试虾',
          nickname: '123456789012345678901', // 21字
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('description 可选字段默认为 null', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      expect(agent.description, isNull);
    });

    test('copyWith 保留 description 字段', () {
      final original = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        description: '产品规划、需求分析',
      );
      expect(original.description, '产品规划、需求分析');

      final updated = original.copyWith(name: '新名称');
      expect(updated.description, '产品规划、需求分析'); // 未被覆盖
    });

    test('copyWith 正确创建修改副本', () {
      final original = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );

      final updated = original.copyWith(
        nickname: '我的小虾',
        themeColor: '#FF0000',
        isPinned: true,
      );

      expect(updated.localId, original.localId);
      expect(updated.nickname, '我的小虾');
      expect(updated.themeColor, '#FF0000');
      expect(updated.isPinned, isTrue);
      expect(updated.name, original.name); // 未修改
    });
  });

  // US-021: Agent tombstone 状态。removed_at / hidden_at 由
  // DriftAgentRepo.syncFromGateway 通过 DB 独占写入（不经过 copyWith），
  // 此处只验证 domain 层的只读语义。
  group('Agent tombstone state (US-021)', () {
    Agent baseAgent() => Agent(
      localId: 'local-a1',
      remoteId: 'r1',
      instanceId: 'inst-001',
      name: '产品虾',
    );

    test('默认构造的 Agent 既未移除也未隐藏', () {
      final agent = baseAgent();
      expect(agent.removedAt, isNull);
      expect(agent.hiddenAt, isNull);
      expect(agent.isRemoved, isFalse);
      expect(agent.isHidden, isFalse);
    });

    test('removedAt 非空时 isRemoved 为 true', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      expect(agent.removedAt, 1719200000000);
      expect(agent.isRemoved, isTrue);
      expect(agent.isHidden, isFalse); // hiddenAt 仍 null
    });

    test('hiddenAt 非空时 isHidden 为 true', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        hiddenAt: 1719200000000,
      );
      expect(agent.hiddenAt, 1719200000000);
      expect(agent.isHidden, isTrue);
      expect(agent.isRemoved, isFalse); // removedAt 仍 null
    });

    test('removedAt 与 hiddenAt 可同时非空（正交状态）', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
        hiddenAt: 1719300000000,
      );
      expect(agent.isRemoved, isTrue);
      expect(agent.isHidden, isTrue);
    });

    test('copyWith 不暴露 removedAt/hiddenAt 参数，透传保留 tombstone 状态', () {
      // copyWith 故意不暴露 removedAt/hiddenAt（防 ?? old 清空坑，见 spec §3.3）。
      // 改其他字段时，tombstone 状态必须被透传保留。
      final tombstoned = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
        hiddenAt: 1719300000000,
      );

      final updated = tombstoned.copyWith(name: '改名后的虾');

      expect(updated.name, '改名后的虾');
      // tombstone 状态被透传，未被清空
      expect(updated.removedAt, 1719200000000);
      expect(updated.hiddenAt, 1719300000000);
      expect(updated.isRemoved, isTrue);
      expect(updated.isHidden, isTrue);
    });
  });

  // US-021 + Finding #7 (2026-06-27 重构): [operator ==] 退回 identity-only
  // （仅 localId），tombstone 状态不再参与 Set/Map dedup。Reactive dedup 的
  // 责任完全转移到 [contentEquals]：UI tombstone 转换路径（vm.agent.isRemoved
  // 从 false 翻 true）必须放行 Riverpod rebuild，否则 ChatRoom 占位页静默不显示。
  //
  // 两层 equality 的契约：
  // - [operator ==] / [hashCode] → identity-only，用于 Set/Map dedup。
  //   「同 localId = 同一 Agent」，tombstone 是 Agent 的属性而非身份。
  // - [contentEquals] → 全字段比对（含 tombstone / hidden），用于
  //   reactive dedup（[_setAgent] contentEquals 守卫 + Riverpod watch）。
  //   「同内容 = 应放行 UI rebuild」，nickname/themeColor/tombstone 变更必须检出。
  group('Agent equality (US-021 — operator == identity-only)', () {
    final alive = Agent(
      localId: 'local-a1',
      remoteId: 'r1',
      instanceId: 'inst-001',
      name: '产品虾',
    );

    test('Fix #7: 相同 localId 的 alive 与 tombstoned Agent 在 == 层相等', () {
      // tombstone 是 Agent 的属性，不是身份的一部分；Set/Map dedup
      // 不应因 tombstone 变化把「同一个 Agent」折叠或分裂。
      final tombstoned = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      expect(alive == tombstoned, isTrue);
      expect(tombstoned == alive, isTrue);
    });

    test('Fix #7: contentEquals 必须检出 alive → tombstoned 转换', () {
      // reactive dedup 的责任：占位页（vm.agent.isRemoved 翻 true）
      // 必须能驱动 Riverpod rebuild，否则 UI 静默不更新。
      final tombstoned = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      expect(alive.contentEquals(tombstoned), isFalse);
      expect(tombstoned.contentEquals(alive), isFalse);
    });

    test('Fix #7: 相同 localId 的 alive 与 hidden Agent 在 == 层相等', () {
      final hidden = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        hiddenAt: 1719300000000,
      );
      expect(alive == hidden, isTrue);
      expect(hidden == alive, isTrue);
    });

    test('Fix #7: contentEquals 必须检出 alive → hidden 转换', () {
      final hidden = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        hiddenAt: 1719300000000,
      );
      expect(alive.contentEquals(hidden), isFalse);
    });

    test('Fix #7: removedAt 不同不影响 == 但被 contentEquals 检出', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      final b = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000001,
      );
      expect(a == b, isTrue, reason: '同 localId，== 必相等（identity-only）');
      expect(a.contentEquals(b), isFalse, reason: 'contentEquals 必须检出');
    });

    test('Fix #7: hiddenAt 不同不影响 == 但被 contentEquals 检出', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        hiddenAt: 1719300000000,
      );
      final b = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        hiddenAt: 1719300000001,
      );
      expect(a == b, isTrue);
      expect(a.contentEquals(b), isFalse);
    });

    test('所有字段相同（含 tombstone 状态）的 Agent == 与 contentEquals 都相等', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
        hiddenAt: 1719300000000,
      );
      final b = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
        hiddenAt: 1719300000000,
      );
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a.contentEquals(b), isTrue);
    });

    test('Fix #7: Set 折叠 alive 与 tombstoned（identity-only 语义）', () {
      // 之前的版本期望 length == 2（即 tombstone 把 Set 分裂成两个元素）；
      // 现版本因为 == 是 identity-only，同 localId 的 alive 与 tombstoned
      // 在 Set 看来是「同一个 Agent」，length == 1。
      // tombstone 状态对外可观察的责任完全交给 contentEquals + vm.agent getter。
      final tombstoned = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      final set = {alive, tombstoned};
      expect(set.length, 1);
      expect(set.first, alive);
    });
  });

  // Fix #7 (2026-06-27): 守 operator == 与 hashCode 的 identity-only 契约。
  // 新增 Agent 字段时必须**不**改 == / hashCode（只改 contentEquals），
  // 否则会破坏 Set/Map dedup 的「同 localId = 同一 Agent」语义。
  group('Agent.operator == identity-only contract (Fix #7)', () {
    test('仅 localId 不同 → 不等', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      final b = Agent(
        localId: 'local-a2', // 仅 localId 不同
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      expect(a == b, isFalse);
    });

    test('所有其他字段不同但 localId 同 → 相等', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        nickname: '小虾',
        themeColor: '#6c5ce7',
        description: 'desc',
        isPinned: false,
      );
      final b = Agent(
        localId: 'local-a1', // 同 localId
        remoteId: 'r2', // 其他全不同
        instanceId: 'inst-002',
        name: '改名后',
        nickname: '改名',
        themeColor: '#FF0000',
        description: 'desc2',
        isPinned: true,
      );
      expect(a == b, isTrue);
    });

    test('hashCode 仅依赖 localId', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      final b = Agent(
        localId: 'local-a1',
        remoteId: 'r2',
        instanceId: 'inst-002',
        name: '改名后',
        removedAt: 1719300000000, // 不同的 tombstone 时间
      );
      expect(a.hashCode, b.hashCode);
    });

    test('identical(this, other) 走快速路径仍返回 true', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      expect(a == a, isTrue);
    });
  });

  // Finding #9 (2026-06-27 重构): extension on Agent? 把
  // `agent?.isRemoved ?? false` 模式统一抽到 domain 层。UI 调用方不再
  // 关心 nullable 兜底细节，统一用 `agent.isTombstoned` 即可。
  group('AgentTombstonedExt (Finding #9)', () {
    test('null → false（agent 未加载）', () {
      const Agent? a = null;
      expect(a.isTombstoned, isFalse, reason: 'null 与 "未删除" 同义');
    });

    test('alive (removedAt == null) → false', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      expect(a.isTombstoned, isFalse);
    });

    test('tombstoned (removedAt != null) → true', () {
      final a = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      expect(a.isTombstoned, isTrue);
    });

    test('等价于 `agent?.isRemoved ?? false` 旧模式', () {
      // 守护不变性：extension 替换 UI 三处调用后行为必须 100% 一致。
      Agent? makeAlive() => Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      Agent? makeTombstoned() => Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );

      expect(makeAlive().isTombstoned, equals(makeAlive()?.isRemoved ?? false));
      expect(
        makeTombstoned().isTombstoned,
        equals(makeTombstoned()?.isRemoved ?? false),
      );
      expect(
        (null as Agent?).isTombstoned,
        equals((null as Agent?)?.isRemoved ?? false),
      );
    });
  });

  // 2026-06-26 refactor: 引入 contentEquals 弥补 operator == 只比身份字段的盲区。
  // 当用户改昵称 / 主题色 / 快捷指令等"内容"字段时，operator == 仍然相等
  // （同 localId），导致 Riverpod dedup 抑制 UI rebuild。ChatViewModel 当前
  // 用 contentRevision 计数器（bumped by _setAgent post-contentEquals filter）
  // 驱动 ref.watch 重建；这里守护的 contentEquals 不变量是这条信号链可靠的前提。
  //
  // 这里守护 4 条不变量：
  //   1) operator == 保持身份-only 语义（不改）
  //   2) contentEquals 比所有用户可见字段
  //   3) operator == vs contentEquals 在内容变更场景下输出不同
  //   4) tombstone 状态翻转两边都检测
  group('Agent.contentEquals', () {
    Agent base({
      String nickname = '小虾',
      String avatarUrl = 'avatars/agent-a1.png',
      String themeColor = '#6c5ce7',
      List<QuickCommand>? quickCommands,
      int? createdAt,
      int? removedAt,
      int? hiddenAt,
    }) => Agent(
      localId: 'local-a1',
      remoteId: 'r1',
      instanceId: 'inst-001',
      name: '产品虾',
      nickname: nickname,
      avatarUrl: avatarUrl,
      themeColor: themeColor,
      quickCommands: quickCommands ?? const [],
      createdAt: createdAt ?? 1719000000,
      removedAt: removedAt,
      hiddenAt: hiddenAt,
    );

    test('不变量 1: operator == 对同身份不同内容返回 true（守住 == 不被改写）', () {
      // nickname 变了但 localId 没变 → == 应仍然 true（防 reviewer 误把 ==
      // 改成 contentEquals 后导致 Set/Map 折叠出问题）
      final a = base(nickname: '小虾');
      final b = base(nickname: '改名后的虾');
      expect(a == b, isTrue, reason: 'operator == 仍是身份-only；改动内容字段不应改变 ==');
    });

    test('不变量 2: contentEquals 对所有字段相同的两个 Agent 返回 true', () {
      final a = base();
      final b = base();
      expect(a.contentEquals(b), isTrue);
      expect(b.contentEquals(a), isTrue);
    });

    test('不变量 2: contentEquals 对 identical(this, other) 走快速路径', () {
      final a = base();
      expect(a.contentEquals(a), isTrue);
    });

    test('内容变更: nickname 差异应被 contentEquals 检出', () {
      final a = base(nickname: '小虾');
      final b = base(nickname: '改名后的虾');
      expect(a.contentEquals(b), isFalse);
    });

    test('内容变更: themeColor 差异应被 contentEquals 检出', () {
      final a = base(themeColor: '#6c5ce7');
      final b = base(themeColor: '#FF0000');
      expect(a.contentEquals(b), isFalse);
    });

    test('内容变更: avatarUrl 差异应被 contentEquals 检出', () {
      final a = base(avatarUrl: 'avatars/a.png');
      final b = base(avatarUrl: 'avatars/b.png');
      expect(a.contentEquals(b), isFalse);
    });

    test('内容变更: createdAt 差异应被 contentEquals 检出（避免 silent drift）', () {
      final a = base(createdAt: 1719000000);
      final b = base(createdAt: 1719000001);
      expect(a.contentEquals(b), isFalse);
    });

    test('内容变更: quickCommands 长度差异应被 contentEquals 检出', () {
      final a = base(quickCommands: const []);
      final b = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1',
            agentId: 'local-a1',
            label: '状态',
            payload: '/status',
          ),
        ],
      );
      expect(a.contentEquals(b), isFalse);
    });

    test('内容变更: quickCommands 元素 id 不同应被 contentEquals 检出', () {
      // 注: QuickCommand.== 只比 id（与 Agent.== 同种"身份-only"盲区）。
      // Agent.contentEquals 因此只能检出元素级 id 差异，无法检出同 id
      // 内部的 label/payload/sortOrder 变更——后者是 QuickCommand 的债，
      // 不在本次 Step 1 范围。
      final a = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1',
            agentId: 'local-a1',
            label: '状态',
            payload: '/status',
          ),
        ],
      );
      final b = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-2', // 不同 id → 元素不相等
            agentId: 'local-a1',
            label: '状态',
            payload: '/status',
          ),
        ],
      );
      expect(a.contentEquals(b), isFalse);
    });

    // Bug 1 修复回归测试: 同 id 不同 label 的 QuickCommand 必须被
    // Agent.contentEquals 检出 (否则 _setAgent 早退，ChatRoom 不 rebuild)。
    test('内容变更: quickCommands 同 id 不同 label 应被 contentEquals 检出 '
        '(Bug 1 fix regression)', () {
      final a = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1',
            agentId: 'local-a1',
            label: '状态',
            payload: '/status',
          ),
        ],
      );
      final b = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1', // 同 id
            agentId: 'local-a1',
            label: '健康检查', // 不同 label
            payload: '/status',
          ),
        ],
      );
      expect(
        a.contentEquals(b),
        isFalse,
        reason:
            'contentEquals 必须依赖 QuickCommand.contentEquals，而后者比较 label；'
            '否则 AgentConfigPage 改 label 后 ChatRoom 的 QuickCommandBar 不会 rebuild',
      );
    });

    test('内容变更: quickCommands 同 id 不同 payload 应被 contentEquals 检出 '
        '(Bug 1 fix regression)', () {
      final a = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1',
            agentId: 'local-a1',
            label: '状态',
            payload: '/status',
          ),
        ],
      );
      final b = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1', // 同 id
            agentId: 'local-a1',
            label: '状态',
            payload: '/health', // 不同 payload
          ),
        ],
      );
      expect(a.contentEquals(b), isFalse);
    });

    test('内容变更: quickCommands 同 id 不同 sortOrder 应被 contentEquals 检出 '
        '(Bug 1 fix regression)', () {
      final a = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1',
            agentId: 'local-a1',
            label: '状态',
            payload: '/status',
            sortOrder: 0,
          ),
        ],
      );
      final b = base(
        quickCommands: [
          QuickCommand(
            id: 'qc-1', // 同 id
            agentId: 'local-a1',
            label: '状态',
            payload: '/status',
            sortOrder: 5, // 不同 sortOrder
          ),
        ],
      );
      expect(a.contentEquals(b), isFalse);
    });

    test('不变量 3: 内容变更时 == 与 contentEquals 必须输出相反结果', () {
      // 关键不变量：nickname 变化后 operator == 仍 true（dedup 抑制 rebuild 是
      // 现有问题），但 contentEquals 返回 false（dedup 应该放行）。这两个不
      // 等式是修复方案的根本依据。
      final a = base(nickname: '小虾');
      final b = base(nickname: '改名后的虾');
      expect(a == b, isTrue, reason: 'operator == 应仍 true（身份未变）');
      expect(
        a.contentEquals(b),
        isFalse,
        reason: 'contentEquals 应 false（昵称已变）',
      );
    });

    test('不变量 4: removedAt 翻转（tombstone 转换）应被 contentEquals 检出', () {
      final alive = base();
      final tombstoned = base(removedAt: 1719200000000);
      expect(alive.contentEquals(tombstoned), isFalse);
      expect(tombstoned.contentEquals(alive), isFalse);
    });

    test('不变量 4: hiddenAt 翻转应被 contentEquals 检出', () {
      final visible = base();
      final hidden = base(hiddenAt: 1719300000000);
      expect(visible.contentEquals(hidden), isFalse);
    });
  });
}
