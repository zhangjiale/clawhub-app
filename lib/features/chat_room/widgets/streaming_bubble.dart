import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Streaming text bubble — shows Agent reply text as it arrives in real time.
///
/// Visually identical to [MessageBubble] (Agent side) except:
/// - No timestamp (response still in progress)
/// - Blinking cursor at end to indicate live generation
/// - Debounced MarkdownBody rebuild (150ms) to avoid frame drops on mid-range devices
/// - Height-constrained with internal scroll to prevent input-bar displacement
/// - Image rendering disabled (security: prevents exfiltration via external URLs)
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
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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

    return Padding(
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
                        // Security: never fetch external images during
                        // streaming (prevents IP exfiltration).
                        sizedImageBuilder: (_) => const SizedBox.shrink(),
                        styleSheet: _markdownStyle(),
                      ),
                      // Blinking cursor below rendered markdown — using
                      // Column instead of Stack+Positioned so the cursor
                      // always sits at the text frontier, not at the
                      // bottom-right corner of a multi-line MarkdownBody.
                      const SizedBox(height: 2),
                      AnimatedBuilder(
                        animation: _cursorController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _cursorController.value,
                            child: const Text(
                              '▊',
                              style: TextStyle(
                                color: XiaColors.accent,
                                fontSize: 15,
                              ),
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
