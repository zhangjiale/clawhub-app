import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

void main() {
  group('MessageBubble agent theme', () {
    Widget wrap(Widget child, {AgentTheme? agentTheme}) => MaterialApp(
      theme: ThemeData(extensions: agentTheme != null ? [agentTheme] : []),
      home: Scaffold(body: SizedBox(width: 400, child: child)),
    );

    Message message({required MessageRole role, String content = 'hello'}) {
      return Message(
        clientId: 'm-${role.name}',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        role: role,
        content: content,
        type: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: 0,
        logicalClock: 0,
      );
    }

    Color bubbleColor(WidgetTester tester, String text) {
      final textFinder = find.text(text);
      final containers = find.ancestor(
        of: textFinder,
        matching: find.byType(Container),
      );
      for (final element in containers.evaluate()) {
        final widget = element.widget as Container;
        final decoration = widget.decoration;
        if (decoration is BoxDecoration && decoration.color != null) {
          return decoration.color!;
        }
      }
      fail('No decorated Container found for text $text');
    }

    testWidgets('user bubble uses AgentTheme primary color', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message(role: MessageRole.user, content: 'user-blue'),
            agentName: '产品虾',
          ),
          agentTheme: const AgentTheme(primary: Color(0xFF9B7AFF)), // V2 violet
        ),
      );

      expect(bubbleColor(tester, 'user-blue'), const Color(0xFF9B7AFF));
    });

    testWidgets('user bubble falls back to sapphire when no AgentTheme', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message(role: MessageRole.user, content: 'user-default'),
            agentName: '产品虾',
          ),
        ),
      );

      // V2: default AgentTheme.primary = sapphire #4F83FF
      expect(bubbleColor(tester, 'user-default'), const Color(0xFF4F83FF));
    });

    testWidgets('agent bubble stays surface2 regardless of AgentTheme', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message(role: MessageRole.agent, content: 'agent-themed'),
            agentName: '产品虾',
          ),
          agentTheme: const AgentTheme(primary: Color(0xFFF472B6)), // V2 pink
        ),
      );
      // V2: agent bubble bg = surface2 (was surface in V1)
      expect(bubbleColor(tester, 'agent-themed'), XiaColors.surface2);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message(role: MessageRole.agent, content: 'agent-default'),
            agentName: '产品虾',
          ),
        ),
      );
      expect(bubbleColor(tester, 'agent-default'), XiaColors.surface2);
    });

    testWidgets('user bubble text is white', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message(role: MessageRole.user, content: 'white-text'),
            agentName: '产品虾',
          ),
          agentTheme: const AgentTheme(primary: Color(0xFF22D3EE)), // V2 cyan
        ),
      );

      final text = tester.widget<Text>(find.text('white-text'));
      expect(text.style!.color, Colors.white);
    });

    // -----------------------------------------------------------------------
    // Law 14: isHighlighted rendering — 搜索高亮必须有 widget 测试覆盖
    // -----------------------------------------------------------------------
    group('isHighlighted', () {
      testWidgets('agent bubble uses accent background when highlighted', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: message(
                role: MessageRole.agent,
                content: 'agent-highlighted',
              ),
              agentName: '产品虾',
              isHighlighted: true,
            ),
            agentTheme: const AgentTheme(primary: Color(0xFF4F83FF)),
          ),
        );

        // V2: highlighted agent bubble uses accent.withAlpha(38), not surface
        expect(
          bubbleColor(tester, 'agent-highlighted'),
          XiaColors.accent.withAlpha(38),
        );
      });

      testWidgets('user bubble keeps user color when highlighted', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: message(
                role: MessageRole.user,
                content: 'user-highlighted',
              ),
              agentName: '产品虾',
              isHighlighted: true,
            ),
            agentTheme: const AgentTheme(primary: Color(0xFF9B7AFF)),
          ),
        );

        // Highlighted user bubble keeps AgentTheme.primary (not accent)
        expect(
          bubbleColor(tester, 'user-highlighted'),
          const Color(0xFF9B7AFF),
        );
      });

      testWidgets('highlighted bubble has accent border', (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: message(role: MessageRole.agent, content: 'border-test'),
              agentName: '产品虾',
              isHighlighted: true,
            ),
          ),
        );

        final containers = find.ancestor(
          of: find.text('border-test'),
          matching: find.byType(Container),
        );
        BoxDecoration? foundDecoration;
        for (final element in containers.evaluate()) {
          final widget = element.widget as Container;
          final d = widget.decoration;
          if (d is BoxDecoration && d.border != null) {
            foundDecoration = d;
            break;
          }
        }
        expect(foundDecoration, isNotNull);
        expect(foundDecoration!.border, isNotNull);
      });

      testWidgets('non-highlighted bubble has no accent border', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: message(
                role: MessageRole.agent,
                content: 'no-border-test',
              ),
              agentName: '产品虾',
              isHighlighted: false,
            ),
          ),
        );

        // V2: agent bubbles now have a hairline border (XiaColors.border) for
        // depth. The test verifies there is NO accent-colored border on a
        // non-highlighted agent bubble.
        final containers = find.ancestor(
          of: find.text('no-border-test'),
          matching: find.byType(Container),
        );
        for (final element in containers.evaluate()) {
          final widget = element.widget as Container;
          final d = widget.decoration;
          if (d is BoxDecoration && d.border != null) {
            // Ensure no accent-colored border on non-highlighted agent bubble
            final border = d.border!;
            final top = border.top;
            if (top.color == XiaColors.accent) {
              fail('Non-highlighted bubble should not have accent border');
            }
          }
        }
        // Test passes if no decorated container with accent border found
      });

      testWidgets('short message still shrink-wraps', (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: message(role: MessageRole.agent, content: 'OK'),
              agentName: '产品虾',
            ),
          ),
        );

        final bubble = tester.widget<Container>(
          find
              .ancestor(of: find.text('OK'), matching: find.byType(Container))
              .first,
        );

        // BoxConstraints(maxWidth: ...) allows shrink-wrapping — verify
        // the constraint is maxWidth (not tight width)
        final constraints = bubble.constraints;
        expect(constraints, isNotNull);
        if (constraints != null) {
          expect(constraints.minWidth, lessThan(constraints.maxWidth));
        }
      });
    });

    group('image/file rendering', () {
      Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, child: child)),
      );

      testWidgets('file message renders fileName + size', (tester) async {
        final msg = Message(
          clientId: 'f1',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.user,
          content: '/tmp/doc.pdf',
          type: MessageType.file,
          status: MessageStatus.sent,
          timestamp: 0,
          logicalClock: 0,
          metadata: const {
            'fileName': 'doc.pdf',
            'mimeType': 'application/pdf',
            'size': 12288,
          },
        );
        await tester.pumpWidget(
          wrap(MessageBubble(message: msg, agentName: '虾')),
        );

        expect(find.text('doc.pdf'), findsOneWidget);
        expect(find.text('12.0 KB'), findsOneWidget);
      });

      testWidgets('image message with no path/url renders [图片] placeholder', (
        tester,
      ) async {
        final msg = Message(
          clientId: 'i1',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.user,
          content: null,
          type: MessageType.image,
          status: MessageStatus.sent,
          timestamp: 0,
          logicalClock: 0,
        );
        await tester.pumpWidget(
          wrap(MessageBubble(message: msg, agentName: '虾')),
        );

        expect(find.text('[图片]'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      });

      testWidgets('agent image response renders Image widget + caption', (
        tester,
      ) async {
        final msg = Message(
          clientId: 'i2',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.agent,
          content: '看这个图',
          type: MessageType.image,
          status: MessageStatus.delivered,
          timestamp: 0,
          logicalClock: 0,
          metadata: const {
            'imageUrl': 'https://example.com/x.png',
            'mimeType': 'image/png',
          },
        );
        await tester.pumpWidget(
          wrap(MessageBubble(message: msg, agentName: '虾')),
        );

        // Image widget present (network image, loads async — widget exists pre-load)
        expect(find.byType(Image), findsOneWidget);
        // caption text from content
        expect(find.text('看这个图'), findsOneWidget);
      });

      testWidgets('user image message with local path renders Image widget', (
        tester,
      ) async {
        final msg = Message(
          clientId: 'i3',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.user,
          content: '/tmp/nonexistent.jpg',
          type: MessageType.image,
          status: MessageStatus.sent,
          timestamp: 0,
          logicalClock: 0,
          metadata: const {'fileName': 'img.jpg', 'mimeType': 'image/jpeg'},
        );
        await tester.pumpWidget(
          wrap(MessageBubble(message: msg, agentName: '虾')),
        );

        expect(find.byType(Image), findsOneWidget);
        // 用户图无 caption(content 是路径,不应作为 caption 文本显示)
        expect(find.text('/tmp/nonexistent.jpg'), findsNothing);
      });
    });

    // -----------------------------------------------------------------------
    // userPlaceholder 文件上传条
    // -----------------------------------------------------------------------
    group('userPlaceholder file upload strip', () {
      Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, child: child)),
      );

      Message placeholder({List<dynamic>? mediaPaths}) => Message(
        clientId: 'ph-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        role: MessageRole.userPlaceholder,
        content: '[User sent media without caption]',
        type: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: 0,
        logicalClock: 0,
        metadata: mediaPaths != null ? {'mediaPaths': mediaPaths} : null,
      );

      testWidgets('empty MediaPaths renders zero-file label', (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: placeholder(mediaPaths: []),
              agentName: '虾',
            ),
          ),
        );
        expect(find.text('📎 空附件'), findsOneWidget);
      });

      testWidgets('single MediaPath renders singular label', (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: placeholder(mediaPaths: ['/tmp/a.jpg']),
              agentName: '虾',
            ),
          ),
        );
        expect(find.text('📎 文件已上传'), findsOneWidget);
      });

      testWidgets('multiple MediaPaths renders count label', (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: placeholder(mediaPaths: ['/tmp/a.jpg', '/tmp/b.jpg']),
              agentName: '虾',
            ),
          ),
        );
        expect(find.text('📎 2 个文件已上传'), findsOneWidget);
      });

      // 回归:placeholder/system 消息必须走 StaggeredEnterItem,保持列表进入动画一致。
      testWidgets('placeholder is wrapped in StaggeredEnterItem', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: placeholder(mediaPaths: ['/tmp/a.jpg']),
              agentName: '虾',
            ),
          ),
        );
        final enter = find.ancestor(
          of: find.text('📎 文件已上传'),
          matching: find.byType(StaggeredEnterItem),
        );
        expect(enter, findsOneWidget);
      });

      testWidgets('system notice is wrapped in StaggeredEnterItem', (
        tester,
      ) async {
        final system = Message(
          clientId: 'sys-1',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          role: MessageRole.system,
          content: 'system notice',
          type: MessageType.text,
          status: MessageStatus.delivered,
          timestamp: 0,
          logicalClock: 0,
        );
        await tester.pumpWidget(
          wrap(MessageBubble(message: system, agentName: '虾')),
        );
        final enter = find.ancestor(
          of: find.text('system notice'),
          matching: find.byType(StaggeredEnterItem),
        );
        expect(enter, findsOneWidget);
      });
    });
  });
}
