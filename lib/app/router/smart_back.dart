import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';

/// Smart back navigation (US-011).
///
/// Pops from the current branch navigator if possible. Falls back to switching
/// to the source tab using `StatefulShellRoute` branch index.
///
/// Shared by ChatRoomPage, SearchPage, and AgentProfilePage — extracted to
/// avoid copy-pasting the same logic across pages.
void smartBack(BuildContext context, {String? source}) {
  if (context.canPop()) {
    context.pop();
  } else {
    if (source == 'messages') {
      context.go(AppRoutes.messages);
    } else {
      // Default and 'claws' both go to claws tab
      context.go(AppRoutes.claws);
    }
  }
}
