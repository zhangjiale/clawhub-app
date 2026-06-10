import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 颜色选项
class ColorOption {
  final String hex;
  final String label;

  const ColorOption({required this.hex, required this.label});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorOption && hex == other.hex && label == other.label;

  @override
  int get hashCode => Object.hash(hex, label);
}

/// 12 色圆形主题色选择器
///
/// 以网格展示颜色圆形，选中项显示白色边框 + 外环高亮。
/// 参数化为 [colors] + [selectedColor] + [onColorSelected] 回调。
class ColorGrid extends StatelessWidget {
  final List<ColorOption> colors;
  final String selectedColor;
  final ValueChanged<String> onColorSelected;

  const ColorGrid({
    super.key,
    required this.colors,
    required this.selectedColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: colors.map((option) {
        final color = ColorExtension.fromHex(option.hex);
        final isSelected =
            option.hex.toUpperCase() == selectedColor.toUpperCase();

        return GestureDetector(
          onTap: () => onColorSelected(option.hex),
          behavior: HitTestBehavior.opaque,
          child: Tooltip(
            message: option.label,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withAlpha(150),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
