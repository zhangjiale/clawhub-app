import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

// =============================================================================
// PressFeedback — generic press-feedback wrapper (Single Source of Truth)
// =============================================================================

/// Generic press-feedback wrapper. Encapsulates the common
/// `onTapDown → setState → AnimatedScale + AnimatedContainer` pattern
/// into one reusable widget, eliminating `_isPressed` boilerplate.
///
/// **Simple usage** — scale + background color change:
/// ```dart
/// PressFeedback(
///   scale: 0.98,
///   pressedColor: XiaColors.surface2,
///   normalColor: XiaColors.surface,
///   borderRadius: BorderRadius.circular(XiaRadius.lg),
///   onTap: () => ...,
///   child: Padding(...card content...),
/// )
/// ```
///
/// **Builder usage** — for opacity, border, or multi-property changes:
/// ```dart
/// PressFeedback(
///   onTap: () => ...,
///   builder: (child, isPressed) => AnimatedOpacity(
///     opacity: isPressed ? 0.5 : 1.0,
///     duration: XiaMotion.durationFast,
///     child: child,
///   ),
///   child: Row(...),
/// )
/// ```
///
/// When [builder] is provided, [scale], [pressedColor], and [margin] are
/// ignored — the builder takes full control of the pressed appearance.
class PressFeedback extends StatefulWidget {
  /// The widget tree to apply press feedback to.
  final Widget child;

  /// Called on tap. When null, no gesture detection is added.
  final VoidCallback? onTap;

  /// Called on long press.
  final VoidCallback? onLongPress;

  /// Scale factor applied via [AnimatedScale] when pressed (default 1.0).
  final double scale;

  /// Background color applied via [AnimatedContainer] when pressed.
  /// When set, wraps [child] in AnimatedContainer with [borderRadius].
  final Color? pressedColor;

  /// Normal background color (defaults to [Colors.transparent]).
  final Color? normalColor;

  /// Border radius for the AnimatedContainer when [pressedColor] is set.
  final BorderRadius? borderRadius;

  /// Outer margin applied to the AnimatedContainer wrapper.
  final EdgeInsetsGeometry? margin;

  /// Animation duration.
  final Duration duration;

  /// Animation curve.
  final Curve curve;

  /// GestureDetector behavior.
  final HitTestBehavior? behavior;

  /// Escape hatch for complex press effects (opacity, border, multi-color).
  /// When provided, [scale], [pressedColor], and [margin] are ignored.
  final Widget Function(Widget child, bool isPressed)? builder;

  const PressFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 1.0,
    this.pressedColor,
    this.normalColor,
    this.borderRadius,
    this.margin,
    this.duration = XiaMotion.durationFast,
    this.curve = XiaMotion.ease,
    this.behavior,
    this.builder,
  });
  // coverage:ignore-line

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _isPressed = false;

  void _onDown(_) {
    if (widget.onTap != null || widget.onLongPress != null) {
      if (mounted) setState(() => _isPressed = true);
    }
  }

  void _onUp(_) {
    if (mounted) setState(() => _isPressed = false);
  }

  void _onCancel() {
    if (mounted) setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = widget.child;

    if (widget.builder != null) {
      result = widget.builder!(result, _isPressed);
    } else {
      // Apply background color if configured
      if (widget.pressedColor != null) {
        result = AnimatedContainer(
          duration: widget.duration,
          curve: widget.curve,
          margin: widget.margin,
          decoration: BoxDecoration(
            color: _isPressed
                ? widget.pressedColor!
                : (widget.normalColor ?? Colors.transparent),
            borderRadius: widget.borderRadius,
          ),
          child: result,
        );
      } else if (widget.margin != null) {
        result = Padding(padding: widget.margin!, child: result);
      }

      // Apply scale if configured
      if (widget.scale != 1.0) {
        result = AnimatedScale(
          scale: _isPressed ? widget.scale : 1.0,
          duration: widget.duration,
          curve: widget.curve,
          child: result,
        );
      }
    }

    // Only wrap in GestureDetector if there's something to detect
    if (widget.onTap != null || widget.onLongPress != null) {
      result = GestureDetector(
        onTapDown: _onDown,
        onTapUp: _onUp,
        onTapCancel: _onCancel,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        behavior: widget.behavior,
        child: result,
      );
    }

    return result;
  }
}

// =============================================================================
// Semantic Buttons (built on PressFeedback)
// =============================================================================

/// Press-feedback wrapper for AppBar action buttons (header-btn).
///
/// Spec: 40×40, r-md, bg surface2→surface3, scale(0.95), icon text2,
/// 200ms XiaMotion.ease.
class HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const HeaderButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = PressFeedback(
      scale: 0.95,
      pressedColor: XiaColors.surface3,
      normalColor: XiaColors.surface2,
      borderRadius: BorderRadius.circular(XiaRadius.md),
      onTap: onPressed,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 20, color: XiaColors.text2),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Press-feedback back button for AppBar leading slots.
///
/// Spec: 40×40, r-md, bg transparent→surface2, scale(0.95), icon text2,
/// 200ms XiaMotion.ease.
class XiaBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const XiaBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scale: 0.95,
      pressedColor: XiaColors.surface2,
      normalColor: Colors.transparent,
      borderRadius: BorderRadius.circular(XiaRadius.md),
      onTap: onPressed,
      child: const SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.arrow_back, size: 22, color: XiaColors.text2),
      ),
    );
  }
}

// =============================================================================
// StaggeredEnterItem — lightweight enter animation (no AnimationController)
// =============================================================================

/// Wraps a list item with staggered enter animation using implicit
/// [AnimatedSlide] + [AnimatedOpacity], triggered after a per-index delay.
///
/// Unlike the per-item [AnimationController] + [Timer] approach, this widget
/// only holds a single `_entered` boolean — no TickerProvider, no dispose.
///
/// ```dart
/// ListView.builder(
///   itemBuilder: (context, i) => StaggeredEnterItem(
///     index: i,
///     child: MyCard(...),
///   ),
/// )
/// ```
class StaggeredEnterItem extends StatefulWidget {
  /// Zero-based position in the list (controls stagger delay).
  final int index;

  /// The item widget to animate in.
  final Widget child;

  /// Full enter animation duration (default: 350ms).
  final Duration duration;

  /// Per-item incremental delay (default: 40ms).
  final Duration delayPerItem;

  /// Maximum total delay (default: 200ms = 5 items × 40ms).
  final Duration maxDelay;

  /// Starting slide offset (default: (0, 0.06) ≈ 12–20px up).
  final Offset beginOffset;

  const StaggeredEnterItem({
    super.key,
    required this.index,
    required this.child,
    this.duration = XiaMotion.durationMid,
    this.delayPerItem = const Duration(milliseconds: 40),
    this.maxDelay = const Duration(milliseconds: 200),
    this.beginOffset = const Offset(0, 0.06),
  });

  @override
  State<StaggeredEnterItem> createState() => _StaggeredEnterItemState();
}

class _StaggeredEnterItemState extends State<StaggeredEnterItem> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.index * widget.delayPerItem.inMilliseconds).clamp(
      0,
      widget.maxDelay.inMilliseconds,
    );
    if (delayMs > 0) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) setState(() => _entered = true);
      });
    } else {
      // Set immediately — no Future.delayed for index 0.
      // Must use post-frame callback to let first build complete.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _entered = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _entered ? Offset.zero : widget.beginOffset,
      duration: widget.duration,
      curve: XiaMotion.ease,
      child: AnimatedOpacity(
        opacity: _entered ? 1.0 : 0.0,
        duration: widget.duration,
        curve: XiaMotion.ease,
        child: widget.child,
      ),
    );
  }
}

/// Press-feedback primary/save button matching spec Section 6.7.
///
/// Spec: 100% width, 52px height, r-md, accent bg, white text,
/// scale(0.97) + brightness(0.92) on press, 200ms ease.
/// Also includes accent-glow box-shadow.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return PressFeedback(
      onTap: enabled ? onPressed : null,
      builder: (child, isPressed) => AnimatedScale(
        scale: isPressed ? 0.97 : 1.0,
        duration: XiaMotion.durationFast,
        curve: XiaMotion.ease,
        child: AnimatedContainer(
          duration: XiaMotion.durationFast,
          curve: XiaMotion.ease,
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: !enabled
                ? XiaColors.surface2
                : isPressed
                ? Color.lerp(XiaColors.accent, Colors.black, 0.08)!
                : XiaColors.accent,
            borderRadius: BorderRadius.circular(XiaRadius.md),
            boxShadow: enabled ? XiaShadow.accentGlow : null,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: XiaColors.text1,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                color: XiaColors.text1,
                fontSize: XiaTypography.body,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
    );
  }
}
