import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';

void main() {
  group('ColorOption', () {
    test('stores hex and label', () {
      const option = ColorOption(hex: '#6c5ce7', label: '紫罗兰');
      expect(option.hex, '#6c5ce7');
      expect(option.label, '紫罗兰');
    });

    test('equality', () {
      const a = ColorOption(hex: '#6c5ce7', label: '紫罗兰');
      const b = ColorOption(hex: '#6c5ce7', label: '紫罗兰');
      expect(a, b);
    });
  });

  group('ColorGrid', () {
    const colors = [
      ColorOption(hex: '#6c5ce7', label: '紫罗兰'),
      ColorOption(hex: '#0984e3', label: '海洋蓝'),
      ColorOption(hex: '#00b894', label: '薄荷绿'),
    ];

    Widget buildGrid({
      required String selectedColor,
      ValueChanged<String>? onColorSelected,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ColorGrid(
            colors: colors,
            selectedColor: selectedColor,
            onColorSelected: onColorSelected ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('renders all color dots', (tester) async {
      await tester.pumpWidget(buildGrid(selectedColor: '#6c5ce7'));
      expect(find.byType(GestureDetector), findsNWidgets(3));
    });

    testWidgets('calls onColorSelected when tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(buildGrid(
        selectedColor: '#6c5ce7',
        onColorSelected: (color) => selected = color,
      ));
      await tester.tap(find.byType(GestureDetector).at(1));
      expect(selected, '#0984e3');
    });
  });
}
