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
  // parseMessage — Phase 2 image-fix (payloads / metadata.imageUrl)
  // See docs/technical/image-fix-spec.md §4.3
  // ---------------------------------------------------------------------------
  group('Bug fix: Agent 回图 type="text" 但 payloads[].mediaUrl / metadata.imageUrl', () {
    test('形态 1: type=text + content=null + payloads 含 mediaUrl → type=image', () {
      final msg = mapper.parseMessage({
        'agentId': 'r-1',
        'sessionKey': 'agent:r-1:main',
        'content': null,
        'role': 'agent',
        'type': 'text',
        'payloads': [
          {'text': '图表说明', 'mediaUrl': 'data:image/png;base64,XXX'},
        ],
      });
      expect(msg.type, MessageType.image); // 提升为 image
      expect(msg.imageUrl, 'data:image/png;base64,XXX');
      expect(msg.content, '图表说明'); // payloads[0].text 也读
    });

    test('形态 1 多 payload: 第一个 text-only, 第二个纯 image → type=image', () {
      final msg = mapper.parseMessage({
        'content': null,
        'role': 'agent',
        'type': 'text',
        'payloads': [
          {'text': '这是图表', 'mediaUrl': null},
          {'text': null, 'mediaUrl': 'https://cdn.example.com/chart.png'},
        ],
      });
      expect(msg.type, MessageType.image);
      expect(msg.imageUrl, 'https://cdn.example.com/chart.png');
    });

    test('形态 4: type=text + content=描述文本 + metadata.imageUrl 独立 → type=image', () {
      final msg = mapper.parseMessage({
        'content': '这是图表',
        'role': 'agent',
        'type': 'text',
        'metadata': {'imageUrl': 'data:image/png;base64,XXX'},
      });
      expect(msg.type, MessageType.image);
      expect(msg.imageUrl, 'data:image/png;base64,XXX');
      expect(msg.content, '这是图表');
    });

    test('形态 5 兼容: content=blocks(image) → 保持原行为(imageRef 命中)', () {
      final msg = mapper.parseMessage({
        'content': [
          {'type': 'text', 'text': '描述'},
          {'type': 'image', 'url': 'https://x.com/a.png'},
        ],
        'role': 'agent',
        'type': 'image',
      });
      expect(msg.type, MessageType.image);
      expect(msg.imageUrl, 'https://x.com/a.png');
      expect(msg.content, '描述');
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
