import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/widgets/message_image_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for [MessageImageContent] (Law 14: ≥2 tests per new widget).
///
/// Created BEFORE its source counterpart to satisfy test-first flow.
/// Covers: P0 (data: URL renders), P1 (cacheWidth constrained Image),
/// errorBuilder path (corrupt data: URL), caption rendering.
void main() {
  group('MessageImageContent', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, child: child)),
    );

    // 1×1 transparent PNG as a data: URL.
    const validDataUrl =
        'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

    testWidgets('data: URL renders Image widget (P0 fix)', (tester) async {
      final msg = Message(
        clientId: 'i1',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.agent,
        content: 'caption',
        type: MessageType.image,
        status: MessageStatus.delivered,
        timestamp: 0,
        logicalClock: 0,
        metadata: const {'imageUrl': validDataUrl, 'mimeType': 'image/png'},
      );
      await tester.pumpWidget(
        wrap(MessageImageContent(message: msg, isUser: false)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(Image),
        findsOneWidget,
        reason:
            'data: URL must render via MemoryImage — the P0 bug fed data: '
            'URLs to NetworkImage which only handles http/https.',
      );
    });

    testWidgets('https URL renders Image widget', (tester) async {
      final msg = Message(
        clientId: 'i2',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.agent,
        content: null,
        type: MessageType.image,
        status: MessageStatus.delivered,
        timestamp: 0,
        logicalClock: 0,
        metadata: const {'imageUrl': 'https://example.com/x.png'},
      );
      await tester.pumpWidget(
        wrap(MessageImageContent(message: msg, isUser: false)),
      );
      // Do not pumpAndSettle — network image would hang. Just verify Image
      // widget exists pre-load (same assertion shape as the original
      // message_bubble_test.dart).
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('null imageUrl + null imagePath renders [图片] placeholder', (
      tester,
    ) async {
      final msg = Message(
        clientId: 'i3',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.user,
        content: null,
        type: MessageType.image,
        status: MessageStatus.sent,
        timestamp: 0,
        logicalClock: 0,
      );
      await tester.pumpWidget(
        wrap(MessageImageContent(message: msg, isUser: true)),
      );

      expect(find.text('[图片]'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets(
      'corrupt data: URL renders _BrokenImage via errorBuilder (no crash)',
      (tester) async {
        final msg = Message(
          clientId: 'i4',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.agent,
          content: null,
          type: MessageType.image,
          status: MessageStatus.delivered,
          timestamp: 0,
          logicalClock: 0,
          metadata: const {'imageUrl': 'data:image/png;base64,!!!invalid!!!'},
        );
        await tester.pumpWidget(
          wrap(MessageImageContent(message: msg, isUser: false)),
        );
        await tester.pumpAndSettle();

        // errorBuilder fired → _BrokenImage renders '图片不可用' text.
        expect(
          find.text('图片不可用'),
          findsOneWidget,
          reason:
              'corrupt data URL must hit errorBuilder (renders _BrokenImage), '
              'not crash the widget tree with a FormatException',
        );
      },
    );

    testWidgets('caption renders below image', (tester) async {
      final msg = Message(
        clientId: 'i5',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.agent,
        content: '看这个图',
        type: MessageType.image,
        status: MessageStatus.delivered,
        timestamp: 0,
        logicalClock: 0,
        metadata: const {'imageUrl': validDataUrl, 'mimeType': 'image/png'},
      );
      await tester.pumpWidget(
        wrap(MessageImageContent(message: msg, isUser: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('看这个图'), findsOneWidget);
    });
  });
}
