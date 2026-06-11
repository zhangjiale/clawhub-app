import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, shadow-s.
/// Dots: 6×6, text3 color, 800ms bounce cycle, staggered delays.
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 4,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: XiaColors.accentMuted,
              borderRadius: BorderRadius.circular(XiaRadius.sm),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.psychology,
              size: 16,
              color: XiaColors.accent,
            ),
          ),
          const SizedBox(width: XiaSpacing.s2),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: XiaSpacing.s5,
              vertical: XiaSpacing.s4,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BouncingDot(controller: _controller, delay: 0.0),
                const SizedBox(width: 4),
                _BouncingDot(controller: _controller, delay: 0.15),
                const SizedBox(width: 4),
                _BouncingDot(controller: _controller, delay: 0.3),
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

  const _BouncingDot({
    required this.controller,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final delayFraction = delay / 0.8;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
        // 0-40%: translateY(-8px), 40-80%: back, 80-100%: rest
        final y = t < 0.4
            ? -8.0 * (t / 0.4)
            : t < 0.8
                ? -8.0 + 8.0 * ((t - 0.4) / 0.4)
                : 0.0;
        return Transform.translate(
          offset: Offset(0, y),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: XiaColors.text3,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
