import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Streaming text bubble — shows Agent reply text as it arrives in real time.
///
/// Visually identical to [MessageBubble] (Agent side) except:
/// - No timestamp (response still in progress)
/// - Blinking cursor at end to indicate live generation
/// - Debounced MarkdownBody rebuild (150ms) to avoid frame drops on mid-range devices
/// - Height-constrained with internal scroll to prevent input-bar displacement
/// - Image rendering disabled (security: prevents exfiltration via external URLs)
///
/// **Enter animation (B4)**: 350ms opacity + slide via [StaggeredEnterItem].
class StreamingBubble extends StatefulWidget {
  final String text;
  final String agentName;

  const StreamingBubble({
    super.key,
    required this.text,
    required this.agentName,
  });

  @override
  State<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  /// Debounced text — updated at most every 150ms to limit MarkdownBody re-parses.
  String _renderedText = '';

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Cursor blink duration (B4: changed from 600ms to durationFast).
    _cursorController = AnimationController(
      vsync: this,
      duration: XiaMotion.durationFast,
    )..repeat(reverse: true);

    _renderedText = widget.text;
  }

  @override
  void didUpdateWidget(covariant StreamingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() {
            _renderedText = widget.text;
          });
        }
      });
      // Overflow protection: force update if accumulation exceeds threshold
      if (widget.text.length - _renderedText.length > 200) {
        _debounceTimer?.cancel();
        if (mounted) {
          setState(() {
            _renderedText = widget.text;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    final maxBubbleHeight = viewportHeight * 0.4;

    return StaggeredEnterItem(
      index: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s6,
          vertical: 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Agent mini avatar (matches MessageBubble)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(XiaRadius.sm),
                color: XiaColors.accentMuted,
              ),
              alignment: Alignment.center,
              child: Text(
                widget.agentName.characters.first,
                style: const TextStyle(
                  fontSize: 12,
                  color: XiaColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: XiaSpacing.s2),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBubbleHeight),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: XiaSpacing.s5,
                    vertical: XiaSpacing.s3,
                  ),
                  decoration: BoxDecoration(
                    color: XiaColors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(XiaRadius.xl),
                      topRight: Radius.circular(XiaRadius.xl),
                      bottomRight: Radius.circular(XiaRadius.xl),
                      bottomLeft: Radius.circular(XiaRadius.sm),
                    ),
                    boxShadow: XiaShadow.s,
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: _renderedText,
                          selectable: true,
                          sizedImageBuilder: (_) => const SizedBox.shrink(),
                          styleSheet: _markdownStyle(),
                        ),
                        const SizedBox(height: 2),
                        AnimatedBuilder(
                          animation: _cursorController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: _cursorController.value,
                              child: const SizedBox(
                                width: _CursorPainter.cursorWidth,
                                height: _CursorPainter.cursorHeight,
                                child: CustomPaint(painter: _CursorPainter()),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle() => MarkdownStyleSheet(
    p: const TextStyle(color: XiaColors.text1, fontSize: 15, height: 1.6),
    code: const TextStyle(
      backgroundColor: XiaColors.codeBlockBg,
      color: XiaColors.accent,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    strong: const TextStyle(fontWeight: FontWeight.bold),
  );
}

/// Paints the blinking text cursor as a filled rounded rectangle.
///
/// Replaces a Unicode block character (U+258A ▊) whose rendering varies
/// across platform fonts.  [CustomPaint] guarantees identical appearance
/// on iOS, Android, and desktop.
class _CursorPainter extends CustomPainter {
  const _CursorPainter();

  /// Cursor width in logical pixels.
  static const double cursorWidth = 2.5;

  /// Cursor height in logical pixels — matches the 15px body text size.
  static const double cursorHeight = 15;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = XiaColors.accent
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, cursorWidth, cursorHeight),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
