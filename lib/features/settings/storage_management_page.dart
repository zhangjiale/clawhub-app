import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/storage_info.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/shared/settings_widgets.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
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
        data: (info) => _buildBody(context, ref, info),
        loading: () => _buildLoading(),
        // 复用 lib/ui_kit/load_error_view.dart,与 AgentProfilePage /
        // AgentConfigPage 的错误展示契约一致(主题色 error、可选重试)。
        error: (error, _) => LoadErrorView(error: error, title: '无法加载存储信息'),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, StorageInfo info) {
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
        const SizedBox(height: XiaSpacing.s5),
        _ClearCacheButton(onConfirm: () => _onClearCache(context, ref)),
      ],
    );
  }

  Future<void> _onClearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部缓存?'),
        content: const Text(
          '将清除所有消息和对话记录、工具调用、统计与头像。\n'
          '此操作不可撤销,Agent 与实例连接配置会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: XiaColors.red),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref.read(clearCacheActionProvider)();
      if (!context.mounted) return;
      if (result.allSucceeded) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清除全部缓存')));
      } else if (result.partialFailure) {
        // DB 已清，但头像文件清理失败（macOS 沙箱 / 权限拒绝）。
        // 不让用户重做整个流程，但必须让他知道头像文件可能残留在磁盘。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('消息已清除，头像文件清理失败（可能为权限问题）')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('清除失败，请重试')));
      }
    } catch (error, stackTrace) {
      // Law 8 合规: catch 必须至少 debugPrint,SnackBar 仅用于用户反馈,
      // 调试 / 排障依赖此处控制台输出。
      debugPrint('[StorageManagement] clearCache failed: $error\n$stackTrace');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清除失败: $error')));
    }
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
}

/// "清除全部缓存" 红色危险按钮。点击触发二次确认 Dialog。
///
/// **Major #2 修复**：升级为 ConsumerStatefulWidget，本地维护 `_isClearing`
/// 标志，防止用户在 DB 删除（万级行）+ 文件清理期间重复点击触发并发 clearAll。
/// `onPressed: _isClearing ? null : _onPressed` 是 Flutter 标准的"禁用态"——
/// `null` 时按钮自动渲染灰色且不响应 tap。
class _ClearCacheButton extends ConsumerStatefulWidget {
  final Future<void> Function() onConfirm;
  const _ClearCacheButton({required this.onConfirm});

  @override
  ConsumerState<_ClearCacheButton> createState() => _ClearCacheButtonState();
}

class _ClearCacheButtonState extends ConsumerState<_ClearCacheButton> {
  bool _isClearing = false;

  Future<void> _onPressed() async {
    if (_isClearing) return; // 二次防御（虽然按钮已禁用）
    setState(() => _isClearing = true);
    try {
      await widget.onConfirm();
    } finally {
      // mounted 检查: widget 可能已 dispose（用户快速返回上一页面）
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isClearing ? null : _onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: XiaColors.red,
          side: const BorderSide(color: XiaColors.red),
          padding: const EdgeInsets.symmetric(vertical: XiaSpacing.s3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(XiaRadius.md),
          ),
        ),
        icon: const Icon(Icons.delete_outline, size: 18),
        label: Text(
          _isClearing ? '正在清除...' : '清除全部缓存',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
