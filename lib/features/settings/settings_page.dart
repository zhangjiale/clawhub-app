import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/toast.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// ⚠️ PLACEHOLDER — UI mock for design review only.
///
/// 对齐 component-spec.md Section 9。展示 6 行设置项（每行: emoji + 标签 +
/// 右侧值），点击显示 Toast。底部显示版权信息。
///
/// **当前状态**：所有设置项均为硬编码 mock 数据，无 ViewModel / Repository /
/// 持久化。仅用于验证 UI 布局和设计 Token 一致性。
///
/// **TODO(US-030)**: V1.2 接入真实设置 Repository（通知开关、免打扰时段、
/// 生物识别、存储管理），替换 `_SettingRow` 为 ViewModel 驱动的 Widget。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                _SettingRow(
                  emoji: '🔔',
                  label: '通知设置',
                  value: '已开启',
                  onTap: () => XiaToast.show(context, '通知已开启'),
                ),
                _SettingRow(
                  emoji: '🌙',
                  label: '免打扰时段',
                  value: '22:00 — 08:00',
                  onTap: () => XiaToast.show(context, '免打扰时段：22:00 — 08:00'),
                ),
                _SettingRow(
                  emoji: '🔐',
                  label: '生物识别解锁',
                  value: 'Face ID',
                  onTap: () => XiaToast.show(context, '已开启 Face ID 解锁'),
                ),
                _SettingRow(
                  emoji: '🌐',
                  label: '网络设置',
                  value: 'WiFi',
                  onTap: () => XiaToast.show(context, '当前使用 WiFi 连接'),
                ),
                _SettingRow(
                  emoji: '💾',
                  label: '存储管理',
                  value: '12.3 MB',
                  onTap: () => XiaToast.show(context, '已使用 12.3 MB / 500 MB'),
                ),
                _SettingRow(
                  emoji: 'ℹ️',
                  label: '关于虾Hub',
                  value: 'v1.0',
                  onTap: () =>
                      XiaToast.show(context, '虾Hub v1.0 Premium Edition'),
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
                '$emoji $label',
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
