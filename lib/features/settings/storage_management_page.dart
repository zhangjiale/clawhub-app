import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/storage_info.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 存储管理子页面 (US-030)
///
/// 展示数据库和缓存占用，提供清除消息缓存功能。
/// Storage info is fetched via [storageInfoProvider] — no direct
/// repository access in the UI layer (Law 2).
class StorageManagementPage extends ConsumerWidget {
  const StorageManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageAsync = ref.watch(storageInfoProvider);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '存储管理',
          style: TextStyle(
            fontSize: XiaTypography.sectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: storageAsync.when(
        data: (info) => _buildBody(info),
        loading: () => _buildLoading(),
        error: (error, _) => _buildError(error),
      ),
    );
  }

  Widget _buildBody(StorageInfo info) {
    return ListView(
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
              SettingsInfoRow(
                emoji: '\u{1F5C4}️',
                label: '数据库大小',
                value: info.sizeLabel,
              ),
              const SettingsDivider(),
              SettingsInfoRow(
                emoji: '\u{1F4AC}',
                label: '消息总数',
                value: '${info.messageCount} 条',
              ),
              const SettingsDivider(),
              SettingsInfoRow(
                emoji: '\u{1F5BC}️',
                label: '头像缓存',
                value: '自动清理',
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: XiaSpacing.pagePaddingH),
        const Text(
          '消息记录存储在设备本地，删除后将无法恢复。\n'
          '头像和图片缓存会在存储空间不足时自动清理。',
          style: TextStyle(fontSize: 13, color: XiaColors.text4, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return ListView(
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
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: XiaSpacing.s8),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  Widget _buildError(Object error) {
    return ListView(
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
          child: Padding(
            padding: const EdgeInsets.all(XiaSpacing.pagePaddingH),
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: XiaColors.text4,
                ),
                const SizedBox(height: XiaSpacing.s3),
                const Text(
                  '无法加载存储信息',
                  style: TextStyle(
                    fontSize: XiaTypography.body,
                    color: XiaColors.text1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$error',
                  style: const TextStyle(fontSize: 13, color: XiaColors.text4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
