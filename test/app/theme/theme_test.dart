import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/theme.dart';

void main() {
  group('ClawHub Theme', () {
    test('light theme is generated from seed color', () {
      final theme = AppTheme.lightTheme;
      // Material 3 fromSeed generates tonal palette — primary is derived from seed
      expect(theme.colorScheme.primary, isNotNull);
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme has correct brightness', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
    });

    test('AppColors defines all required colors', () {
      expect(AppColors.primaryBlue, const Color(0xFF007AFF));
      expect(AppColors.agentColors, isNotEmpty);
      expect(AppColors.agentColors.length, greaterThanOrEqualTo(7));
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
      expect(const Color(0xFF007AFF).toHex(), '#007AFF');
      expect(const Color(0xFFE17055).toHex(), '#E17055');
      expect(const Color(0xFFFFFFFF).toHex(), '#FFFFFF');
    });

    test('ColorExtension contrastingTextColor returns black or white', () {
      // White background → dark text
      expect(const Color(0xFFFFFFFF).contrastingTextColor(), Colors.black);
      // Black background → light text
      expect(const Color(0xFF000000).contrastingTextColor(), Colors.white);
      // Blue → light text (dark background)
      expect(const Color(0xFF007AFF).contrastingTextColor(), Colors.white);
      // Yellow → dark text (light background)
      expect(const Color(0xFFFFEB3B).contrastingTextColor(), Colors.black);
    });
  });
}
