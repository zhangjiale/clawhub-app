import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 网络设置信息页 (US-030)
///
/// 展示当前网络连接状态（实时，来自 [connectivityStateProvider]）和基本信息。
/// 后续可扩展代理设置等高级网络配置。
class NetworkSettingsPage extends ConsumerWidget {
  const NetworkSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch real-time connectivity state from connectivity_plus
    final connectivityAsync = ref.watch(connectivityStateProvider);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '网络设置',
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
                // Real-time network state via connectivity_plus
                SettingsInfoRow(
                  emoji: '📶',
                  label: '实时状态',
                  value: connectivityAsync.when(
                    data: (results) => connectivityResultLabel(results),
                    loading: () => '检测中…',
                    error: (_, _) => '未知',
                  ),
                ),
                const SettingsDivider(),
                // Static platform hint
                SettingsInfoRow(
                  emoji: '📡',
                  label: '当前网络',
                  value: connectivityLabel(),
                ),
                const SettingsDivider(),
                SettingsInfoRow(
                  emoji: '📱',
                  label: '运行平台',
                  value: _platformLabel(),
                ),
                const SettingsDivider(),
                SettingsInfoRow(
                  emoji: '🔌',
                  label: '连接协议',
                  value: 'WebSocket (OpenClaw v4)',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: XiaSpacing.s5),
          const Text(
            '虾Hub 通过 WebSocket 连接 OpenClaw Gateway 实例。'
            '内网实例需设备与 Gateway 在同一局域网。',
            style: TextStyle(fontSize: 13, color: XiaColors.text4, height: 1.5),
          ),
        ],
      ),
    );
  }

  String _platformLabel() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
    }
  }
}
