import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/widgets/message_file_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for [MessageFileContent] (Law 14: ≥2 tests per new widget).
///
/// Created BEFORE its source counterpart to satisfy test-first flow.
void main() {
  group('MessageFileContent', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, child: child)),
    );

    testWidgets('renders fileName + formatted size', (tester) async {
      final msg = Message(
        clientId: 'f1',
        conversationId: 'conv',
        agentId: 'a',
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
        wrap(MessageFileContent(message: msg, isUser: true)),
      );

      expect(find.text('doc.pdf'), findsOneWidget);
      expect(find.text('12.0 KB'), findsOneWidget);
    });

    testWidgets('null path + null name → [文件] placeholder', (tester) async {
      final msg = Message(
        clientId: 'f2',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.user,
        content: null,
        type: MessageType.file,
        status: MessageStatus.sent,
        timestamp: 0,
        logicalClock: 0,
      );
      await tester.pumpWidget(
        wrap(MessageFileContent(message: msg, isUser: true)),
      );

      expect(find.text('[文件]'), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
    });

    testWidgets('renders without crashing when fileSize is null', (
      tester,
    ) async {
      final msg = Message(
        clientId: 'f3',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.user,
        content: '/tmp/doc.pdf',
        type: MessageType.file,
        status: MessageStatus.sent,
        timestamp: 0,
        logicalClock: 0,
        metadata: const {'fileName': 'doc.pdf', 'mimeType': 'application/pdf'},
      );
      await tester.pumpWidget(
        wrap(MessageFileContent(message: msg, isUser: false)),
      );

      expect(find.text('doc.pdf'), findsOneWidget);
      // No size text rendered when fileSize is null.
      expect(find.text('12.0 KB'), findsNothing);
    });
  });
}
