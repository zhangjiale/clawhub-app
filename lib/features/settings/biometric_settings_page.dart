import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 生物识别解锁设置子页面 (US-030)
///
/// 允许用户开启/关闭 Face ID 或指纹解锁。
class BiometricSettingsPage extends ConsumerWidget {
  const BiometricSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biometricEnabled = ref.watch(
      settingsViewModelProvider.select((s) => s.biometricEnabled),
    );
    final vm = ref.read(settingsViewModelProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '生物识别解锁',
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
            child: SettingsToggleRow(
              emoji: '🔐',
              label: 'Face ID / 指纹解锁',
              subtitle: '打开 App 时要求身份验证',
              value: biometricEnabled,
              onChanged: vm.setBiometricEnabled,
            ),
          ),
          const SizedBox(height: XiaSpacing.s5),
          const Text(
            '开启后，每次打开虾Hub 需要验证你的身份。'
            '此功能需要设备已录入面容或指纹。',
            style: TextStyle(fontSize: 13, color: XiaColors.text4, height: 1.5),
          ),
        ],
      ),
    );
  }
}
