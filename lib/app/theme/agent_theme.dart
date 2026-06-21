import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Per-agent theme extension that propagates the agent's primary color
/// down the widget tree via [Theme.of(context).extension<AgentTheme>()].
///
/// Usage:
/// ```dart
/// Theme(
///   data: Theme.of(context).copyWith(extensions: [
///     AgentTheme(primary: ColorExtension.fromHex(agent.themeColor)),
///   ]),
///   child: ...,
/// )
/// ```
///
/// Descendants obtain the color without prop-drilling:
/// ```dart
/// final agentTheme = Theme.of(context).extension<AgentTheme>();
/// final color = agentTheme?.primary ?? XiaColors.accent;
/// ```
@immutable
class AgentTheme extends ThemeExtension<AgentTheme> {
  /// The agent's brand color (parsed from hex like '#6C8AAF').
  final Color primary;

  /// Primary color at ~10% opacity — used for AppBar tint, pill pressed bg, etc.
  Color get primaryMuted => primary.withAlpha(26);

  const AgentTheme({required this.primary});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentTheme && primary.value == other.primary.value;

  @override
  int get hashCode => primary.value;

  @override
  AgentTheme copyWith({Color? primary}) {
    return AgentTheme(primary: primary ?? this.primary);
  }

  @override
  AgentTheme lerp(covariant AgentTheme? other, double t) {
    if (other == null) return this;
    return AgentTheme(
      primary: Color.lerp(primary, other.primary, t) ?? primary,
    );
  }

  /// Convenience: look up [AgentTheme] from the closest [Theme] ancestor,
  /// falling back to [XiaColors.accent] primary when no AgentTheme is in scope.
  static AgentTheme of(BuildContext context) {
    return Theme.of(context).extension<AgentTheme>() ??
        const AgentTheme(primary: XiaColors.accent);
  }
}
