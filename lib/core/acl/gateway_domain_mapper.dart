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
    // 注意顺序:必须先抽到 textContent 才能识别 user 上传文件占位,否则
    // _parseMessageRole 拿不到 content 也识别不出来。末尾兜底 payloads[].text
    // (Agent 回图时图片说明可能在 payloads 里,见下文 image 捕获)。
    final rawText =
        extractTextContent(json['content']) ??
        extractTextContent(json['text']) ??
        _extractTextFromPayloads(json);
    final role = _parseMessageRole(json['role'] as String?, content: rawText);
    // Bug #2 (重启错乱): 时间戳归一化为毫秒。Gateway 历史可能用秒级时间戳
    // (doc §5.4 示意图: 1718000000)；与本地消息(DateTime.now().ms, ~1.7e12)
    // 不同量级会导致软匹配 ±60s 永不命中 + 排序错乱。< 1e12 视为秒级(1e12 ms
    // ≈ 2001 年,任何真实毫秒时间戳都 >= 1e12),×1000 归一化。
    final timestamp = _normalizeEpochMs(json['timestamp'] as int?);
    final textContent = rawText;
    // 响应侧图片捕获(PROTOCOL-VERIFY):入站 message 可能以下列任一形态携带图片,
    // 任一命中即提升 type=image 并把 imageUrl 写入 metadata。优先级:
    //   imageRef(含 attachment) > payloads[].mediaUrl > metadata.imageUrl
    //   1. content/text 结构化 blocks 含 image / image_url / attachment block
    //      → [extractImageRef](attachment 形态见
    //      docs/technical/openclaw-media-protocol.md §4.2:gateway 解析 MEDIA:
    //      指令后 emit {type:attachment, attachment:{url, kind, mimeType}})
    //   2. payloads[].mediaUrl(防御兜底,待 wire 捕获确认,no-op 安全)
    //   3. metadata.imageUrl 独立存在(兜底)
    // content 保留文本(作为图片说明);imagePath getter 靠 imageUrl==null 区分
    // 用户本地图 vs Agent 回图,故无需 null content。
    final imageRef =
        extractImageRef(json['content']) ?? extractImageRef(json['text']);
    final parsedType = _parseMessageType(json['type'] as String?);
    // 提前构建 metadata:payloads 兜底要写入 imageUrl,且 type 提升要读它。
    final incomingMetadata = json['metadata'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final payloadMediaUrl = _extractMediaUrlFromPayloads(json);
    if (payloadMediaUrl != null) {
      incomingMetadata['imageUrl'] = payloadMediaUrl;
    }
    // 类型提升:imageRef 命中 OR metadata.imageUrl 非空 → image。
    // toolCall 永不提升(保留工具调用语义,由 MessageBubble._buildToolResult 渲染)。
    final hasImageMetadata =
        incomingMetadata['imageUrl'] is String &&
        (incomingMetadata['imageUrl'] as String).isNotEmpty;
    final type = parsedType == MessageType.toolCall
        ? parsedType
        : ((imageRef != null || hasImageMetadata)
              ? MessageType.image
              : parsedType);
    // imageRef 命中时覆盖 metadata.imageUrl(优先级最高,含 attachment)。
    if (imageRef != null) {
      incomingMetadata['imageUrl'] = imageRef;
    }
    // Capture-verified (2026-07-05, OpenClaw v2026.6.10): toolResult / 上传占位消息把
    // toolName / toolCallId / isError / MediaPaths 放在**顶层字段**,不在 metadata
    // 对象里(消息本身也没有 metadata 字段)。这里提取到 incomingMetadata,供
    // MessageBubble._buildToolResult / _buildPlaceholder 通过 message.metadata 读取。
    // 详见 memory openclaw-v2026-6-10-wire-format。
    final toolName = json['toolName'];
    if (toolName is String && toolName.isNotEmpty) {
      incomingMetadata['toolName'] = toolName;
    }
    final toolCallId = json['toolCallId'];
    if (toolCallId is String && toolCallId.isNotEmpty) {
      incomingMetadata['toolCallId'] = toolCallId;
    }
    final isError = json['isError'];
    if (isError is bool) {
      incomingMetadata['isError'] = isError;
    }
    // MediaPaths(大写 M,顶层 List)→ mediaPaths(供 _buildPlaceholder 数份数)。
    // 兼容单数 MediaPath(字符串)——UI 的 `rawPaths is List` 判断会兜成 1 份。
    final mediaPaths = json['MediaPaths'] ?? json['MediaPath'];
    if (mediaPaths != null) {
      incomingMetadata['mediaPaths'] = mediaPaths;
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

  MessageRole _parseMessageRole(String? role, {String? content}) {
    // 工具调用结果:不归到 user,归到独立 role.MessageBubble 按 role 分支渲染
    // 折叠卡 (⌨ exec · 0.02s),而不再画成「用户发的」黄色右气泡 —— 即
    // 用户在 openclaw-android 客户端反馈的「图 3」bug 修复点。
    if (role == 'toolResult' ||
        role == 'tool_result' ||
        role == 'toolCall' ||
        role == 'tool_call') {
      return MessageRole.toolResult;
    }
    // 用户上传文件时,OpenClaw 协议自动插入一条 user message,但 body 是固定的
    // 占位文本,从语义上「不是用户打字的输入」,不该占 user 气泡。在 ACL 层
    // 识别出来归到 userPlaceholder,UI 折叠成「📎 1 个文件已上传」小条。
    //
    // PROTOCOL-VERIFY (capture 2026-07-05, OpenClaw v2026.6.10): 真机实测确认
    // 上传占位消息的 body 就是这个固定字符串,且顶层带 MediaPath/MediaPaths/
    // MediaType/MediaTypes。⚠️ 若 OpenClaw 改文案/做多语言,此匹配会静默失效 →
    // 占位回退成 user 黄气泡(原 bug 复现)。改文案时需同步更新此处 + 测试。
    // 详见 memory openclaw-v2026-6-10-wire-format。
    const mediaPlaceholder = '[User sent media without caption]';
    if (role == 'user' && content?.trim() == mediaPlaceholder) {
      return MessageRole.userPlaceholder;
    }
    return switch (role) {
      'agent' || 'assistant' => MessageRole.agent,
      'user' => MessageRole.user,
      'system' => MessageRole.system,
      // 未知 role 字符串兜到 system(渲染为空)而不是 user(黄气泡)——
      // 这是本 fix 真正要堵的口:下一个未识别的 role 不再冒充用户输入。
      _ => MessageRole.system,
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
      } else if (block['type'] == 'attachment') {
        // PROTOCOL-VERIFY (docs/technical/openclaw-media-protocol.md §4.2):
        // Agent 回图经 gateway 解析 MEDIA: 指令后 emit 的 attachment block:
        //   {type:attachment, attachment:{url, kind:'image', label, mimeType}}
        // url 通常是 /__openclaw__/assistant-media?... 相对路径(UI 需拼 gateway
        // host,本层只负责提取)。kind=='image' 才算图片;kind 缺省时也尝试(防御,
        // 部分形态可能省略 kind 字段)。
        final att = block['attachment'];
        if (att is Map) {
          final kind = att['kind'];
          if (kind == 'image' || kind == null) {
            final url = att['url'];
            if (url is String && url.isNotEmpty) return url;
          }
        }
      }
    }
    return null;
  }

  /// 防御兜底(PROTOCOL-VERIFY-PENDING):从 `payloads[]` 提取第一个非空 `mediaUrl`。
  ///
  /// docs/technical/openclaw-media-protocol.md §4.2 记录的 Agent 回图主路径是
  /// attachment block;payloads:[{text, mediaUrl}] 是另一疑似形态,待 wire 捕获
  /// 确认。字段不存在时返回 null(no-op 安全,不会破坏现有行为)。
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

  /// 防御兜底:从 `payloads[]` 拼接非空 `text` 作为 content 兜底。
  ///
  /// 与 [extractTextContent] 的 block 拼接风格一致(空分隔符 join)。当顶层
  /// content 为 null 而图片说明在 payloads[].text 时使用。
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
