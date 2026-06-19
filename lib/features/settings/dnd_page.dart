import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 免打扰时段设置子页面 (US-030)
///
/// 允许用户开启/关闭免打扰并设置开始/结束时间。
class DoNotDisturbPage extends ConsumerWidget {
  const DoNotDisturbPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(
      settingsViewModelProvider.select(
        (s) => (
          dndEnabled: s.dndEnabled,
          dndStartHour: s.dndStartHour,
          dndStartMinute: s.dndStartMinute,
          dndEndHour: s.dndEndHour,
          dndEndMinute: s.dndEndMinute,
        ),
      ),
    );
    final vm = ref.read(settingsViewModelProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '免打扰时段',
          style: TextStyle(
            fontSize: XiaTypography.sectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s6,
          vertical: XiaSpacing.s2,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.lg),
            ),
            child: Column(
              children: [
                // DND toggle
                SettingsToggleRow(
                  emoji: '🌙',
                  label: '开启免打扰',
                  subtitle: '开启后在设定时段内不推送通知',
                  value: prefs.dndEnabled,
                  onChanged: vm.setDndEnabled,
                ),

                if (prefs.dndEnabled) ...[
                  const SettingsDivider(),

                  // Start time picker
                  _TimeTile(
                    emoji: '🌅',
                    label: '开始时间',
                    hour: prefs.dndStartHour,
                    minute: prefs.dndStartMinute,
                    onTimePicked: (h, m) {
                      vm.setDndTimeRange(
                        startHour: h,
                        startMinute: m,
                        endHour: prefs.dndEndHour,
                        endMinute: prefs.dndEndMinute,
                      );
                    },
                  ),

                  const SettingsDivider(),

                  // End time picker
                  _TimeTile(
                    emoji: '🌇',
                    label: '结束时间',
                    hour: prefs.dndEndHour,
                    minute: prefs.dndEndMinute,
                    onTimePicked: (h, m) {
                      vm.setDndTimeRange(
                        startHour: prefs.dndStartHour,
                        startMinute: prefs.dndStartMinute,
                        endHour: h,
                        endMinute: m,
                      );
                    },
                    isLast: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: XiaSpacing.s5),
          const Text(
            '免打扰时段内收到的通知将静默存储，时段结束后批量推送。',
            style: TextStyle(fontSize: 13, color: XiaColors.text4, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String emoji;
  final String label;
  final int hour;
  final int minute;
  final void Function(int hour, int minute) onTimePicked;
  final bool isLast;

  const _TimeTile({
    required this.emoji,
    required this.label,
    required this.hour,
    required this.minute,
    required this.onTimePicked,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final display = formatHHmm(hour, minute);

    return PressFeedback(
      pressedColor: XiaColors.surface2,
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: minute),
        );
        if (time != null) {
          onTimePicked(time.hour, time.minute);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s5,
          vertical: XiaSpacing.s4,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$emoji  $label',
              style: const TextStyle(
                fontSize: XiaTypography.body,
                color: XiaColors.text1,
              ),
            ),
            Text(
              display,
              style: const TextStyle(
                fontSize: XiaTypography.body,
                color: XiaColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
