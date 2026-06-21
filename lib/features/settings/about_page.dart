import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/config/app_config.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 关于虾Hub 页面 (US-030)
///
/// 展示应用版本、技术栈和版权信息。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '关于虾Hub',
          style: TextStyle(
            fontSize: XiaTypography.sectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH,
          vertical: XiaSpacing.pagePaddingH,
        ),
        children: [
          // App icon + name
          const SizedBox(height: XiaSpacing.pagePaddingH),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: XiaColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.pets, size: 44, color: XiaColors.accent),
            ),
          ),
          const SizedBox(height: XiaSpacing.s5),
          Center(
            child: Text(
              '虾Hub',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: XiaColors.text1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'v${AppClientInfo.version}',
              style: const TextStyle(fontSize: 15, color: XiaColors.text3),
            ),
          ),

          const SizedBox(height: XiaSpacing.s7),

          // Info container
          Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.lg),
            ),
            child: Column(
              children: [
                SettingsInfoRow(
                  emoji: '🔌',
                  label: '通信协议',
                  value: 'OpenClaw Gateway v4',
                ),
                const SettingsDivider(),
                SettingsInfoRow(
                  emoji: '📱',
                  label: '平台',
                  value: 'iOS / Android',
                ),
                const SettingsDivider(),
                SettingsInfoRow(
                  emoji: '🛠️',
                  label: '框架',
                  value: 'Flutter + Drift + Riverpod',
                ),
                const SettingsDivider(),
                SettingsInfoRow(
                  emoji: '🧪',
                  label: '测试',
                  value: '360+ tests',
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: XiaSpacing.s7),

          // Footer
          const Text(
            '虾Hub — 你的 AI 虾群移动管理中心\n'
            'Powered by OpenClaw Gateway Protocol\n\n'
            '© 2026 ClawHub Team. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: XiaColors.text4,
              height: 1.8,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
