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
