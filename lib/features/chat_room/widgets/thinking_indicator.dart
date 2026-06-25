import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, border.
/// Dots: 6×6, AgentTheme.of(context).primary (full opacity), 800ms bounce cycle,
/// staggered delays.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = AgentTheme.of(context).primary;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 4,
      ),
      child: Row(
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: XiaColors.surface2,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(XiaRadius.xl),
                topRight: Radius.circular(XiaRadius.xl),
                bottomRight: Radius.circular(XiaRadius.xl),
                bottomLeft: Radius.circular(XiaRadius.xs),
              ),
              border: Border.all(color: XiaColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BouncingDot(
                  controller: _controller,
                  delay: 0.0,
                  dotColor: dotColor,
                ),
                const SizedBox(width: 4),
                _BouncingDot(
                  controller: _controller,
                  delay: 0.15,
                  dotColor: dotColor,
                ),
                const SizedBox(width: 4),
                _BouncingDot(
                  controller: _controller,
                  delay: 0.3,
                  dotColor: dotColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BouncingDot extends StatelessWidget {
  final AnimationController controller;
  final double delay; // seconds
  final Color dotColor;

  const _BouncingDot({
    required this.controller,
    required this.delay,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    final delayFraction = delay / 0.8;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
        // V2: 0-40%: translateY(-6px), 40-80%: back, 80-100%: rest
        final y = t < 0.4
            ? -6.0 * (t / 0.4)
            : t < 0.8
            ? -6.0 + 6.0 * ((t - 0.4) / 0.4)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, y),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              // Dot color from AgentTheme.of(context).primary (spec §4.3)
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
