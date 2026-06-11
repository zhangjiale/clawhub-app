import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Color option for [ColorGrid].
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

/// 12-color grid picker (6 columns, 40×40 rounded squares).
/// Matching ComponentSpec Section 6.5.
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: XiaSpacing.s3,
        crossAxisSpacing: XiaSpacing.s3,
        childAspectRatio: 1,
      ),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final option = colors[index];
        final color = ColorExtension.fromHex(option.hex);
        final isSelected =
            option.hex.toUpperCase() == selectedColor.toUpperCase();

        return GestureDetector(
          onTap: () => onColorSelected(option.hex),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(XiaRadius.sm),
              border: isSelected
                  ? Border.all(color: XiaColors.text1, width: 3)
                  : Border.all(color: Colors.transparent, width: 3),
              boxShadow: isSelected ? XiaShadow.selectedGlow : null,
            ),
            child: isSelected
                ? const Center(
                    child: Text(
                      '✓',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}
