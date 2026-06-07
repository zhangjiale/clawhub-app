import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';

void main() {
  group('ChatInputBar', () {
    Widget buildBar({ValueChanged<String>? onSend}) {
      return MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            onSend: onSend ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('renders text field', (tester) async {
      await tester.pumpWidget(buildBar());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders send button', (tester) async {
      await tester.pumpWidget(buildBar());
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('clears text after send', (tester) async {
      await tester.pumpWidget(buildBar());
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      // Text field should be cleared
      expect(find.text('Hello'), findsNothing);
    });

    testWidgets('calls onSend with entered text', (tester) async {
      String? sent;
      await tester.pumpWidget(buildBar(onSend: (text) => sent = text));
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(sent, 'Test message');
    });

    testWidgets('does not call onSend when text is empty', (tester) async {
      String? sent;
      await tester.pumpWidget(buildBar(onSend: (text) => sent = text));
      await tester.tap(find.byIcon(Icons.send));
      expect(sent, isNull);
    });

    testWidgets('trims whitespace before sending', (tester) async {
      String? sent;
      await tester.pumpWidget(buildBar(onSend: (text) => sent = text));
      await tester.enterText(find.byType(TextField), '  hello  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(sent, 'hello');
    });
  });
}
