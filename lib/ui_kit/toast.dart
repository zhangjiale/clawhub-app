import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// A pill-shaped, glassmorphism-backed toast notification displayed at the
/// top-center of the screen (72px from top), matching the design spec.
///
/// **Animation (B1)**: 350ms translateY(-20px→0) + opacity(0→1) on enter,
/// reverse on dismiss. Auto-dismiss after 2500ms.
///
/// Uses [BackdropFilter] for glassmorphism effect matching the design spec.
class XiaToast {
  static OverlayEntry? _currentEntry;

  /// Show a toast message. If a toast is already visible, it is replaced.
  static void show(BuildContext context, String message) {
    _dismiss();

    final overlay = Overlay.of(context);
    _currentEntry = OverlayEntry(
      builder: (context) => _ToastOverlay(
        message: message,
        onDismissComplete: () {
          _currentEntry?.remove();
          _currentEntry = null;
        },
      ),
    );

    overlay.insert(_currentEntry!);
  }

  static void _dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

/// Stateful overlay widget with enter/exit animation.
class _ToastOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onDismissComplete;

  const _ToastOverlay({required this.message, required this.onDismissComplete});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: XiaMotion.durationMid, // 350ms
    );
    _opacity = CurvedAnimation(parent: _controller, curve: XiaMotion.ease);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: XiaMotion.ease));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Start auto-dismiss timer after enter animation finishes
        _dismissTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) _controller.reverse();
        });
      } else if (status == AnimationStatus.dismissed) {
        // Remove overlay entry after exit animation finishes
        widget.onDismissComplete();
      }
    });

    // Auto-play enter animation.
    _controller.forward();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 72,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _slide,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(XiaRadius.full),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: XiaGlass.toastBlur,
                  sigmaY: XiaGlass.toastBlur,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: XiaSpacing.s6,
                    vertical: XiaSpacing.s3,
                  ),
                  decoration: BoxDecoration(
                    color: XiaColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(XiaRadius.full),
                    boxShadow: XiaShadow.l,
                  ),
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: XiaColors.text1,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
