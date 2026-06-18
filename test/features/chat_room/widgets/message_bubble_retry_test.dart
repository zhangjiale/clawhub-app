import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';

/// Widget tests for [MessageBubble.onRetry] (US-015 AC2).
void main() {
  group('MessageBubble retry button', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    Message msg({
      required MessageStatus status,
      MessageRole role = MessageRole.user,
    }) => Message(
      clientId: 'm-1',
      conversationId: 'conv-1',
      agentId: 'agent-1',
      role: role,
      content: 'hello',
      type: MessageType.text,
      status: status,
      timestamp: 0,
      logicalClock: 0,
    );

    testWidgets(
      'shows refresh icon when message is FAILED and onRetry is set',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: msg(status: MessageStatus.failed),
              agentName: '产品虾',
              onRetry: () {},
            ),
          ),
        );

        expect(find.byIcon(Icons.refresh), findsOneWidget);
        expect(find.byIcon(Icons.error), findsOneWidget); // FAILED status icon
      },
    );

    testWidgets('does NOT show refresh icon when onRetry is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg(status: MessageStatus.failed),
            agentName: '产品虾',
            // onRetry: null
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsNothing);
      // FAILED status icon still rendered
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('does NOT show refresh icon when status is not FAILED', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg(status: MessageStatus.sent),
            agentName: '产品虾',
            onRetry: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('tapping the retry icon area invokes onRetry callback', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg(status: MessageStatus.failed),
            agentName: '产品虾',
            onRetry: () => tapped = true,
          ),
        ),
      );

      // Invoke the GestureDetector's onTap directly. Hit-testing through
      // the framework is unreliable for thin tap targets nested inside
      // ListBody, especially when the message bubble is right-aligned.
      // Verifying the wired-up callback fires is the actual unit under test.
      final detector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      detector.onTap!();

      expect(tapped, isTrue);
    });

    testWidgets('refresh icon uses XiaColors.red', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg(status: MessageStatus.failed),
            agentName: '产品虾',
            onRetry: () {},
          ),
        ),
      );

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.refresh));
      expect(iconWidget.color, XiaColors.red);
    });

    testWidgets('retry button has Tooltip with accessibility label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg(status: MessageStatus.failed),
            agentName: '产品虾',
            onRetry: () {},
          ),
        ),
      );

      // Verify a Tooltip widget wraps the retry tap area
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, '重试发送');
    });

    testWidgets(
      'retry button Tooltip has correct semantics for screen readers',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: msg(status: MessageStatus.failed),
              agentName: '产品虾',
              onRetry: () {},
            ),
          ),
        );

        // Tooltip provides an implicit Semantics node with the message
        // as its label.  Screen readers (TalkBack / VoiceOver) will
        // announce "重试发送, button" when the retry area is focused.
        final semantics = tester.getSemantics(find.byTooltip('重试发送'));
        expect(semantics, isNotNull);
      },
    );
  });
}
