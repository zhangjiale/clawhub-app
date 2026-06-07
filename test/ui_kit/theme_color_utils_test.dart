import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/theme_color_utils.dart';

void main() {
  group('ThemeColorUtils', () {
    group('parseHexColor', () {
      test('parses 6-digit hex', () {
        expect(parseHexColor('#007AFF'), const Color(0xFF007AFF));
        expect(parseHexColor('#FF5733'), const Color(0xFFFF5733));
      });

      test('parses 3-digit hex', () {
        final result = parseHexColor('#F00');
        expect(result, const Color(0xFFFF0000));
      });

      test('parses without hash', () {
        expect(parseHexColor('007AFF'), const Color(0xFF007AFF));
      });

      test('throws on invalid hex', () {
        expect(() => parseHexColor(''), throwsArgumentError);
        expect(() => parseHexColor('not a color'), throwsArgumentError);
        expect(() => parseHexColor('#GGGGGG'), throwsArgumentError);
      });
    });

    group('wcagContrastRatio', () {
      test('black on white = 21:1', () {
        final ratio = wcagContrastRatio(Colors.black, Colors.white);
        expect(ratio, greaterThan(20.0));
        expect(ratio, lessThan(22.0));
      });

      test('same colors = 1:1', () {
        final ratio = wcagContrastRatio(Colors.blue, Colors.blue);
        expect(ratio, closeTo(1.0, 0.01));
      });

      test('white on black = 21:1', () {
        final ratio = wcagContrastRatio(Colors.white, Colors.black);
        expect(ratio, greaterThan(20.0));
      });
    });

    group('wcagAA compliance', () {
      test('black on white meets AA', () {
        expect(meetsWCAGAA(Colors.black, Colors.white), isTrue);
      });

      test('grey on white may not meet AA', () {
        expect(meetsWCAGAA(const Color(0xFFCCCCCC), Colors.white), isFalse);
      });

      test('navy on white meets AA', () {
        expect(meetsWCAGAA(const Color(0xFF000080), Colors.white), isTrue);
      });
    });
  });
}
