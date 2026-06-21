import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// SettingsToggle — V2 §9.4 custom 40×22 toggle.
///
/// Off: bg surface3, knob at left (translateX(0)).
/// On: bg accent, knob translateX(18).
/// 150ms ease. Disabled: opacity 0.4.
class SettingsToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingsToggle({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: XiaMotion.durationFast,
          curve: XiaMotion.ease,
          width: 40,
          height: 22,
          decoration: BoxDecoration(
            color: value ? XiaColors.accent : XiaColors.surface3,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: XiaMotion.durationFast,
                curve: XiaMotion.ease,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
