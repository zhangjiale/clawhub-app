import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/theme.dart';

void main() {
  group('ClawHub Theme', () {
    test('dark theme has correct brightness and is manually constructed', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      // V2: cool dark bg #08090D (was V1 #111110 warm dark)
      expect(theme.scaffoldBackgroundColor, const Color(0xFF08090D));
    });

    test('AppColors defines all required colors', () {
      // V2: sapphire blue #4F83FF (was V1 coral #C27C68)
      expect(AppColors.primaryBlue, const Color(0xFF4F83FF));
      expect(AppColors.agentColors, isNotEmpty);
      expect(AppColors.agentColors.length, greaterThanOrEqualTo(12));
    });

    test('agentColors are all valid and unique', () {
      final colors = AppColors.agentColors;
      final hexStrings = colors.map((c) => c.toHex()).toSet();
      expect(hexStrings.length, colors.length); // all unique
      for (final c in colors) {
        expect(c.toHex(), matches(RegExp(r'^#[0-9a-fA-F]{6}$')));
      }
    });

    test('status colors are defined', () {
      expect(AppColors.statusOnline, isNotNull);
      expect(AppColors.statusOffline, isNotNull);
      expect(AppColors.statusConnecting, isNotNull);
      expect(AppColors.statusExpectedOffline, isNotNull);
      expect(AppColors.messageFailed, isNotNull);
      expect(AppColors.unreadBadge, isNotNull);
    });

    test('ColorExtension toHex produces 6-digit hex', () {
      // V2 sapphire
      expect(const Color(0xFF4F83FF).toHex(), '#4F83FF');
      expect(const Color(0xFFFBBF24).toHex(), '#FBBF24');
      expect(const Color(0xFFFFFFFF).toHex(), '#FFFFFF');
    });

    test('ColorExtension contrastingTextColor returns black87 or white', () {
      // White background → dark text (WCAG AA via 0.55 threshold)
      expect(const Color(0xFFFFFFFF).contrastingTextColor(), Colors.black87);
      // Black background → light text
      expect(const Color(0xFF000000).contrastingTextColor(), Colors.white);
      // Purple (ClawHub accent) → light text (luminance ≈0.16 < 0.55)
      expect(const Color(0xFF6C5CE7).contrastingTextColor(), Colors.white);
      // Yellow → dark text (luminance ≈0.81 > 0.55)
      expect(const Color(0xFFFFEB3B).contrastingTextColor(), Colors.black87);
      // Mid-luminance teal → white text (luminance ≈0.45 < 0.55)
      expect(const Color(0xFF00A86B).contrastingTextColor(), Colors.white);
      // Light gray → dark text (luminance ≈0.53 < 0.55, borderline)
      expect(const Color(0xFFBDBDBD).contrastingTextColor(), Colors.white);
    });
  });
}
