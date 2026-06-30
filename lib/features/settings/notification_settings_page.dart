import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 通知设置子页面 (US-030)
///
/// 允许用户逐项开关通知类型：
/// - 通知总开关
/// - Agent 回复通知
/// - Agent 出错通知
/// - 实例连接状态变化通知
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(
      settingsViewModelProvider.select(
        (s) => (
          notificationsEnabled: s.notificationsEnabled,
          notifyOnReply: s.notifyOnReply,
          notifyOnError: s.notifyOnError,
          notifyOnConnectionChange: s.notifyOnConnectionChange,
          backgroundSyncEnabled: s.backgroundSyncEnabled,
        ),
      ),
    );
    final vm = ref.read(settingsViewModelProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '通知设置',
          style: TextStyle(
            fontSize: XiaTypography.sectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH,
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
                SettingsToggleRow(
                  emoji: '🔔',
                  label: '通知总开关',
                  subtitle: '关闭后所有通知静默',
                  value: prefs.notificationsEnabled,
                  onChanged: vm.setNotificationsEnabled,
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  emoji: '💬',
                  label: 'Agent 回复通知',
                  subtitle: 'Agent 完成任务后推送通知',
                  value: prefs.notifyOnReply,
                  onChanged: vm.setNotifyOnReply,
                  enabled: prefs.notificationsEnabled,
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  emoji: '⚠️',
                  label: 'Agent 出错通知',
                  subtitle: 'Agent 执行出错时推送通知',
                  value: prefs.notifyOnError,
                  onChanged: vm.setNotifyOnError,
                  enabled: prefs.notificationsEnabled,
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  emoji: '🔗',
                  label: '连接状态通知',
                  subtitle: '实例上线/离线时推送通知',
                  value: prefs.notifyOnConnectionChange,
                  onChanged: vm.setNotifyOnConnectionChange,
                  enabled: prefs.notificationsEnabled,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: XiaSpacing.s5),
          Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.lg),
            ),
            child: SettingsToggleRow(
              emoji: '\u{1F504}',
              label: '后台同步',
              subtitle: 'App 闲置时定时拉取新消息（约 15 分钟，由系统调度）',
              value: prefs.backgroundSyncEnabled,
              onChanged: vm.setBackgroundSyncEnabled,
              isLast: true,
            ),
          ),
          const SizedBox(height: XiaSpacing.s5),
          const Text(
            '通知通过设备本地推送实现。关闭通知总开关后，以下子项自动静默。',
            style: TextStyle(fontSize: 13, color: XiaColors.text4, height: 1.5),
          ),
        ],
      ),
    );
  }
}
