import '../models/enums.dart';
import '../models/message.dart';

/// 消息聚簇去重器 — 纯 domain 逻辑，无 IO。
///
/// Bug #2 修复的两条路径（实时合并 + 历史回填去重）共用同一聚簇规则：
/// - 同 (role, content) 才视为候选
/// - 相邻时间戳间隔 ≤ [softMatchWindowMs] 视为同一簇
/// - 每簇保留一条 keeper（优先有 serverId 的，其次最早 logicalClock），其余删
///
/// 抽取此类的动机：Drift/InMemory 两份仓库各自实现了 ~70 行近乎相同的聚簇代码，
/// 三处重复声明 [softMatchWindowMs] 常量。任一处改动必须同步另外两处 —— 这是
/// 真实存在的耦合风险（参见 review 反馈）。
class MessageClusterDeduper {
  const MessageClusterDeduper._();

  /// 软匹配时间窗口（毫秒）。同一消息的本地发送时间与网关时间戳通常在几秒内
  /// 对齐（网络 RTT + 处理）；±60s 容忍客户端/网关时钟漂移，同时把"相距较久
  /// 的相同内容"识别为不同消息。
  static const int softMatchWindowMs = 60000;

  /// 归一化消息内容用于**去重比较**：移除所有空白字符（空格/换行/制表符等）。
  ///
  /// 背景：同一条 agent 回复经不同事件路径（`chat.final` / `session.message` /
  /// `chat.history`）解析时，`GatewayDomainMapper.extractTextContent` 对 String
  /// vs 结构化 content blocks 的拼接可能产生换行/空白差异 -- 例如一段回复被存成
  /// 两行，一行在句间保留 `\n`、另一行没有。精确字符串比较会把它们误判为不同
  /// 消息 -> 身份去重（serverId 也常不同）miss、软匹配 miss、聚簇 miss -> 重载
  /// 时同一回复渲染成两个气泡（用户 2026-07-11 真机复现）。
  ///
  /// 归一化后只差空白的两条内容视为相同，供 [plan] 聚簇与
  /// `MergeInboundMessageUseCase._softMatch` 软匹配使用。
  ///
  /// **仅用于去重比较，绝不改变展示内容** -- 展示仍用原始 `content`（保留换行
  /// 可读性）。中文内容无词间空格，移除空白无损语义；英文场景下两条仅空白差异
  /// 的消息本就是重复，误合并风险可忽略，且受 ±60s 窗口 + 同 role 约束。
  static String normalizeContentForDedup(String? content) {
    if (content == null) return '';
    return content.replaceAll(RegExp(r'\s+'), '');
  }

  /// 给定会话内全部消息，规划应删除的 `clientId` 集合（聚簇去重 + 空 text 清理）。
  ///
  /// 返回空 Set 表示无重复 —— 调用方可直接跳过后续删除事务。
  ///
  /// 算法：
  /// 1. 空 content 的 text 消息（空气泡）一律删除 —— 无展示价值。
  /// 2. 其余 text 消息按 (role, content) 分组。
  /// 3. 组内按 timestamp 升序，相邻 ≤ [softMatchWindowMs] 视为同一簇。
  /// 4. 每簇保留一条 keeper（优先有 serverId 的，其次最早 logicalClock），其余
  ///    加入删除集合。簇长 < 2 不动。
  /// 5. 非 text 消息（如 tool_call / image）不参与 —— 无法安全按内容聚簇。
  static Set<String> plan(List<Message> all) {
    final doomed = <String>{};

    // 收集：空 content text 消息 + 参与聚簇的非空 text 消息。
    // toolResult 角色的空 content 不清理：stdout 为空的 shell 命令(cp/mv 等)
    // 仍需要保留行以展示工具执行记录(toolName/status)。
    final textByKey = <String, List<Message>>{};
    for (final m in all) {
      if (m.type != MessageType.text) continue;
      if (m.role != MessageRole.toolResult &&
          (m.content == null || m.content!.isEmpty)) {
        doomed.add(m.clientId);
        continue;
      }
      final key = '${m.role.toInt()}|${normalizeContentForDedup(m.content)}';
      (textByKey[key] ??= <Message>[]).add(m);
    }

    for (final group in textByKey.values) {
      if (group.length < 2) continue;

      group.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Pairwise-vs-first 拓扑：每条消息与「聚簇起点」(|Δ|≤windowMs) 才视为
      // 同一簇。修复链式相邻 bug —— 链式会把 t=0/t=30/t=90 全部并入一个聚簇
      // （即便首尾跨度 90s > 60s 窗口），错误删除合法独立消息。
      // 与 MergeInboundMessageUseCase._softMatch 的 pairwise 语义保持一致。
      final clusters = <List<Message>>[
        <Message>[group.first],
      ];
      for (var i = 1; i < group.length; i++) {
        final anchor = clusters.last.first;
        if ((group[i].timestamp - anchor.timestamp).abs() <=
            softMatchWindowMs) {
          clusters.last.add(group[i]);
        } else {
          clusters.add(<Message>[group[i]]);
        }
      }

      for (final cluster in clusters) {
        if (cluster.length < 2) continue;
        cluster.sort(_keeperOrder);
        final keeper = cluster.first;
        for (final m in cluster) {
          if (m.clientId != keeper.clientId) doomed.add(m.clientId);
        }
      }
    }

    return doomed;
  }

  /// Keeper 选择顺序：有 serverId 的优先，其次最早 logicalClock（确定性）。
  static int _keeperOrder(Message a, Message b) {
    final aHasId = (a.serverId != null && a.serverId!.isNotEmpty) ? 0 : 1;
    final bHasId = (b.serverId != null && b.serverId!.isNotEmpty) ? 0 : 1;
    if (aHasId != bHasId) return aHasId - bHasId;
    return a.logicalClock.compareTo(b.logicalClock);
  }
}
