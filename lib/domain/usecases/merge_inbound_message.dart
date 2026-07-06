import '../models/models.dart';
import '../repositories/repositories.dart';
import 'message_cluster_deduper.dart';

/// 入站消息合并用例（Bug #2 根因修复）。
///
/// 背景：网关不给"本地已发的 user 消息"与"历史/实时回传的同一条 user 消息"
/// 提供任何共享稳定身份——`chat.send` 响应里没有 message id（只有 runId），
/// `chat.history` 回传的消息用网关自己的 `id`，而 `clientId`（idempotencyKey）
/// 网关并不回传（实测，见 protocol-doc-reality-gap）。本地 user 消息的
/// `serverId` 被填成了 runId/随机 UUID，与历史回传的 `serverId` 永不相等。
///
/// 后果：每次重启拉历史，"我发过的消息"会被当成新消息再插一行（新 clientId、
/// 新 serverId、不同 logicalClock）→ 重复 + 错乱 + 游标分页被搅乱（看起来像丢失）。
///
/// 修法：入站消息（实时流 + 历史拉取两条路径）统一走 [merge]，按优先级去重：
///   1. clientId 命中（网关若回传 idempotencyKey）→ 返回本地行
///   2. serverId 命中（agent 消息稳态去重，已有效）→ 返回本地行
///   3. **user 消息软匹配**：`content 相同 + 时间戳 ±60s + role=user`
///      —— clientId 不回传时的兜底，没有它 user 消息去重就是空转
///   4. 都不命中 → [IMessageRepo.insert]（多设备来的真新消息仍保留）
///
/// 软匹配的 ±60s 窗口同时是"连续两条相同内容"的护栏：相距 >60s 的相同内容
/// 视为两条不同消息，分别插入，避免错误合并。
class MergeInboundMessageUseCase {
  final IMessageRepo _messageRepo;

  MergeInboundMessageUseCase({required this._messageRepo});

  /// 软匹配时间窗口（毫秒）。同一消息的本地发送时间与网关时间戳通常在几秒内
  /// 对齐（网络 RTT + 处理）；±60s 容忍客户端/网关时钟漂移，同时把"相距较久
  /// 的相同内容"识别为不同消息。
  ///
  /// 常量定义在 [MessageClusterDeduper.softMatchWindowMs]，本类与
  /// `dedupeConversation` 共用同一窗口，避免三处重复声明。
  static const int softMatchWindowMs = MessageClusterDeduper.softMatchWindowMs;

  /// 合并一条入站消息：命中已有行则返回该行（不重复入库），否则插入。
  ///
  /// [softMatch] 控制是否启用内容+时间戳软匹配（第 3 步，需查会话近期消息）。
  /// - **历史拉取路径**传 `true`（默认）：历史会回传本地已存的 user/agent 消息，
  ///   身份(clientId/serverId)对不上时靠软匹配兜底去重 —— 这是 Bug #2 的核心。
  /// - **实时流路径**传 `false`：实时消息是 gateway 刚产生的新消息（实测网关
  ///   不在实时流回传本地已发消息，故重复只在重启后出现），只需身份去重(1/2步)
  ///   防止重传即可，跳过昂贵的会话查询 —— 也避免快速连发消息触发 N 次
  ///   getByConversation,破坏 ChatViewModel 的 reload 合并。
  ///
  /// 返回值即为应当展示的消息实体（已有行或新插入行）。
  Future<Message> merge(Message inbound, {bool softMatch = true}) async =>
      (await mergeWithStatus(inbound, softMatch: softMatch)).message;

  /// 与 [merge] 相同，但额外返回 [MergeResult.wasNew]：true 表示这条消息是
  /// 真新插入的，false 表示命中已有行（身份或软匹配去重）。
  ///
  /// [MessageCatchUpService] 用 `wasNew` 判断"是否已追平"——当一页中出现过
  /// 命中(wasNew=false)时，说明本地已拥有该页消息，停止翻页。
  ///
  /// [recent]: 软匹配用的近期消息列表。批量入站(如 catch-up 一页 50 条)时,
  /// 调用方应在循环外预取一次传入,避免每条都触发 `getByConversation`——
  /// 50 条 × 50 limit = 50 次相同查询。`null` 表示由本用例自行查询。
  Future<MergeResult> mergeWithStatus(
    Message inbound, {
    bool softMatch = true,
    List<Message>? recent,
  }) async {
    // 0. 空内容 text 消息不入库(但 toolResult 除外)。
    //    网关历史/实时回传的空 text 消息(典型: agent 这一轮只有 tool_call,
    //    无文本回复,网关存了空 text 行)无展示价值 —— 显示为空气泡。
    //    入站直接丢弃。用户主动发的空消息走 SendMessageUseCase.insert(不经
    //    merge),不受影响,保留用户意图。
    //    toolResult 角色即使 content 为空也必须保留:它携带工具执行记录
    //    (toolName/status 在 metadata 里),跳过会导致历史里丢失该工具存在。
    //    标记 wasSkipped=true,让 MessageCatchUpService 不把空内容计入
    //    pageKnown,避免误触发「已追平」停止条件导致真实新消息被丢。
    if (inbound.type == MessageType.text &&
        inbound.role != MessageRole.toolResult &&
        (inbound.content == null || inbound.content!.isEmpty)) {
      return MergeResult(message: inbound, wasNew: false, wasSkipped: true);
    }

    // 1. clientId 身份去重（网关回传 idempotencyKey 时命中）。
    if (inbound.clientId.isNotEmpty) {
      final byClient = await _messageRepo.getByClientId(inbound.clientId);
      if (byClient != null) {
        return MergeResult(message: byClient, wasNew: false);
      }
    }

    // 2. serverId 身份去重（agent 消息稳态去重；user 消息因本地 serverId 是
    //    runId/随机 UUID 而通常不命中，交给第 3 步软匹配兜底）。
    final serverId = inbound.serverId;
    if (serverId != null && serverId.isNotEmpty) {
      final byServer = await _messageRepo.getByServerId(serverId);
      if (byServer != null) {
        return MergeResult(message: byServer, wasNew: false);
      }
    }

    // 3. 内容+时间戳软匹配（所有角色，仅历史路径启用）。
    //    实时 chat.final 事件的 message 对象通常没有 id → 实时 agent 消息以
    //    serverId=null 入库；重启后 history 回传同一条 agent 消息(带 gateway
    //    id)→ 身份去重全部 miss → agent 回复每次重启都重复。故历史路径的
    //    软匹配必须覆盖所有角色。
    if (softMatch && inbound.conversationId.isNotEmpty) {
      final recentSnapshot =
          recent ??
          await _messageRepo.getByConversation(
            inbound.conversationId,
            limit: 50,
          );
      final match = _softMatch(inbound, recentSnapshot);
      if (match != null) {
        return MergeResult(message: match, wasNew: false);
      }
    }

    // 4. 真新消息 → 入库。
    final inserted = await _messageRepo.insert(inbound);
    return MergeResult(message: inserted, wasNew: true);
  }

  /// 在近期消息中找一条与 [inbound] 内容相同、时间戳在窗口内、同角色的
  /// 本地消息。多条命中时取时间戳最接近者。返回 null 表示无匹配。
  ///
  /// 同角色过滤避免"用户发的'好的'"与"agent 回的'好的'"被错误合并。
  Message? _softMatch(Message inbound, List<Message> candidates) {
    Message? best;
    var bestDelta = 0x7FFFFFFFFFFFFFFF; // int.maxValue
    for (final m in candidates) {
      if (m.role != inbound.role) continue;
      if (m.content != inbound.content) continue;
      final delta = (m.timestamp - inbound.timestamp).abs();
      if (delta > MessageClusterDeduper.softMatchWindowMs) continue;
      if (delta < bestDelta) {
        bestDelta = delta;
        best = m;
      }
    }
    return best;
  }
}

/// [MergeInboundMessageUseCase.mergeWithStatus] 的返回值。
///
/// [wasNew] 为 true 表示这条入站消息是真新插入的；false 表示命中本地已有行
/// （身份去重或软匹配），未产生新行。调用方（如 [MessageCatchUpService]）可
/// 据此判断同步进度。
///
/// [wasSkipped] 为 true 表示这条消息因业务规则被显式丢弃（如空内容 text
/// 不入库）。与「命中已有行」区分：skipped 不应触发 catch-up 的「已追平」
/// 停止条件 —— Bug #1 修复。
class MergeResult {
  final Message message;
  final bool wasNew;
  final bool wasSkipped;

  const MergeResult({
    required this.message,
    required this.wasNew,
    this.wasSkipped = false,
  });
}
