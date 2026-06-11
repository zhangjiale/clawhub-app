import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Custom [PageTransitionsBuilder] matching the design spec page transition.
///
/// Forward navigation: incoming page slides in from right (100%→0),
/// outgoing page shifts left -30% with opacity fade.
/// Back navigation: reverse of forward.
///
/// Transform: 500ms XiaMotion.ease. Opacity: 350ms XiaMotion.ease.
/// This staggered timing creates a "fast fade, slow slide" rhythm.
class XiaPageTransitionsBuilder extends PageTransitionsBuilder {
  const XiaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: XiaMotion.ease,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0), // start 100% right
        end: Offset.zero,
      ).animate(curvedAnimation),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: XiaMotion.ease,
            reverseCurve: XiaMotion.easeOut,
          ),
        ),
        child: child,
      ),
    );
  }
}
