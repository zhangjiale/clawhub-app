import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Custom [PageTransitionsBuilder] matching the design spec page transition.
///
/// Forward navigation: incoming page slides in from right (100%→0),
/// outgoing page shifts left -30% with opacity fade.
/// Back navigation: reverse of forward.
///
/// **Timing (B6)**: Transform uses the full route transition duration (400ms)
/// with XiaMotion.ease. Opacity uses Interval(0.0, 0.7) so the fade completes
/// in ~280ms of the 400ms total — matching the spec's "先快后慢" rhythm.
///
/// Use [XiaTransitionPage] in GoRouter pageBuilder to set the 400ms
/// transition duration on individual routes.
class XiaTransitionPage<T> extends Page<T> {
  final Widget child;

  const XiaTransitionPage({required this.child, super.key, super.name});

  @override
  Route<T> createRoute(BuildContext context) {
    return _XiaPageRoute<T>(builder: (_) => child, settings: this);
  }
}

/// Internal [MaterialPageRoute] with 400ms transition duration (V2).
class _XiaPageRoute<T> extends MaterialPageRoute<T> {
  _XiaPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration => XiaMotion.durationSlow; // 400ms (V2)
}

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
    // Slide: uses full animation duration (should be 400ms from route)
    final slideAnimation = CurvedAnimation(
      parent: animation,
      curve: XiaMotion.ease,
    );

    // Fade: completes in 70% of total duration via Interval (280ms of 400ms)
    final fadeAnimation = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.7, curve: XiaMotion.ease),
      reverseCurve: const Interval(0.3, 1.0, curve: XiaMotion.easeOut),
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(slideAnimation),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(fadeAnimation),
        child: child,
      ),
    );
  }
}
