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
    // LayoutBuilder caches the parent-constrained maxWidth; reading
    // MediaQuery inside build() would re-multiply per AnimationController
    // tick (60Hz over the 800ms cycle).
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 4,
      ),
      child: Row(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final maxBubbleWidth = constraints.maxWidth * 0.7;
              return Container(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                // Single AnimatedBuilder drives all three dots — previously
                // each dot had its own listener, causing 3 widget rebuilds
                // per tick instead of 1.
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Row(
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
                    );
                  },
                ),
              );
            },
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
    // Phase offset as a fraction of the 800ms cycle (must match controller
    // duration if changed). Avoids re-deriving inside the AnimatedBuilder.
    final delayFraction = delay / 0.8;
    return Transform.translate(
      offset: Offset(0, _bounceY(controller.value + delayFraction)),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
      ),
    );
  }

  /// V2 bounce envelope: 0-40% translateY(-6px), 40-80% back, 80-100% rest.
  /// Pure function so AnimatedBuilder rebuilds don't reallocate closures.
  static double _bounceY(double t) {
    final phase = t % 1.0;
    if (phase < 0.4) return -6.0 * (phase / 0.4);
    if (phase < 0.8) return -6.0 + 6.0 * ((phase - 0.4) / 0.4);
    return 0.0;
  }
}
