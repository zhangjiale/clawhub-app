import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';

void main() {
  group('ChatInputBar attach button', () {
    testWidgets('no "+" button when onPickAttachment is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatInputBar(onSend: (_) {})),
        ),
      );
      // Icons.add 是 "+" 按钮的图标;onPickAttachment=null 时不渲染
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets(
      'renders "+" button and opens AttachmentSheet when onPickAttachment set',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatInputBar(onSend: (_) {}, onPickAttachment: (_) {}),
            ),
          ),
        );
        expect(find.byIcon(Icons.add), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        // AttachmentSheet 弹出,三个选项可见
        expect(find.text('相册'), findsOneWidget);
        expect(find.text('文件'), findsOneWidget);
      },
    );

    testWidgets('onSend still fires for text input', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(onSend: sent.add, onPickAttachment: (_) {}),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '你好');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(sent, ['你好']);
    });
  });
}
