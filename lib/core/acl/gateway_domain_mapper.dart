import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';

/// Gateway 协议原始 JSON / 辅助字段 → 领域对象的纯映射器。
///
/// 职责：
/// - 解析 [Agent]、入站 [Message]
/// - 文本 / image 引用提取
/// - 时间戳归一化、枚举映射
/// - 从 streaming buffer 构建 fallback [Message]
///
/// 不包含任何 WebSocket / 连接 / 流生命周期逻辑；不依赖 ILogger。
class GatewayDomainMapper {
  final Uuid _uuid;

  GatewayDomainMapper({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// 解析 Gateway `agents.list` 响应中的单个 agent JSON。
  Agent parseAgent(Map<String, dynamic> json, String instanceId) {
    final remoteId = json['remoteId'] as String? ?? json['id'] as String? ?? '';
    final rawCommands = json['quickCommands'] as List<dynamic>?;
    final quickCommands = <QuickCommand>[];
    if (rawCommands != null) {
      for (var i = 0; i < rawCommands.length; i++) {
        final cmd = rawCommands[i] as Map<String, dynamic>;
        final label = cmd['label'] as String? ?? '';
        final payload = cmd['payload'] as String? ?? '';
        final commandId = cmd['id'] as String?;
        quickCommands.add(
          QuickCommand(
            id: commandId != null && commandId.isNotEmpty
                ? commandId
                : '$remoteId:$i:${label.trim()}:${payload.trim()}',
            agentId: remoteId,
            label: label,
            payload: payload,
            sortOrder: i,
          ),
        );
      }
    }

    // Agent name fallback chain:
    //   json['name'] → identity.name → id
    // Gateway 的默认 agent (如 "main") 通常没有 name 字段，
    // 只有 id，此时以 id 作为显示名（协议文档 §A.6 实测验证）。
    final identity = json['identity'] as Map<String, dynamic>?;
    String? nonEmpty(String? s) =>
        (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    final name =
        nonEmpty(json['name'] as String?) ??
        nonEmpty(identity?['name'] as String?) ??
        remoteId;

    // Agent description fallback chain:
    //   json['description'] → identity.theme → identity.description
    //
    // 真实 Gateway 的 agents.list API 不返回顶层 description（API 简化版，
    // 仅含路由必要字段）；配置 schema 支持 description（openclaw config get
    // agents.list 可查完整结构）。兜底到 identity.theme（部分 agent 的角色描述
    // 字段，jvsclaw/xinqing/zhishi 等已配）和 identity.description（未来字段
    // 预留）。**不再**回退到 identity.name —— identity.name 是 display name
    // （短名/昵称，如 "Bob"、"行远"），不是角色描述，回退会导致 name/description
    // 在 UI 上完全撞车。
    final description =
        nonEmpty(json['description'] as String?) ??
        nonEmpty(identity?['theme'] as String?) ??
        nonEmpty(identity?['description'] as String?);

    return Agent(
      localId: _uuid.v4(),
      remoteId: remoteId,
      instanceId: instanceId,
      name: name,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      themeColor: json['themeColor'] as String? ?? '#4F83FF',
      description: description,
      isPinned: json['isPinned'] == true,
      quickCommands: quickCommands,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }

  /// 解析入站或历史 [Message] JSON。
  Message parseMessage(Map<String, dynamic> json) {
    final role = _parseMessageRole(json['role'] as String?);
    // Bug #2 (重启错乱): 时间戳归一化为毫秒。Gateway 历史可能用秒级时间戳
    // (doc §5.4 示意图: 1718000000)；与本地消息(DateTime.now().ms, ~1.7e12)
    // 不同量级会导致软匹配 ±60s 永不命中 + 排序错乱。< 1e12 视为秒级(1e12 ms
    // ≈ 2001 年,任何真实毫秒时间戳都 >= 1e12),×1000 归一化。
    final timestamp = _normalizeEpochMs(json['timestamp'] as int?);
    // 响应侧图片捕获(PROTOCOL-VERIFY):入站 message 可能以下列任一形态携带图片,
    // 任一命中即提升 type=image 并把 imageUrl 写入 metadata(image-fix-spec.md §3
    // root cause):
    //   1. content/text 是结构化 blocks 且含 image block → [extractImageRef]
    //   2. OpenClaw 官方 payloads[].mediaUrl 字段
    //      (docs.openclaw.ai/cli/agent: payloads:[{text, mediaUrl}])
    //   3. metadata.imageUrl 独立存在(形态 4 兜底)
    // content 保留文本(作为图片说明);imagePath getter 靠 imageUrl==null 区分
    // 用户本地图 vs Agent 回图,故无需 null content。
    final textContent = extractTextContent(json['content']) ??
        extractTextContent(json['text']) ??
        _extractTextFromPayloads(json);
    final imageRef =
        extractImageRef(json['content']) ?? extractImageRef(json['text']);
    final parsedType = _parseMessageType(json['type'] as String?);

    // 提前构建 metadata(原在 type 判断之后,提前以读 metadata.imageUrl 兜底)。
    final incomingMetadata = json['metadata'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>)
        : <String, dynamic>{};

    // Phase 2 修复(image-fix-spec.md §4.2):从 OpenClaw 官方 payloads[] 提取
    // mediaUrl 写入 metadata。不读这个字段,Agent 回图 type='text' + content=null
    // 必然空白。优先级:imageRef > payloads[].mediaUrl > metadata.imageUrl。
    final payloadMediaUrl = _extractMediaUrlFromPayloads(json);
    if (payloadMediaUrl != null) {
      incomingMetadata['imageUrl'] = payloadMediaUrl;
    }

    // 类型提升:imageRef 命中 OR metadata.imageUrl 非空 → image。
    // toolCall 永不提升(保留工具调用语义)。
    final hasImageMetadata = incomingMetadata['imageUrl'] is String &&
        (incomingMetadata['imageUrl'] as String).isNotEmpty;
    final type = parsedType == MessageType.toolCall
        ? parsedType
        : (imageRef != null || hasImageMetadata
            ? MessageType.image
            : parsedType);

    // imageRef 命中时覆盖 metadata.imageUrl(保持原行为兼容:imageRef 优先级最高)。
    if (imageRef != null) {
      incomingMetadata['imageUrl'] = imageRef;
    }
    return Message(
      clientId: json['clientId'] as String? ?? _uuid.v4(),
      serverId: json['serverId'] as String? ?? json['id'] as String?,
      conversationId: json['conversationId'] as String? ?? '',
      agentId: json['agentId'] as String? ?? '',
      role: role,
      content: textContent,
      type: type,
      // Bug #1 (双对号): 入站消息按角色赋状态，不再一律 delivered。
      // 回传/历史中的 user 消息若被标 delivered，右下角会渲染双对号
      // (Icons.done_all)。user 消息最多到 sent（已送达网关）；delivered
      // 保留给 agent/system（已读/已处理）。
      status: role == MessageRole.user
          ? MessageStatus.sent
          : MessageStatus.delivered,
      // Bug #2: gateway 省略 logicalClock 时回退到「消息自身时间戳」(归一化),
      // 而非 DateTime.now()。旧实现让所有历史消息聚到重启时刻 → 错乱。
      // gateway 显式给的 logicalClock 保持原样(不二次猜测,向后兼容)。
      logicalClock:
          json['logicalClock'] as int? ??
          timestamp ??
          DateTime.now().millisecondsSinceEpoch,
      timestamp: timestamp,
      metadata: incomingMetadata.isEmpty ? null : incomingMetadata,
    );
  }

  /// Build a final [Message] from accumulated streaming buffer text.
  ///
  /// Shared by [chat.final] fallback and [agent.lifecycle.end] to avoid
  /// duplicating the 8-field Message literal. Both callers have already
  /// verified [agentId] is resolved (may be empty string if unresolvable)
  /// and [content] is non-empty.
  ///
  /// [conversationId] is intentionally left empty — the ChatViewModel
  /// normalises every message to the canonical SHA-256 hash via
  /// `msg.copyWith(conversationId: _conversationId)`.
  Message buildAgentFallbackMessage(String agentId, String content) => Message(
    clientId: _uuid.v4(),
    conversationId: '', // normalised by ChatViewModel
    agentId: agentId,
    role: MessageRole.agent,
    content: content,
    type: MessageType.text,
    status: MessageStatus.delivered,
    logicalClock: DateTime.now().millisecondsSinceEpoch,
  );

  /// 把可能是秒级的 epoch 时间戳归一化为毫秒。< 1e12 视为秒级(1e12 ms ≈ 2001 年)。
  /// null 透传(null)，由调用方决定兜底。
  int? _normalizeEpochMs(int? value) {
    if (value == null) return null;
    return value < 1000000000000 ? value * 1000 : value;
  }

  MessageRole _parseMessageRole(String? role) {
    return switch (role) {
      'agent' || 'assistant' => MessageRole.agent,
      'system' => MessageRole.system,
      _ => MessageRole.user,
    };
  }

  MessageType _parseMessageType(String? type) {
    return switch (type) {
      'image' => MessageType.image,
      'file' => MessageType.file,
      'tool_call' || 'toolCall' => MessageType.toolCall,
      _ => MessageType.text,
    };
  }

  /// Extract plain-text content from a Gateway message field.
  ///
  /// The Gateway may send `content` as a plain [String] or as structured
  /// content blocks (`List<Map>` with `type`/`text` keys, OpenAI-style).
  /// This method normalises both formats to a single [String] (or `null`).
  static String? extractTextContent(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    if (raw is List) {
      if (raw.isEmpty) return null; // [] → null, avoid '[]' literal in content
      // Structured content blocks: [{"type": "text", "text": "..."}, ...]
      // Join all text-type blocks with empty separator.
      if (raw.first is Map) {
        return (raw)
            .whereType<Map<String, dynamic>>()
            .where((b) => b['type'] == 'text')
            .map((b) => (b['text'] as String?) ?? '')
            .join();
      }
      // Simple string list: ["a", "b"]
      // Note: null entries are filtered by whereType<String>();
      // empty strings silently contribute nothing to join('').
      return (raw).whereType<String>().join();
    }
    return raw.toString();
  }

  /// PROTOCOL-VERIFY (appendix F.5, 2026-07-03): chat.history 响应的 image block
  /// 实测形态是 `{"type":"image","url":"..."}`(url 在 block 根)。同时防御性兼容
  /// OpenAI `image_url` 嵌套形态。用于 [parseMessage] 提升入站消息为 image 类型 +
  /// 写 metadata.imageUrl,让 UI 渲染 Agent 回图。
  static String? extractImageRef(dynamic raw) {
    if (raw is! List) return null;
    for (final block in raw) {
      if (block is! Map<String, dynamic>) continue;
      if (block['type'] == 'image_url') {
        final url = (block['image_url'] as Map?)?['url'];
        if (url is String && url.isNotEmpty) return url;
      } else if (block['type'] == 'image') {
        // F.5 实测:url 直接在 block 根。
        final url = block['url'];
        if (url is String && url.isNotEmpty) return url;
        // 防御性兼容:嵌套在 image:{url}(未见实测,但 extractTextContent 旧测试用过)。
        final img = block['image'];
        if (img is Map) {
          final innerUrl = img['url'];
          if (innerUrl is String && innerUrl.isNotEmpty) return innerUrl;
        }
      }
    }
    return null;
  }

  /// Phase 2 修复(image-fix-spec.md §4.2.1):从 OpenClaw 官方 `payloads[]` 提取
  /// 第一个非空 `mediaUrl`。
  ///
  /// OpenClaw CLI/agent 协议(docs.openclaw.ai/cli/agent):
  ///   payloads: [{text, mediaUrl}, ...]
  /// Agent 回图时 mediaUrl 携带 data: URL 或 https URL。原 parseMessage 只看
  /// content blocks(imageRef),漏掉此字段 → type='text' + content=null → 空白。
  static String? _extractMediaUrlFromPayloads(dynamic json) {
    final payloads = json is Map ? json['payloads'] : null;
    if (payloads is! List) return null;
    for (final p in payloads) {
      if (p is Map && p['mediaUrl'] is String) {
        final url = (p['mediaUrl'] as String).trim();
        if (url.isNotEmpty && url != 'null') return url;
      }
    }
    return null;
  }

  /// Phase 2 修复:从 `payloads[]` 拼接非空 `text` 作为 content 兜底。
  ///
  /// OpenClaw payloads 形态每个元素含 {text, mediaUrl};当顶层 content 为 null
  /// 时,文字描述(图片说明)在 payloads[].text。与 [extractTextContent] 的
  /// block 拼接风格一致(空分隔符 join)。
  static String? _extractTextFromPayloads(dynamic json) {
    final payloads = json is Map ? json['payloads'] : null;
    if (payloads is! List) return null;
    final texts = <String>[];
    for (final p in payloads) {
      if (p is Map && p['text'] is String) {
        final t = p['text'] as String;
        if (t.isNotEmpty) texts.add(t);
      }
    }
    return texts.isEmpty ? null : texts.join();
  }
}
