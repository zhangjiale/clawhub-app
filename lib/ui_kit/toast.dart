import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// A pill-shaped, glassmorphism-backed toast notification displayed at the
/// top-center of the screen (72px from top), matching the design spec.
///
/// Auto-dismisses after 2500ms. Uses [BackdropFilter] for glassmorphism effect.
class XiaToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  /// Show a toast message. If a toast is already visible, it is replaced.
  static void show(BuildContext context, String message) {
    _dismiss();

    final overlay = Overlay.of(context);
    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 72,
        left: 0,
        right: 0,
        child: Center(
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
                  message,
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
    );

    overlay.insert(_currentEntry!);

    _dismissTimer = Timer(const Duration(milliseconds: 2500), _dismiss);
  }

  static void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}
