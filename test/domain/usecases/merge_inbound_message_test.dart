import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/usecases/merge_inbound_message.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';

class MockMessageRepo extends Mock implements IMessageRepo {}

void main() {
  late MergeInboundMessageUseCase useCase;
  late MockMessageRepo messageRepo;

  setUpAll(() {
    registerFallbackValue(
      Message(
        clientId: 'fallback',
        conversationId: 'conv-fallback',
        agentId: 'agent-fallback',
        role: MessageRole.user,
        content: 'fallback',
        type: MessageType.text,
        logicalClock: 0,
      ),
    );
    registerFallbackValue(MessageType.text);
  });

  setUp(() {
    messageRepo = MockMessageRepo();
    useCase = MergeInboundMessageUseCase(messageRepo: messageRepo);
  });

  Message inbound({
    String clientId = 'inbound-1',
    String? serverId = 'srv-1',
    String conversationId = 'conv-1',
    String agentId = 'agent-1',
    MessageRole role = MessageRole.agent,
    String content = 'hi',
    int timestamp = 1718000000000,
    int logicalClock = 100,
  }) => Message(
    clientId: clientId,
    serverId: serverId,
    conversationId: conversationId,
    agentId: agentId,
    role: role,
    content: content,
    type: MessageType.text,
    status: role == MessageRole.user
        ? MessageStatus.sent
        : MessageStatus.delivered,
    timestamp: timestamp,
    logicalClock: logicalClock,
  );

  Message local({
    String clientId = 'local-1',
    String? serverId,
    String conversationId = 'conv-1',
    String agentId = 'agent-1',
    MessageRole role = MessageRole.user,
    String content = 'hi',
    int timestamp = 1718000000000,
    int logicalClock = 99,
  }) => Message(
    clientId: clientId,
    serverId: serverId,
    conversationId: conversationId,
    agentId: agentId,
    role: role,
    content: content,
    type: MessageType.text,
    status: MessageStatus.sent,
    timestamp: timestamp,
    logicalClock: logicalClock,
  );

  group('MergeInboundMessageUseCase.merge', () {
    // -------------------------------------------------------------------------
    // Identity dedup — agent message with existing serverId
    // -------------------------------------------------------------------------
    test(
      'agent message whose serverId already exists returns existing (no insert)',
      () async {
        final msg = inbound(role: MessageRole.agent, serverId: 'srv-1');
        final existing = local(
          clientId: 'local-agent',
          serverId: 'srv-1',
          role: MessageRole.agent,
          content: 'reply',
        );
        when(
          () => messageRepo.getByClientId('inbound-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('srv-1'),
        ).thenAnswer((_) async => existing);

        final result = await useCase.merge(msg);

        expect(result.clientId, 'local-agent', reason: '应返回已存在行，而非新插入');
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    // -------------------------------------------------------------------------
    // Identity dedup — clientId match (gateway echoes idempotencyKey)
    // -------------------------------------------------------------------------
    test(
      'message whose clientId matches a local row returns existing (no insert)',
      () async {
        final msg = inbound(clientId: 'shared-cid', role: MessageRole.user);
        final existing = local(clientId: 'shared-cid', serverId: null);
        when(
          () => messageRepo.getByClientId('shared-cid'),
        ).thenAnswer((_) async => existing);

        final result = await useCase.merge(msg);

        expect(result.clientId, 'shared-cid');
        verifyNever(() => messageRepo.getByServerId(any()));
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    // -------------------------------------------------------------------------
    // Genuinely new agent message → insert
    // -------------------------------------------------------------------------
    test('agent message with no match is inserted', () async {
      final msg = inbound(role: MessageRole.agent, serverId: 'srv-new');
      when(
        () => messageRepo.getByClientId('inbound-1'),
      ).thenAnswer((_) async => null);
      when(
        () => messageRepo.getByServerId('srv-new'),
      ).thenAnswer((_) async => null);
      // 软匹配对所有角色生效(见 Bug #2 agent 重复修复),故 agent 也会查会话。
      when(
        () =>
            messageRepo.getByConversation('conv-1', limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

      final result = await useCase.merge(msg);

      expect(result, msg);
      verify(() => messageRepo.insert(any())).called(1);
    });

    // -------------------------------------------------------------------------
    // Bug #2 (agent 重复): 实时 chat.final 事件的 message 对象通常没有
    // id/serverId → 实时 agent 消息以 serverId=null + 随机 clientId 入库。
    // 重启后 chat.history 回传同一条 agent 消息(带 gateway id) → 身份去重全部
    // miss(serverId 不等、clientId 随机)→ 必须靠内容+时间戳软匹配兜底。
    // 旧实现软匹配只对 role=user 生效,agent 消息直接落库 → 每次重启 agent
    // 回复都重复。修法: 软匹配对所有角色生效。
    // -------------------------------------------------------------------------
    test(
      'agent message with null serverId soft-matches local agent by content+timestamp',
      () async {
        final msg = inbound(
          clientId: 'history-cid-agent',
          serverId: null, // 实时入库时无 id
          role: MessageRole.agent,
          content: '这是 agent 的回复',
          timestamp: 1718000000000,
        );
        // 本地实时入库的同一 agent 回复: serverId=null, clientId=随机。
        final existingLocal = local(
          clientId: 'local-agent-uuid',
          serverId: null,
          role: MessageRole.agent,
          content: '这是 agent 的回复',
          timestamp: 1718000003000, // +3s, 在 ±60s 窗口内
        );
        when(
          () => messageRepo.getByClientId('history-cid-agent'),
        ).thenAnswer((_) async => null);
        // serverId 为 null → 不查 getByServerId。
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [existingLocal]);

        final result = await useCase.merge(msg);

        expect(
          result.clientId,
          'local-agent-uuid',
          reason: 'agent 回复也应按内容+时间戳软匹配,否则每次重启都重复。',
        );
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    // -------------------------------------------------------------------------
    // agent 软匹配护栏: 内容相同但时间戳超出窗口 → 视为不同回复 → 插入
    // -------------------------------------------------------------------------
    test(
      'agent message with same content but timestamp outside window is inserted',
      () async {
        final msg = inbound(
          clientId: 'history-cid-agent-2',
          serverId: null,
          role: MessageRole.agent,
          content: '好的',
          timestamp: 1718000000000,
        );
        final existingLocal = local(
          clientId: 'local-agent-uuid-2',
          serverId: null,
          role: MessageRole.agent,
          content: '好的',
          timestamp: 1718000000000 + 120000, // +120s, 超出 ±60s
        );
        when(
          () => messageRepo.getByClientId('history-cid-agent-2'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [existingLocal]);
        when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

        final result = await useCase.merge(msg);

        expect(result, msg);
        verify(() => messageRepo.insert(any())).called(1);
      },
    );

    // -------------------------------------------------------------------------
    // 空白归一化软匹配：同一条 agent 回复经不同事件路径解析时，String vs
    // 结构化 blocks 拼接可能产生换行差异。serverId 不同 -> 身份去重 miss；
    // 内容只差 \n -> 精确软匹配也 miss -> 插入重复行 -> 重载渲染成两个气泡
    // （用户 2026-07-11 真机复现）。归一化后软匹配命中，不重复入库。
    // -------------------------------------------------------------------------
    test(
      'agent message whose content differs only by whitespace soft-matches existing',
      () async {
        final msg = inbound(
          clientId: 'history-cid',
          serverId: 'srv-new', // 与本地行 serverId 不同 -> byServer miss
          role: MessageRole.agent,
          content: '让我先查一下记录。乐哥，老实说没有记忆。', // 无换行
          timestamp: 1718000000000,
        );
        final existingLocal = local(
          clientId: 'local-agent',
          serverId: 'srv-old',
          role: MessageRole.agent,
          content: '让我先查一下记录。\n乐哥，老实说没有记忆。', // 有换行
          timestamp: 1718000003000, // +3s, 在 ±60s 窗口内
        );
        when(
          () => messageRepo.getByClientId('history-cid'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('srv-new'),
        ).thenAnswer((_) async => null); // 身份 miss
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [existingLocal]);
        when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

        final result = await useCase.merge(
          msg,
        ); // softMatch=true (history path)

        expect(
          result.clientId,
          'local-agent',
          reason:
              '只差空白字符(\\n)的 agent 回复应软匹配命中，而非新插一行。'
              'Pre-fix 精确 content 比较让 \\n 差异导致 miss -> 重复入库。',
        );
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    // -------------------------------------------------------------------------
    // Bug #2 核心：user 消息无身份匹配时，按 content+时间戳软匹配兜底去重
    // (网关不回传 clientId，本地 serverId 是 runId/随机UUID 永不匹配)
    // -------------------------------------------------------------------------
    test(
      'user message with no identity match soft-matches local by content+timestamp',
      () async {
        final msg = inbound(
          clientId: 'history-cid',
          serverId: 'gateway-msg-id',
          role: MessageRole.user,
          content: '帮我分析需求',
          timestamp: 1718000000000,
        );
        // 本地发送的同一消息：clientId 是本地 UUID，serverId 是 runId/随机
        // （与 gateway-msg-id 永不相等），故身份去重全部 miss。
        final existingLocal = local(
          clientId: 'local-uuid',
          serverId: 'runid-junk',
          content: '帮我分析需求',
          timestamp: 1718000002000, // +2s, 在 ±60s 窗口内
        );
        when(
          () => messageRepo.getByClientId('history-cid'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('gateway-msg-id'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [existingLocal]);

        final result = await useCase.merge(msg);

        expect(result.clientId, 'local-uuid', reason: '应软匹配到本地已发消息，而非新插一行历史重复');
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    // -------------------------------------------------------------------------
    // 软匹配护栏：内容相同但时间戳超出窗口 → 视为不同消息 → 插入
    // (防止"连续两条相同内容"被错误合并)
    // -------------------------------------------------------------------------
    test(
      'user message with same content but timestamp outside window is inserted',
      () async {
        final msg = inbound(
          clientId: 'history-cid-2',
          serverId: 'gateway-msg-id-2',
          role: MessageRole.user,
          content: '好的',
          timestamp: 1718000000000,
        );
        final existingLocal = local(
          clientId: 'local-uuid-2',
          serverId: 'runid-junk-2',
          content: '好的',
          timestamp: 1718000000000 + 120000, // +120s, 超出 ±60s 窗口
        );
        when(
          () => messageRepo.getByClientId('history-cid-2'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('gateway-msg-id-2'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [existingLocal]);
        when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

        final result = await useCase.merge(msg);

        expect(result, msg, reason: '内容相同但时间相距甚远 → 是两条不同消息，应插入');
        verify(() => messageRepo.insert(any())).called(1);
      },
    );

    // -------------------------------------------------------------------------
    // 软匹配护栏：内容不同 → 不匹配 → 插入
    // -------------------------------------------------------------------------
    test('user message with different content is inserted', () async {
      final msg = inbound(
        clientId: 'history-cid-3',
        serverId: 'gateway-msg-id-3',
        role: MessageRole.user,
        content: '新问题',
        timestamp: 1718000000000,
      );
      final existingLocal = local(
        clientId: 'local-uuid-3',
        serverId: 'runid-junk-3',
        content: '旧问题',
        timestamp: 1718000000000,
      );
      when(
        () => messageRepo.getByClientId('history-cid-3'),
      ).thenAnswer((_) async => null);
      when(
        () => messageRepo.getByServerId('gateway-msg-id-3'),
      ).thenAnswer((_) async => null);
      when(
        () =>
            messageRepo.getByConversation('conv-1', limit: any(named: 'limit')),
      ).thenAnswer((_) async => [existingLocal]);
      when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

      final result = await useCase.merge(msg);

      expect(result, msg);
      verify(() => messageRepo.insert(any())).called(1);
    });

    // -------------------------------------------------------------------------
    // user 消息无任何匹配 → 插入（多设备来的真新消息）
    // -------------------------------------------------------------------------
    test('user message with no match at all is inserted', () async {
      final msg = inbound(
        clientId: 'history-cid-4',
        serverId: 'gateway-msg-id-4',
        role: MessageRole.user,
        content: '从另一台设备发的',
        timestamp: 1718000000000,
      );
      when(
        () => messageRepo.getByClientId('history-cid-4'),
      ).thenAnswer((_) async => null);
      when(
        () => messageRepo.getByServerId('gateway-msg-id-4'),
      ).thenAnswer((_) async => null);
      when(
        () =>
            messageRepo.getByConversation('conv-1', limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

      final result = await useCase.merge(msg);

      expect(result, msg);
      verify(() => messageRepo.insert(any())).called(1);
    });

    // -------------------------------------------------------------------------
    // softMatch: false（实时流路径）—— 身份未命中时直接 insert，
    // 不查 getByConversation。实时消息是 gateway 新产生(非历史回传),不需要
    // 软匹配；也避免快速连发触发 N 次会话查询破坏 reload 合并。
    // -------------------------------------------------------------------------
    test(
      'softMatch:false skips conversation query and inserts on identity miss',
      () async {
        final msg = inbound(
          clientId: 'rt-cid',
          serverId: null,
          role: MessageRole.agent,
          content: 'realtime reply',
          timestamp: 1718000000000,
        );
        when(
          () => messageRepo.getByClientId('rt-cid'),
        ).thenAnswer((_) async => null);
        // serverId 为 null → 不查 getByServerId。
        when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

        final result = await useCase.merge(msg, softMatch: false);

        expect(result, msg);
        verifyNever(
          () =>
              messageRepo.getByConversation(any(), limit: any(named: 'limit')),
        );
        verify(() => messageRepo.insert(any())).called(1);
      },
    );

    // -------------------------------------------------------------------------
    // 空内容消息 skip: agent 纯 tool_call 回复的空文本副作用 / 网关回传的空
    // text 消息无展示价值(显示为空气泡)。入站空 content text 消息不入库。
    // (用户主动发的空消息走 send→insert,不经 merge,不受影响。)
    // -------------------------------------------------------------------------
    test(
      'empty-content text message is skipped (no insert, no conversation query)',
      () async {
        final msg = inbound(
          clientId: 'empty-cid',
          serverId: null,
          role: MessageRole.agent,
          content: '',
          timestamp: 1718000000000,
        );

        final result = await useCase.merge(msg);

        expect(result, msg, reason: '返回原消息(不入库)');
        verifyNever(() => messageRepo.getByClientId(any()));
        verifyNever(() => messageRepo.getByServerId(any()));
        verifyNever(
          () =>
              messageRepo.getByConversation(any(), limit: any(named: 'limit')),
        );
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    test('null-content text message is also skipped', () async {
      final msg = Message(
        clientId: 'null-cid',
        serverId: null,
        conversationId: 'conv-1',
        agentId: 'agent-1',
        role: MessageRole.agent,
        content: null,
        type: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: 1718000000000,
        logicalClock: 100,
      );

      final result = await useCase.merge(msg);

      expect(result, msg);
      verifyNever(() => messageRepo.insert(any()));
    });

    // -------------------------------------------------------------------------
    // toolResult 空 stdout 不应被跳过：这类消息承载工具执行记录(toolName/status
    // 在 metadata 里),内容为空只是工具没输出。跳过会导致 chat_room 找不到行、
    // 历史 rewind 丢失工具存在痕迹。
    // -------------------------------------------------------------------------
    test(
      'empty-content toolResult message is preserved and inserted',
      () async {
        final msg = inbound(
          clientId: 'tool-cid',
          serverId: 'tool-srv',
          role: MessageRole.toolResult,
          content: '',
          timestamp: 1718000000000,
        );
        when(
          () => messageRepo.getByClientId('tool-cid'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('tool-srv'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => []);
        when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

        final result = await useCase.merge(msg);

        expect(result, msg);
        verify(() => messageRepo.insert(any())).called(1);
      },
    );
  });

  // -------------------------------------------------------------------------
  // mergeWithStatus.wasNew — MessageCatchUpService 用它判断"是否已追平"。
  // -------------------------------------------------------------------------
  group('MergeInboundMessageUseCase.mergeWithStatus.wasNew', () {
    test('returns wasNew=true for a genuinely new message', () async {
      final msg = inbound(role: MessageRole.agent, serverId: 'srv-new');
      when(
        () => messageRepo.getByClientId('inbound-1'),
      ).thenAnswer((_) async => null);
      when(
        () => messageRepo.getByServerId('srv-new'),
      ).thenAnswer((_) async => null);
      when(
        () =>
            messageRepo.getByConversation('conv-1', limit: any(named: 'limit')),
      ).thenAnswer((_) async => []);
      when(() => messageRepo.insert(any())).thenAnswer((_) async => msg);

      final result = await useCase.mergeWithStatus(msg);

      expect(result.wasNew, isTrue);
      expect(result.message, msg);
    });

    test('returns wasNew=false when serverId matches existing', () async {
      final msg = inbound(role: MessageRole.agent, serverId: 'srv-1');
      final existing = local(
        clientId: 'local-agent',
        serverId: 'srv-1',
        role: MessageRole.agent,
        content: 'hi',
      );
      when(
        () => messageRepo.getByClientId('inbound-1'),
      ).thenAnswer((_) async => null);
      when(
        () => messageRepo.getByServerId('srv-1'),
      ).thenAnswer((_) async => existing);

      final result = await useCase.mergeWithStatus(msg);

      expect(result.wasNew, isFalse);
      expect(result.message.clientId, 'local-agent');
      verifyNever(() => messageRepo.insert(any()));
    });

    // v2026.6.10 image reply: chat.final (image-less text placeholder) lands
    // first and inserts with serverId. session.message (image-bearing) arrives
    // later with the same serverId. merge must upsert content/type/metadata
    // rather than silently return the stale placeholder.
    test(
      'serverId hit with richer inbound upserts content/type/metadata',
      () async {
        final placeholder = local(
          clientId: 'local-agent',
          serverId: 'srv-1',
          role: MessageRole.agent,
          content: '',
        );
        final richer = Message(
          clientId: 'rt-cid',
          serverId: 'srv-1',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.agent,
          content: '看这个图',
          type: MessageType.image,
          status: MessageStatus.delivered,
          timestamp: 1718000000000,
          logicalClock: 100,
          metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
        );
        final updated = Message(
          clientId: 'local-agent',
          serverId: 'srv-1',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.agent,
          content: '看这个图',
          type: MessageType.image,
          status: MessageStatus.delivered,
          timestamp: 1718000000000,
          logicalClock: 99,
          metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
        );

        when(
          () => messageRepo.getByClientId('rt-cid'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('srv-1'),
        ).thenAnswer((_) async => placeholder);
        when(
          () => messageRepo.updateContentTypeAndMetadata(
            'srv-1',
            content: '看这个图',
            type: MessageType.image,
            metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
          ),
        ).thenAnswer((_) async => updated);

        final result = await useCase.mergeWithStatus(richer, softMatch: false);

        expect(result.wasNew, isFalse);
        expect(result.message.clientId, 'local-agent');
        expect(result.message.type, MessageType.image);
        expect(result.message.content, '看这个图');
        verify(
          () => messageRepo.updateContentTypeAndMetadata(
            'srv-1',
            content: '看这个图',
            type: MessageType.image,
            metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
          ),
        ).called(1);
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    test(
      'serverId hit with non-richer inbound does not call updateContentTypeAndMetadata',
      () async {
        final existing = local(
          clientId: 'local-agent',
          serverId: 'srv-1',
          role: MessageRole.agent,
          content: 'already image',
        );
        final same = inbound(
          role: MessageRole.agent,
          serverId: 'srv-1',
          content: 'already image',
        );
        when(
          () => messageRepo.getByClientId('inbound-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('srv-1'),
        ).thenAnswer((_) async => existing);

        final result = await useCase.mergeWithStatus(same);

        expect(result.wasNew, isFalse);
        verifyNever(
          () => messageRepo.updateContentTypeAndMetadata(
            any(),
            content: any(named: 'content'),
            type: any(named: 'type'),
            metadata: any(named: 'metadata'),
          ),
        );
      },
    );

    test('returns wasNew=false when softMatch hits', () async {
      final msg = inbound(
        clientId: 'hist-cid',
        serverId: null,
        role: MessageRole.user,
        content: '你好',
        timestamp: 1718000000000,
      );
      final existingLocal = local(
        clientId: 'local-uuid',
        serverId: 'runid-junk',
        content: '你好',
        timestamp: 1718000002000,
      );
      when(
        () => messageRepo.getByClientId('hist-cid'),
      ).thenAnswer((_) async => null);
      when(
        () =>
            messageRepo.getByConversation('conv-1', limit: any(named: 'limit')),
      ).thenAnswer((_) async => [existingLocal]);

      final result = await useCase.mergeWithStatus(msg);

      expect(result.wasNew, isFalse, reason: '软匹配命中 → 不是新消息');
      expect(result.message.clientId, 'local-uuid');
      verifyNever(() => messageRepo.insert(any()));
    });

    // -------------------------------------------------------------------------
    // Placeholder binding: chat.final lands without serverId, session.message
    // arrives later with the authoritative serverId + richer content.
    // -------------------------------------------------------------------------
    test(
      'serverId miss binds recent placeholder with same content and enriches',
      () async {
        final placeholder = local(
          clientId: 'placeholder-cid',
          serverId: null,
          role: MessageRole.agent,
          content: '看这个图',
          timestamp: 1718000000000,
        );
        final richer = Message(
          clientId: 'rt-cid',
          serverId: 'srv-real',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.agent,
          content: '看这个图',
          type: MessageType.image,
          status: MessageStatus.delivered,
          timestamp: 1718000000100,
          logicalClock: 100,
          metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
        );
        final updated = Message(
          clientId: 'placeholder-cid',
          serverId: 'srv-real',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.agent,
          content: '看这个图',
          type: MessageType.image,
          status: MessageStatus.delivered,
          timestamp: 1718000000000,
          logicalClock: 99,
          metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
        );

        when(
          () => messageRepo.getByClientId('rt-cid'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('srv-real'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [placeholder]);
        when(
          () => messageRepo.bindServerIdAndUpdateContent(
            'placeholder-cid',
            serverId: 'srv-real',
            content: '看这个图',
            type: MessageType.image,
            metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
          ),
        ).thenAnswer((_) async => updated);

        final result = await useCase.mergeWithStatus(richer, softMatch: false);

        expect(result.wasNew, isFalse);
        expect(result.message.clientId, 'placeholder-cid');
        expect(result.message.serverId, 'srv-real');
        expect(result.message.type, MessageType.image);
        verifyNever(() => messageRepo.insert(any()));
      },
    );

    test(
      'serverId miss does not bind placeholder when content differs',
      () async {
        final placeholder = local(
          clientId: 'placeholder-cid',
          serverId: null,
          role: MessageRole.agent,
          content: 'old text',
          timestamp: 1718000000000,
        );
        final inboundMsg = inbound(
          serverId: 'srv-real',
          role: MessageRole.agent,
          content: 'new text',
          timestamp: 1718000000100,
        );

        when(
          () => messageRepo.getByClientId('inbound-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('srv-real'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByConversation(
            'conv-1',
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [placeholder]);

        final inserted = inboundMsg.copyWith(clientId: 'inserted-cid');
        when(() => messageRepo.insert(any())).thenAnswer((_) async => inserted);

        final result = await useCase.mergeWithStatus(
          inboundMsg,
          softMatch: false,
        );

        expect(result.wasNew, isTrue);
        verifyNever(
          () => messageRepo.bindServerIdAndUpdateContent(
            any(),
            serverId: any(named: 'serverId'),
            content: any(named: 'content'),
            type: any(named: 'type'),
            metadata: any(named: 'metadata'),
          ),
        );
      },
    );

    test(
      'serverId hit updates imageUrl when inbound has a better endpoint',
      () async {
        final existing =
            local(
              clientId: 'local-agent',
              serverId: 'srv-1',
              role: MessageRole.agent,
              content: '看这个图',
            ).copyWith(
              type: MessageType.image,
              metadata: const {
                'imageUrl': '/root/.openclaw/media/inbound/probe.png',
              },
            );
        final richer = Message(
          clientId: 'rt-cid',
          serverId: 'srv-1',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.agent,
          content: '看这个图',
          type: MessageType.image,
          status: MessageStatus.delivered,
          timestamp: 1718000000000,
          logicalClock: 100,
          metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
        );
        final updated = existing.copyWith(
          metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
        );

        when(
          () => messageRepo.getByClientId('rt-cid'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getByServerId('srv-1'),
        ).thenAnswer((_) async => existing);
        when(
          () => messageRepo.updateContentTypeAndMetadata(
            'srv-1',
            content: '看这个图',
            type: MessageType.image,
            metadata: const {'imageUrl': '/api/chat/media/outgoing/abc/full'},
          ),
        ).thenAnswer((_) async => updated);

        final result = await useCase.mergeWithStatus(richer, softMatch: false);

        expect(result.wasNew, isFalse);
        expect(
          result.message.metadata?['imageUrl'],
          '/api/chat/media/outgoing/abc/full',
        );
      },
    );
  });
}
