import 'package:flutter/material.dart';

/// "虾思考中" 加载动画组件
/// 三点跳动动画，表示 Agent 正在处理消息
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
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Agent mini avatar placeholder
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.psychology,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BouncingDot(
                  key: const ValueKey('thinking-dot-0'),
                  controller: _controller,
                  delay: 0,
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
                const SizedBox(width: 4),
                _BouncingDot(
                  key: const ValueKey('thinking-dot-1'),
                  controller: _controller,
                  delay: 200,
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
                const SizedBox(width: 4),
                _BouncingDot(
                  key: const ValueKey('thinking-dot-2'),
                  controller: _controller,
                  delay: 400,
                  color: theme.colorScheme.onSurface.withAlpha(150),
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
  final int delay; // milliseconds
  final Color color;

  const _BouncingDot({
    super.key,
    required this.controller,
    required this.delay,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final delayFraction = delay / 1200.0;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
        // Sine wave for smooth bounce
        final scale = 0.5 + 0.5 * _bounce(t);
        final opacity = 0.3 + 0.7 * _bounce(t);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }

  double _bounce(double t) {
    // Bounce easing: fast up, slow down
    if (t < 0.5) {
      return t * 2.0;
    } else {
      return 2.0 - t * 2.0;
    }
  }
}
