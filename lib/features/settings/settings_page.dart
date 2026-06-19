import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/config/app_config.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 设置页 (US-030)
///
/// Aligned with component-spec.md Section 9. 展示 6 行设置项，每行显示当前值。
/// 所有数据由 [settingsViewModelProvider] 驱动，通过 [ISettingsRepo] 持久化。
///
/// 通知、免打扰、存储管理、关于 → 导航到子页面。
/// 生物识别 → 内联开关。
/// 网络状态 → 实时展示当前连接类型。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(settingsViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '设置',
          style: TextStyle(
            fontSize: XiaTypography.sectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          left: XiaSpacing.s6,
          right: XiaSpacing.s6,
          top: XiaSpacing.s2,
          bottom: XiaSpacing.s8,
        ),
        children: [
          // Settings container
          Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.lg),
            ),
            child: Column(
              children: [
                // ── 1. 通知设置 ────────────────────────────────────
                _SettingRow(
                  emoji: '🔔',
                  label: '通知设置',
                  value: prefs.notificationsEnabled ? '已开启' : '已关闭',
                  onTap: () => context.push(AppRoutes.settingsNotification),
                ),
                // ── 2. 免打扰时段 ──────────────────────────────────
                _SettingRow(
                  emoji: '🌙',
                  label: '免打扰时段',
                  value: prefs.dndEnabled
                      ? '${formatHHmm(prefs.dndStartHour, prefs.dndStartMinute)}'
                            ' — '
                            '${formatHHmm(prefs.dndEndHour, prefs.dndEndMinute)}'
                      : '未开启',
                  onTap: () => context.push(AppRoutes.settingsDnd),
                ),
                // ── 3. 生物识别解锁 ────────────────────────────────
                _SettingRow(
                  emoji: '🔐',
                  label: '生物识别解锁',
                  value: prefs.biometricEnabled ? '已开启' : '未开启',
                  onTap: () => context.push(AppRoutes.settingsBiometric),
                ),
                // ── 4. 网络设置 ────────────────────────────────────
                _SettingRow(
                  emoji: '🌐',
                  label: '网络设置',
                  value: connectivityLabel(),
                  onTap: () => context.push(AppRoutes.settingsNetwork),
                ),
                // ── 5. 存储管理 ────────────────────────────────────
                _SettingRow(
                  emoji: '💾',
                  label: '存储管理',
                  value: '查看详情',
                  onTap: () => context.push(AppRoutes.settingsStorage),
                ),
                // ── 6. 关于虾Hub ───────────────────────────────────
                _SettingRow(
                  emoji: 'ℹ️',
                  label: '关于虾Hub',
                  value: 'v${AppClientInfo.version}',
                  onTap: () => context.push(AppRoutes.settingsAbout),
                  isLast: true,
                ),
              ],
            ),
          ),
          // Footer
          const SizedBox(height: XiaSpacing.s7),
          const _SettingsFooter(),
        ],
      ),
    );
  }
}

/// 单行设置项 — 左侧 emoji + 标签，右侧当前值。
/// Press: bg→surface2, 200ms ease.
class _SettingRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool isLast;

  const _SettingRow({
    required this.emoji,
    required this.label,
    required this.value,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      pressedColor: XiaColors.surface2,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s5,
          vertical: XiaSpacing.s5,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: XiaColors.divider)),
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
                value,
                style: const TextStyle(
                  fontSize: XiaTypography.body,
                  color: XiaColors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置页底部版权信息。
class _SettingsFooter extends StatelessWidget {
  const _SettingsFooter();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '虾Hub — 你的 AI 虾群移动管理中心\nPowered by OpenClaw Gateway Protocol',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        color: XiaColors.text4,
        height: 1.8,
        letterSpacing: 0.2,
      ),
    );
  }
}
