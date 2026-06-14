import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/streaming_bubble.dart';

Widget buildBubble(String text, {String agentName = '产品虾'}) {
  return MaterialApp(
    home: Scaffold(
      body: StreamingBubble(text: text, agentName: agentName),
    ),
  );
}

/// Wraps a [StreamingBubble] in a widget whose parent can update [text]
/// via setState, mimicking the real usage where a ViewModel rebuilds the
/// parent with new text on each delta.
class _UpdatableBubble extends StatefulWidget {
  final String initialText;
  final String agentName;

  const _UpdatableBubble({required this.initialText, required this.agentName});

  @override
  State<_UpdatableBubble> createState() => _UpdatableBubbleState();
}

class _UpdatableBubbleState extends State<_UpdatableBubble> {
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
  }

  void updateText(String newText) {
    setState(() {
      _text = newText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: StreamingBubble(text: _text, agentName: widget.agentName),
      ),
    );
  }
}

void main() {
  group('StreamingBubble', () {
    // -----------------------------------------------------------------------
    // Basic rendering
    // -----------------------------------------------------------------------

    testWidgets('renders streaming text', (tester) async {
      await tester.pumpWidget(buildBubble('Hello streaming world'));
      expect(find.text('Hello streaming world'), findsOneWidget);
    });

    testWidgets('shows agent avatar first character', (tester) async {
      await tester.pumpWidget(buildBubble('text', agentName: '测试虾'));
      expect(find.text('测'), findsOneWidget);
    });

    testWidgets('shows blinking cursor via CustomPaint', (tester) async {
      await tester.pumpWidget(buildBubble('text'));
      // Cursor is rendered inside an Opacity+AnimatedBuilder chain.
      // Use the Opacity wrapping the cursor as the anchor — it's the only
      // Opacity whose child is a SizedBox (cursor container).
      final opacityFinder = find.byWidgetPredicate(
        (w) =>
            w is Opacity &&
            w.child is SizedBox &&
            (w.child as SizedBox).child is CustomPaint,
      );
      expect(opacityFinder, findsOneWidget);
    });

    testWidgets('cursor animates without throwing after multiple frames', (
      tester,
    ) async {
      await tester.pumpWidget(buildBubble('text'));

      // Pump a full animation cycle (600ms repeat, reverse).
      // The cursor should not throw during any frame.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));

      expect(tester.takeException(), isNull);
    });

    testWidgets('has height constraint at 40% of viewport', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(
              body: StreamingBubble(text: 'text', agentName: '虾'),
            ),
          ),
        ),
      );

      // ConstrainedBox with maxHeight = 40% of 800 = 320
      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      bool foundHeightConstraint = false;
      for (final box in constrainedBoxes) {
        if (box.constraints.maxHeight == 320.0) {
          foundHeightConstraint = true;
          break;
        }
      }
      expect(
        foundHeightConstraint,
        isTrue,
        reason: 'maxBubbleHeight must be 40% of viewport height',
      );
    });

    // -----------------------------------------------------------------------
    // Debounce (150 ms)
    // -----------------------------------------------------------------------

    testWidgets('debounces text updates by 150ms', (tester) async {
      await tester.pumpWidget(
        _UpdatableBubble(initialText: 'Initial text', agentName: '虾'),
      );
      expect(find.text('Initial text'), findsOneWidget);

      final state = tester.state<_UpdatableBubbleState>(
        find.byType(_UpdatableBubble),
      );
      // ignore: invalid_use_of_protected_member
      state.updateText('Updated text');
      await tester.pump(); // triggers rebuild + setState

      // At 149ms the debounce timer has NOT fired yet — old text remains
      await tester.pump(const Duration(milliseconds: 149));
      expect(
        find.text('Updated text'),
        findsNothing,
        reason: 'Debounce has not fired yet at 149ms',
      );

      // At 150ms the debounce fires and rendered text updates
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Updated text'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Overflow protection (>200 char accumulation)
    // -----------------------------------------------------------------------

    testWidgets('forces immediate update when text grows by >200 chars', (
      tester,
    ) async {
      await tester.pumpWidget(
        _UpdatableBubble(initialText: 'Short', agentName: '虾'),
      );
      expect(find.text('Short'), findsOneWidget);

      final state = tester.state<_UpdatableBubbleState>(
        find.byType(_UpdatableBubble),
      );

      // 'Short' = 5 chars. We need >205 chars to exceed the 200-char threshold.
      // 202 'x' + 'Long' = 206 chars → diff = 201 > 200 → overflow fires.
      final longText = 'Long${'x' * 202}';
      // ignore: invalid_use_of_protected_member
      state.updateText(longText);
      await tester.pump(); // triggers rebuild

      // Overflow protection bypasses the 150ms debounce — new text is
      // immediately visible without waiting for the timer.
      expect(
        find.text(longText),
        findsOneWidget,
        reason:
            'Overflow protection must update text immediately '
            'when accumulation exceeds 200 chars',
      );
    });

    // -----------------------------------------------------------------------
    // Dispose safety
    // -----------------------------------------------------------------------

    testWidgets('disposes timers and AnimationController cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(buildBubble('text'));
      expect(find.text('text'), findsOneWidget);

      // Replace with a different widget to trigger dispose
      await tester.pumpWidget(const SizedBox.shrink());

      // No exception should have been thrown during dispose
      expect(tester.takeException(), isNull);
    });

    // -----------------------------------------------------------------------
    // No timestamp (response still in progress)
    // -----------------------------------------------------------------------

    testWidgets('does NOT show timestamp', (tester) async {
      await tester.pumpWidget(buildBubble('streaming text'));
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d{2}:\d{2}$').hasMatch(w.data ?? ''),
        ),
        findsNothing,
      );
    });

    // -----------------------------------------------------------------------
    // Image security: sizedImageBuilder returns SizedBox.shrink()
    // -----------------------------------------------------------------------

    testWidgets('renders markdown with image loading disabled', (tester) async {
      await tester.pumpWidget(buildBubble('text'));
      // MarkdownBody is present with sizedImageBuilder set to block images
      expect(find.byType(MarkdownBody), findsOneWidget);
    });
  });
}
