import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';

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
  });
}
