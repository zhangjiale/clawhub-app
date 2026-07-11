// Widget tests for [MessageOmittedContent] - the "tap to load" bubble rendered
// for chat.history omitted placeholders (metadata.contentOmitted = true).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/widgets/message_omitted_content.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';

void main() {
  group('MessageOmittedContent', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    Message omittedMsg() => Message(
      clientId: 'm-1',
      serverId: 'srv-1',
      conversationId: 'conv-1',
      agentId: 'r-1',
      role: MessageRole.agent,
      content: '[chat.history omitted: message too large]',
      type: MessageType.text,
      status: MessageStatus.delivered,
      logicalClock: 0,
      metadata: const {'contentOmitted': true},
    );

    testWidgets('idle state renders the tap-to-load prompt', (tester) async {
      await tester.pumpWidget(
        wrap(MessageOmittedContent(message: omittedMsg(), onLoad: () async {})),
      );

      expect(find.textContaining('消息过大'), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tap invokes onLoad and shows a spinner while in flight', (
      tester,
    ) async {
      final completer = Completer<void>();
      var callCount = 0;
      Future<void> onLoad() async {
        callCount++;
        await completer.future;
      }

      await tester.pumpWidget(
        wrap(MessageOmittedContent(message: omittedMsg(), onLoad: onLoad)),
      );

      await tester.tap(find.byType(MessageOmittedContent));
      await tester.pump();

      expect(callCount, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the load; the spinner disappears.
      completer.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a second tap while loading is ignored (dedup)', (
      tester,
    ) async {
      final completer = Completer<void>();
      var callCount = 0;
      Future<void> onLoad() async {
        callCount++;
        await completer.future;
      }

      await tester.pumpWidget(
        wrap(MessageOmittedContent(message: omittedMsg(), onLoad: onLoad)),
      );

      await tester.tap(find.byType(MessageOmittedContent));
      await tester.pump();
      await tester.tap(find.byType(MessageOmittedContent));
      await tester.pump();

      expect(callCount, 1, reason: 'second tap must not fire a second load');
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('onLoad failure shows 加载失败 and allows retry', (tester) async {
      var callCount = 0;
      Future<void> onLoad() async {
        callCount++;
        throw Exception('boom');
      }

      await tester.pumpWidget(
        wrap(MessageOmittedContent(message: omittedMsg(), onLoad: onLoad)),
      );

      await tester.tap(find.byType(MessageOmittedContent));
      await tester.pumpAndSettle();

      expect(find.textContaining('加载失败'), findsOneWidget);
      expect(callCount, 1);

      // Retry path: tapping again fires onLoad again.
      await tester.tap(find.byType(MessageOmittedContent));
      await tester.pumpAndSettle();
      expect(callCount, 2);
    });
  });

  group('MessageBubble omitted-flag wiring', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    Message omittedMsg() => Message(
      clientId: 'm-1',
      serverId: 'srv-1',
      conversationId: 'conv-1',
      agentId: 'r-1',
      role: MessageRole.agent,
      content: '[chat.history omitted: message too large]',
      type: MessageType.text,
      status: MessageStatus.delivered,
      logicalClock: 0,
      metadata: const {'contentOmitted': true},
    );

    testWidgets(
      'renders MessageOmittedContent when flag set + onLoadFull wired',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: omittedMsg(),
              agentName: '产品虾',
              onLoadFull: () async {},
            ),
          ),
        );
        expect(find.byType(MessageOmittedContent), findsOneWidget);
        expect(find.textContaining('消息过大'), findsOneWidget);
      },
    );

    testWidgets('falls back to placeholder text when onLoadFull is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: omittedMsg(),
            agentName: '产品虾',
            // onLoadFull deliberately null - no VM context (e.g. tests).
          ),
        ),
      );
      expect(find.byType(MessageOmittedContent), findsNothing);
      // The raw placeholder string still renders as markdown/text content.
      expect(find.textContaining('chat.history omitted'), findsOneWidget);
    });
  });
}
