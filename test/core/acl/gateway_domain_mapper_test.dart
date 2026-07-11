import 'package:claw_hub/core/acl/gateway_domain_mapper.dart';
import 'package:claw_hub/domain/models/enums.dart'
    show MessageRole, MessageType;
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mapper = GatewayDomainMapper();

  // ---------------------------------------------------------------------------
  // extractTextContent
  // ---------------------------------------------------------------------------
  group('extractTextContent', () {
    test('returns null for null input', () {
      expect(GatewayDomainMapper.extractTextContent(null), isNull);
    });

    test('returns string unchanged for String input', () {
      expect(GatewayDomainMapper.extractTextContent('hello'), 'hello');
    });

    test('joins structured content blocks (real Gateway format)', () {
      final blocks = [
        {'type': 'text', 'text': '第一部分'},
        {'type': 'text', 'text': '第二部分'},
      ];
      expect(GatewayDomainMapper.extractTextContent(blocks), '第一部分第二部分');
    });

    test('skips non-text blocks in structured content', () {
      final blocks = [
        {'type': 'image', 'url': 'https://x.com/a.png'},
        {'type': 'text', 'text': '图片描述'},
      ];
      expect(GatewayDomainMapper.extractTextContent(blocks), '图片描述');
    });

    test('joins list of plain strings', () {
      expect(GatewayDomainMapper.extractTextContent(['a', 'b', 'c']), 'abc');
    });

    test('falls back to toString for unrecognized non-list types', () {
      expect(GatewayDomainMapper.extractTextContent(42), '42');
    });

    // ----- #3: extractTextContent must return null (not '') for "no text" so
    // the ?? fallback chain in parseMessage reaches _extractTextFromPayloads.
    test('returns null for empty string (#3)', () {
      expect(GatewayDomainMapper.extractTextContent(''), isNull);
    });

    test('returns null for content list with only non-text blocks (#3)', () {
      final blocks = [
        {'type': 'image', 'url': 'https://x.com/a.png'},
      ];
      expect(GatewayDomainMapper.extractTextContent(blocks), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // extractImageRef
  // ---------------------------------------------------------------------------
  group('extractImageRef', () {
    test('returns null for null / string / empty input', () {
      expect(GatewayDomainMapper.extractImageRef(null), isNull);
      expect(GatewayDomainMapper.extractImageRef('hello'), isNull);
      expect(GatewayDomainMapper.extractImageRef(<Map>[]), isNull);
    });

    test('detects OpenAI-style image_url block', () {
      final blocks = [
        {
          'type': 'image_url',
          'image_url': {'url': 'https://x.com/a.png'},
        },
      ];
      expect(
        GatewayDomainMapper.extractImageRef(blocks),
        'https://x.com/a.png',
      );
    });

    test('detects Gateway native image block with url at root', () {
      final blocks = [
        {'type': 'image', 'url': 'data:image/png;base64,AAA'},
      ];
      expect(
        GatewayDomainMapper.extractImageRef(blocks),
        'data:image/png;base64,AAA',
      );
    });

    test('defensively supports nested image:{url} block', () {
      final blocks = [
        {
          'type': 'image',
          'image': {'url': 'https://cdn.example.com/chart.png'},
        },
      ];
      expect(
        GatewayDomainMapper.extractImageRef(blocks),
        'https://cdn.example.com/chart.png',
      );
    });

    test('returns null when no image block present', () {
      final blocks = [
        {'type': 'text', 'text': '纯文本回复'},
      ];
      expect(GatewayDomainMapper.extractImageRef(blocks), isNull);
    });

    test('returns null for image block without url', () {
      final blocks = [
        {'type': 'image', 'caption': 'missing url'},
      ];
      expect(GatewayDomainMapper.extractImageRef(blocks), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // parseAgent
  // ---------------------------------------------------------------------------
  group('parseAgent', () {
    test('parses minimal agent with remoteId fallback', () {
      final agent = mapper.parseAgent({'id': 'agent-1'}, 'inst-1');
      expect(agent.remoteId, 'agent-1');
      expect(agent.instanceId, 'inst-1');
      expect(agent.name, 'agent-1');
      expect(agent.themeColor, '#4F83FF');
    });

    test('uses name fallback chain: name → identity.name → id', () {
      final agent = mapper.parseAgent({
        'id': 'agent-1',
        'identity': {'name': 'IdentityName'},
      }, 'inst-1');
      expect(agent.name, 'IdentityName');
    });

    test(
      'uses description fallback chain: description → theme → identity.description',
      () {
        final agent = mapper.parseAgent({
          'id': 'agent-1',
          'description': 'TopDesc',
          'identity': {'theme': 'ThemeDesc', 'description': 'IdentityDesc'},
        }, 'inst-1');
        expect(agent.description, 'TopDesc');
      },
    );

    test('parses quick commands with explicit ids', () {
      final agent = mapper.parseAgent({
        'id': 'agent-1',
        'quickCommands': [
          {'id': 'qc-1', 'label': 'Hi', 'payload': 'hello'},
        ],
      }, 'inst-1');
      expect(agent.quickCommands, hasLength(1));
      expect(agent.quickCommands.first.id, 'qc-1');
    });

    test('generates fallback quick command ids when missing', () {
      final agent = mapper.parseAgent({
        'id': 'agent-1',
        'quickCommands': [
          {'label': 'Hi', 'payload': 'hello'},
        ],
      }, 'inst-1');
      expect(agent.quickCommands.first.id, 'agent-1:0:Hi:hello');
    });
  });

  // ---------------------------------------------------------------------------
  // parseMessage
  // ---------------------------------------------------------------------------
  group('parseMessage', () {
    test('user-role message is parsed as SENT, not DELIVERED', () {
      final msg = mapper.parseMessage({'role': 'user', 'content': 'hello'});
      expect(msg.role, MessageRole.user);
      expect(msg.status, MessageStatus.sent);
    });

    test('agent-role message remains DELIVERED', () {
      final msg = mapper.parseMessage({'role': 'agent', 'content': 'hi'});
      expect(msg.role, MessageRole.agent);
      expect(msg.status, MessageStatus.delivered);
    });

    // ----- regression #1: toolResult must NOT fall through to user role. -----
    // Before the fix, 'toolResult' / 'tool_result' / 'toolCall' / 'tool_call' all
    // returned MessageRole.user because the switch had no case for them. UI then
    // rendered the tool output (e.g. `ls -la`) as a yellow user-side bubble,
    // which is the bug reported against the openclaw-android client.
    test('toolResult role maps to MessageRole.toolResult (NOT user)', () {
      final msg = mapper.parseMessage({
        'role': 'toolResult',
        'content': '-rw-r--r-- 1 root root 17125 ...',
      });
      expect(msg.role, MessageRole.toolResult);
      expect(msg.content, '-rw-r--r-- 1 root root 17125 ...');
    });
    test(
      'tool_result / toolCall / tool_call aliases all map to toolResult',
      () {
        for (final alias in ['tool_result', 'toolCall', 'tool_call']) {
          final msg = mapper.parseMessage({'role': alias, 'content': 'x'});
          expect(
            msg.role,
            MessageRole.toolResult,
            reason: 'alias "$alias" should map to toolResult',
          );
        }
      },
    );

    // ----- regression #2: user-upload placeholder must be reclassified. -----
    // OpenClaw inserts a user message whose body is the fixed placeholder
    // '[User sent media without caption]' when the user uploads a file. It is
    // role=user on the wire but semantically is NOT a user-typed input — it
    // should not occupy a user bubble in the chat view.
    test(
      'user-role message whose body is the media placeholder is reclassified',
      () {
        final msg = mapper.parseMessage({
          'role': 'user',
          'content': '[User sent media without caption]',
        });
        expect(msg.role, MessageRole.userPlaceholder);
      },
    );
    test('user-role message with non-placeholder content remains user', () {
      final msg = mapper.parseMessage({'role': 'user', 'content': '你好'});
      expect(msg.role, MessageRole.user);
    });
    test('userPlaceholder handles string AND structured content blocks', () {
      final asBlocks = mapper.parseMessage({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '[User sent media without caption]'},
        ],
      });
      expect(asBlocks.role, MessageRole.userPlaceholder);
    });

    // 回归:网关若给占位文本加尾空格/换行,精确字符串匹配会失效,导致占位消息
    // 被当成普通 user 消息渲染成黄色气泡。
    test('userPlaceholder detection tolerates trailing whitespace', () {
      final msg = mapper.parseMessage({
        'role': 'user',
        'content': '[User sent media without caption]\n',
      });
      expect(msg.role, MessageRole.userPlaceholder);
    });

    // ----- regression #4: chat.history display-normalization replaces oversized
    // message content with a placeholder string. The client must detect it and
    // flag the message so the UI can offer a lazy "tap to load" backfill via
    // chat.message.get (docs/technical/openclaw-gateway-client-reference.md
    // §3.2 line 217-219). Without detection the raw placeholder renders as a
    // normal bubble - the reported bug.
    test(
      'chat.history omitted placeholder sets metadata.contentOmitted = true',
      () {
        final msg = mapper.parseMessage({
          'role': 'agent',
          'content': '[chat.history omitted: message too large]',
          '__openclaw': {'id': 'msg-server-42'},
        });
        expect(msg.content, '[chat.history omitted: message too large]');
        expect(msg.metadata?['contentOmitted'], isTrue);
        // role/type are unchanged - the flag drives rendering, not the role.
        expect(msg.role, MessageRole.agent);
        expect(msg.type, MessageType.text);
        // serverId preserved so chat.message.get can backfill.
        expect(msg.serverId, 'msg-server-42');
      },
    );
    test(
      'omitted placeholder detection works for structured content blocks',
      () {
        final msg = mapper.parseMessage({
          'role': 'agent',
          'content': [
            {
              'type': 'text',
              'text': '[chat.history omitted: message too large]',
            },
          ],
        });
        expect(msg.metadata?['contentOmitted'], isTrue);
      },
    );
    test('omitted placeholder detection tolerates trailing whitespace', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'content': '[chat.history omitted: message too large]\n',
      });
      expect(msg.metadata?['contentOmitted'], isTrue);
    });
    test('normal content does NOT set contentOmitted', () {
      final msg = mapper.parseMessage({'role': 'agent', 'content': '这是一条普通回复'});
      // Empty metadata is normalised to null (mapper line 216); either way the
      // flag must not be true.
      expect(msg.metadata?['contentOmitted'], isNot(isTrue));
    });
    test('user-typed literal placeholder is still flagged (conservative)', () {
      // A user message whose body happens to be the literal is conservatively
      // flagged too - the backfill path is a no-op if the message isn't truly
      // omitted (server returns the same content). Acceptable: the string is
      // not something a user types in practice.
      final msg = mapper.parseMessage({
        'role': 'user',
        'content': '[chat.history omitted: message too large]',
      });
      expect(msg.metadata?['contentOmitted'], isTrue);
    });

    // ----- regression #3: unknown role strings must NOT silently become user. -----
    // The switch's default arm was `_ => MessageRole.user` — any unrecognized role
    // string (e.g. a future 'function' / 'moderator') would render as a yellow user
    // bubble, which is the same bug class as toolResult. Unknown roles now fall to
    // system (rendered as nothing) instead of masquerading as user input.
    test('unknown role string maps to system (NOT user)', () {
      final msg = mapper.parseMessage({'role': 'function', 'content': 'x'});
      expect(msg.role, MessageRole.system);
    });

    // ----- capture-verified (2026-07-05, OpenClaw v2026.6.10): toolResult and
    // upload-placeholder messages carry toolName / toolCallId / isError / MediaPaths
    // as TOP-LEVEL fields, NOT inside a `metadata` object. parseMessage must extract
    // them into message.metadata so MessageBubble._buildToolResult / _buildPlaceholder
    // can read them. See memory openclaw-v2026-6-10-wire-format.
    test(
      'toolResult extracts top-level toolName/toolCallId/isError into metadata',
      () {
        final msg = mapper.parseMessage({
          'role': 'toolResult',
          'toolCallId': 'call_abc',
          'toolName': 'exec',
          'content': '-rw-r--r-- 1 root root 17125 ...',
          'isError': false,
          'timestamp': 1718000000000,
        });
        expect(msg.role, MessageRole.toolResult);
        expect(msg.metadata?['toolName'], 'exec');
        expect(msg.metadata?['toolCallId'], 'call_abc');
        expect(msg.metadata?['isError'], false);
      },
    );
    test('toolResult with isError=true still extracts fields', () {
      final msg = mapper.parseMessage({
        'role': 'toolResult',
        'toolName': 'message',
        'content': '{"status":"error"}',
        'isError': true,
      });
      expect(msg.metadata?['isError'], true);
      expect(msg.metadata?['toolName'], 'message');
    });
    test(
      'userPlaceholder extracts top-level MediaPaths into metadata.mediaPaths',
      () {
        final msg = mapper.parseMessage({
          'role': 'user',
          'content': '[User sent media without caption]',
          'MediaPaths': ['/tmp/a.txt', '/tmp/b.txt'],
          'MediaTypes': ['text/plain', 'text/plain'],
        });
        expect(msg.role, MessageRole.userPlaceholder);
        expect(msg.metadata?['mediaPaths'], ['/tmp/a.txt', '/tmp/b.txt']);
      },
    );
    test('plain user message does NOT synthesize empty metadata', () {
      // Sanity: extraction must not create a metadata map for ordinary messages
      // that carry none of the tool/media top-level fields.
      final msg = mapper.parseMessage({'role': 'user', 'content': '你好'});
      expect(msg.metadata, isNull);
    });

    test('seconds-scale timestamp is normalized to milliseconds', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'timestamp': 1718000000,
      });
      expect(msg.timestamp, 1718000000000);
    });

    test('milliseconds-scale timestamp is preserved unchanged', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'timestamp': 1718000000000,
      });
      expect(msg.timestamp, 1718000000000);
    });

    test('message without logicalClock falls back to its own timestamp', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'timestamp': 1718000000000,
      });
      expect(msg.logicalClock, 1718000000000);
    });

    test('explicit gateway logicalClock is preserved verbatim', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'timestamp': 1718000000000,
        'logicalClock': 42,
      });
      expect(msg.logicalClock, 42);
    });

    // v2026.6.10 drift: chat.final message object carries the authoritative
    // server id under `__openclaw.id`, not `serverId`/`id`. parseMessage must
    // read it so the merge layer can dedup/upsert the real-time final with the
    // richer session.message and with history.
    test('uses __openclaw.id as serverId fallback (v2026.6.10)', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'content': 'hello',
        '__openclaw': {'id': 'oc-msg-123'},
      });
      expect(msg.serverId, 'oc-msg-123');
    });

    test('serverId precedence: serverId > __openclaw.id > id', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'serverId': 'srv-a',
        'id': 'id-b',
        '__openclaw': {'id': 'oc-c'},
      });
      expect(msg.serverId, 'srv-a');
    });

    test('__openclaw.id takes precedence over id (v2026.6.10 alignment)', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'id': 'id-b',
        '__openclaw': {'id': 'oc-c'},
      });
      expect(msg.serverId, 'oc-c');
    });

    test(
      'image_url content block becomes type=image with metadata.imageUrl',
      () {
        final msg = mapper.parseMessage({
          'role': 'agent',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'https://x.com/a.png'},
            },
          ],
        });
        expect(msg.type, MessageType.image);
        expect(msg.metadata?['imageUrl'], 'https://x.com/a.png');
      },
    );

    test('plain text content stays type=text', () {
      final msg = mapper.parseMessage({'role': 'agent', 'content': 'hello'});
      expect(msg.type, MessageType.text);
    });

    test('explicit type=image with string content preserved', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'image',
        'content': 'image text',
      });
      expect(msg.type, MessageType.image);
      expect(msg.content, 'image text');
    });

    // ----- Agent 回图修复:attachment block + payloads/mediaUrl 兜底 -----
    // Root cause: extractImageRef 原只认 image/image_url block,漏掉 gateway
    // 解析 MEDIA: 指令后 emit 的 attachment block(docs/technical/
    // openclaw-media-protocol.md §4.2)→ type=text + 空白。
    // 优先级: imageRef(含 attachment) > payloads[].mediaUrl > metadata.imageUrl
    test('attachment block (kind=image) promotes type=image with imageUrl', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': [
          {
            'type': 'attachment',
            'attachment': {
              'url':
                  '/__openclaw__/assistant-media?source=probe.png&mediaTicket=v1.x',
              'kind': 'image',
              'label': 'probe-1783347699.png',
              'mimeType': 'image/png',
            },
          },
        ],
      });
      expect(msg.type, MessageType.image);
      expect(
        msg.metadata?['imageUrl'],
        '/__openclaw__/assistant-media?source=probe.png&mediaTicket=v1.x',
      );
    });

    test('attachment block with kind=audio is NOT promoted to image', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': [
          {
            'type': 'attachment',
            'attachment': {
              'url': '/__openclaw__/assistant-media?source=clip.mp3',
              'kind': 'audio',
              'mimeType': 'audio/mpeg',
            },
          },
        ],
      });
      expect(msg.type, MessageType.text);
      expect(msg.metadata?['imageUrl'], isNull);
    });

    test('attachment block with missing kind defensively extracts url', () {
      // 防御:部分形态可能省略 kind,仍尝试取 url(避免漏渲染)。
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': [
          {
            'type': 'attachment',
            'attachment': {'url': 'https://cdn.example.com/chart.png'},
          },
        ],
      });
      expect(msg.type, MessageType.image);
      expect(msg.metadata?['imageUrl'], 'https://cdn.example.com/chart.png');
    });

    test('payloads[].mediaUrl fallback promotes type=image with caption', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': null,
        'payloads': [
          {'text': '图表说明', 'mediaUrl': 'data:image/png;base64,XXX'},
        ],
      });
      expect(msg.type, MessageType.image);
      expect(msg.metadata?['imageUrl'], 'data:image/png;base64,XXX');
      expect(msg.content, '图表说明'); // payloads[0].text 作为 caption
    });

    test('payloads multi-payload: first text-only, second image-only', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': null,
        'payloads': [
          {'text': '这是图表', 'mediaUrl': null},
          {'text': null, 'mediaUrl': 'https://cdn.example.com/chart.png'},
        ],
      });
      expect(msg.type, MessageType.image);
      expect(msg.metadata?['imageUrl'], 'https://cdn.example.com/chart.png');
    });

    test('metadata.imageUrl independent fallback promotes type=image', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': '这是图表',
        'metadata': {'imageUrl': 'data:image/png;base64,XXX'},
      });
      expect(msg.type, MessageType.image);
      expect(msg.metadata?['imageUrl'], 'data:image/png;base64,XXX');
      expect(msg.content, '这是图表');
    });

    test('priority: attachment block wins over payloads[].mediaUrl', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': [
          {
            'type': 'attachment',
            'attachment': {
              'url': '/__openclaw__/assistant-media?from=attachment',
              'kind': 'image',
            },
          },
        ],
        'payloads': [
          {'text': 'x', 'mediaUrl': 'https://from-payloads.png'},
        ],
      });
      expect(
        msg.metadata?['imageUrl'],
        '/__openclaw__/assistant-media?from=attachment',
      );
    });

    test(
      'regression: plain agent message without image fields stays text + null metadata',
      () {
        // 整合 image 兜底后,必须确保普通消息不合成空 metadata、不被误提升。
        final msg = mapper.parseMessage({'role': 'agent', 'content': '你好'});
        expect(msg.type, MessageType.text);
        expect(msg.metadata, isNull);
      },
    );

    test('content=blocks(image) keeps original imageRef behavior (compat)', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'image',
        'content': [
          {'type': 'text', 'text': '描述'},
          {'type': 'image', 'url': 'https://x.com/a.png'},
        ],
      });
      expect(msg.type, MessageType.image);
      expect(msg.metadata?['imageUrl'], 'https://x.com/a.png');
      expect(msg.content, '描述');
    });

    // ----- #3 integration: content list with only non-text blocks must fall
    // through to payloads[].text instead of swallowing the caption with ''.
    test(
      'content list with only non-text blocks falls through to payloads[].text (#3)',
      () {
        final msg = mapper.parseMessage({
          'role': 'agent',
          'type': 'text',
          'content': [
            {
              'type': 'attachment',
              'attachment': {'url': '/img.png', 'kind': 'image'},
            },
          ],
          'payloads': [
            {'text': 'caption'},
          ],
        });
        expect(msg.type, MessageType.image);
        expect(msg.metadata?['imageUrl'], '/img.png');
        expect(msg.content, 'caption');
      },
    );

    // ----- #4: a file-typed message must NOT be promoted to image even when
    // metadata.imageUrl is present (file keeps file rendering affordances).
    test('file type with imageUrl is NOT promoted to image (#4)', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'file',
        'metadata': {'imageUrl': 'thumb.png'},
      });
      expect(msg.type, MessageType.file);
    });

    // ----- #6: payloadMediaUrl must not leak a spurious imageUrl onto a
    // toolCall-typed message (type says tool-call, metadata said image-present).
    test(
      'toolCall with payloads mediaUrl does not carry spurious imageUrl (#6)',
      () {
        final msg = mapper.parseMessage({
          'role': 'toolResult',
          'type': 'toolCall',
          'content': 'result',
          'payloads': [
            {'mediaUrl': 'https://x.png'},
          ],
        });
        expect(msg.type, MessageType.toolCall);
        expect(msg.metadata?['imageUrl'], isNull);
      },
    );

    // ----- #15: metadata.imageUrl gate must reject whitespace-only and the
    // literal string 'null' (consistent with _extractMediaUrlFromPayloads).
    test(
      'metadata.imageUrl whitespace-only does not promote to image (#15)',
      () {
        final msg = mapper.parseMessage({
          'role': 'agent',
          'type': 'text',
          'metadata': {'imageUrl': ' '},
        });
        expect(msg.type, MessageType.text);
        expect(msg.metadata?['imageUrl'], isNull);
      },
    );

    test(
      'metadata.imageUrl literal "null" does not promote to image (#15)',
      () {
        final msg = mapper.parseMessage({
          'role': 'agent',
          'type': 'text',
          'metadata': {'imageUrl': 'null'},
        });
        expect(msg.type, MessageType.text);
        expect(msg.metadata?['imageUrl'], isNull);
      },
    );

    // ----- #16: extractImageRef's attachment branch must reject the literal
    // string 'null' as a URL (consistent with the payloads path).
    test('attachment block url literal "null" is not extracted (#16)', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'type': 'text',
        'content': [
          {
            'type': 'attachment',
            'attachment': {'url': 'null', 'kind': 'image'},
          },
        ],
      });
      expect(msg.type, MessageType.text);
      expect(msg.metadata?['imageUrl'], isNull);
    });

    // ----- Raw MEDIA: directive fallback (gateway did not transform to block) ----
    test('MEDIA: directive in text promotes to image and strips directive', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'content':
            '看这个图\nMEDIA:/root/.openclaw/media/inbound/probe-1783347699.png\n喜欢吗?',
      });
      expect(msg.type, MessageType.image);
      expect(
        msg.metadata?['imageUrl'],
        '/root/.openclaw/media/inbound/probe-1783347699.png',
      );
      expect(msg.content, '看这个图\n喜欢吗?');
    });

    test('MEDIA: directive with backticks is stripped', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'content': 'caption\nMEDIA: `/root/.openclaw/media/inbound/a.jpg`',
      });
      expect(msg.type, MessageType.image);
      expect(msg.metadata?['imageUrl'], '/root/.openclaw/media/inbound/a.jpg');
      expect(msg.content, 'caption');
    });

    test('non-image MEDIA: directive does not promote to image', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'content': '听这个\nMEDIA:/root/.openclaw/media/inbound/clip.mp3',
      });
      expect(msg.type, MessageType.text);
      expect(msg.metadata?['imageUrl'], isNull);
      // 非图片指令不应被剥掉,避免误改原始文本。
      expect(msg.content, contains('MEDIA:'));
    });

    test('MEDIA: directive with media:// URL is extracted', () {
      final msg = mapper.parseMessage({
        'role': 'agent',
        'content': 'MEDIA:media://inbound/abc123/image.png',
      });
      expect(msg.type, MessageType.image);
      expect(msg.metadata?['imageUrl'], 'media://inbound/abc123/image.png');
      expect(msg.content, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // buildAgentFallbackMessage
  // ---------------------------------------------------------------------------
  group('buildAgentFallbackMessage', () {
    test('produces delivered text message from buffer content', () {
      final msg = mapper.buildAgentFallbackMessage('agent-1', 'buffer text');
      expect(msg.agentId, 'agent-1');
      expect(msg.content, 'buffer text');
      expect(msg.type, MessageType.text);
      expect(msg.status, MessageStatus.delivered);
      expect(msg.role, MessageRole.agent);
      expect(msg.conversationId, '');
    });
  });
}
