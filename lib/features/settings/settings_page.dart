import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/config/app_config.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/ui_kit/settings_section.dart';

/// 设置页 (US-030) — V2 §9.
///
/// 4 sections (通知 / 隐私与安全 / 存储 / 关于), each in a SettingsSection
/// container with uppercase title and divider-separated rows.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(settingsViewModelProvider);
    // Watch the same provider storage_management_page uses so the row value
    // stays in sync when the user clears cache and returns. The 30s TTL in
    // DriftSettingsRepo means a quick back-and-forth may still show the
    // stale value — acceptable for a settings summary.
    final storageInfo = ref.watch(storageInfoProvider);
    final cacheSizeLabel = storageInfo.when(
      data: (info) => info.sizeLabel,
      loading: () => '…',
      error: (_, _) => '—',
    );

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        toolbarHeight: 52,
        title: const Text(
          '设置',
          style: TextStyle(
            fontSize: XiaTypography.sectionTitle, // V2: 18
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          left: XiaSpacing.s5, // V2: 16
          right: XiaSpacing.s5,
          top: 8,
          bottom: 24,
        ),
        children: [
          // ── Section 1: 通知 ───────────────────────────
          SettingsSection(
            title: '通知',
            children: [
              SettingsRow(
                label: '通知设置',
                value: prefs.notificationsEnabled ? '已开启' : '已关闭',
                onTap: () => context.push(AppRoutes.settingsNotification),
              ),
              SettingsRow(
                label: '免打扰时段',
                value: prefs.dndEnabled
                    ? '${formatHHmm(prefs.dndStartHour, prefs.dndStartMinute)}'
                          ' — '
                          '${formatHHmm(prefs.dndEndHour, prefs.dndEndMinute)}'
                    : '未开启',
                onTap: () => context.push(AppRoutes.settingsDnd),
              ),
            ],
          ),
          // ── Section 2: 隐私与安全 ─────────────────────
          SettingsSection(
            title: '隐私与安全',
            children: [
              SettingsRow(
                label: '生物识别锁',
                value: prefs.biometricEnabled ? '已开启' : '未开启',
                onTap: () => context.push(AppRoutes.settingsBiometric),
              ),
              SettingsRow(label: '数据统计', value: '仅本地', onTap: () {}),
            ],
          ),
          // ── Section 3: 存储 ───────────────────────────
          SettingsSection(
            title: '存储',
            children: [
              SettingsRow(
                label: '本地缓存',
                value: cacheSizeLabel,
                onTap: () => context.push(AppRoutes.settingsStorage),
              ),
              SettingsRow(
                label: '清除全部缓存',
                onTap: () => context.push(AppRoutes.settingsStorage),
                labelStyle: const TextStyle(fontSize: 14, color: XiaColors.red),
              ),
            ],
          ),
          // ── Section 4: 关于 ───────────────────────────
          SettingsSection(
            title: '关于',
            children: [
              SettingsRow(
                label: '版本',
                value: 'v${AppClientInfo.version}',
                onTap: null,
              ),
              SettingsRow(
                label: '诊断',
                value: 'API 日志',
                onTap: () => context.push(AppRoutes.settingsDiagnostics),
              ),
              SettingsRow(label: '源代码', onTap: () {}),
              SettingsRow(label: '检查更新', onTap: () {}),
            ],
          ),
          // Footer
          const SizedBox(height: XiaSpacing.s7),
          const _SettingsFooter(),
        ],
      ),
    );
  }
}

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
