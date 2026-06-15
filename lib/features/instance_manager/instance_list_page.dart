import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/features/instance_manager/providers/instance_providers.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/instance_manager/widgets/instance_card.dart';
import 'package:claw_hub/features/instance_manager/qr_scanner_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 实例列表页 (P0 MVP)
class InstanceListPage extends ConsumerWidget {
  const InstanceListPage({super.key});

  /// 确认并删除指定实例。
  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    Instance instance,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Instance'),
        content: Text(
          'Delete "${instance.name}"?\n'
          'All local messages and agents will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: XiaColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final useCase = ref.read(deleteInstanceUseCaseProvider);
      await useCase.execute(instance.id);
      _invalidateData(ref);
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  /// 显示添加方式选择底部弹窗 (US-001)
  Future<void> _showAddOptions(BuildContext context, WidgetRef ref) async {
    final option = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan QR Code'),
                subtitle: const Text('Scan OpenClaw Gateway configuration QR'),
                onTap: () => Navigator.of(ctx).pop('scan'),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Enter Manually'),
                subtitle: const Text('Type Gateway URL and Token'),
                onTap: () => Navigator.of(ctx).pop('manual'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted) return;

    if (option == 'scan') {
      await _startQrScan(context);
    } else if (option == 'manual') {
      await context.push('/instances/add');
      _invalidateData(ref);
    }
  }

  /// 打开扫码页面并等待结果 (US-001)
  Future<void> _startQrScan(BuildContext context) async {
    if (!context.mounted) return;

    final result = await Navigator.of(context).push<QrScanResult>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

    if (result == null || !context.mounted) return;

    // Navigate to add page with pre-filled data
    context.push('/instances/add', extra: result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instancesAsync = ref.watch(instanceListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('实例管理')),
      body: RefreshIndicator(
        onRefresh: () async {
          _invalidateData(ref);
          // 同时等待两个 provider，确保 spinner 在实例列表和
          // agent 数据都就绪后才收起，避免用户看到过期数据。
          await ref.read(instanceListProvider.future);
          await ref.read(agentListProvider.future);
        },
        child: instancesAsync.when(
          data: (instances) {
            if (instances.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: const EmptyState(
                      icon: Icon(Icons.dns_outlined),
                      title: '还没有实例',
                      subtitle: '添加你的第一个 OpenClaw 实例',
                    ),
                  ),
                  _AddInstanceCard(onTap: () => _showAddOptions(context, ref)),
                  const SizedBox(height: XiaSpacing.s4),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: instances.length + 1, // +1 for inline add card
              itemBuilder: (context, index) {
                if (index == instances.length) {
                  return _AddInstanceCard(
                    onTap: () => _showAddOptions(context, ref),
                  );
                }
                final instance = instances[index];
                return InstanceCard(
                  instance: instance,
                  onTap: () async {
                    await context.push(
                      AppRoutes.editInstanceWithParams(instance.id),
                    );
                    _invalidateData(ref);
                  },
                  onDelete: () => _onDelete(context, ref, instance),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ),
    );
  }

  /// 统一刷新实例列表和 Agent 列表。
  ///
  /// 集中管理两个 provider 的 invalidate 调用，避免在多个回调中重复
  /// 相同代码。未来如需增加第三个 provider，只需修改此方法。
  void _invalidateData(WidgetRef ref) {
    ref.invalidate(instanceListProvider);
    ref.invalidate(agentListProvider);
  }
}

/// 内联"添加实例"虚线卡片 — 对齐原型设计
/// Press: border color→accent, 200ms ease.
class _AddInstanceCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddInstanceCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PressFeedback(
      onTap: onTap,
      builder: (child, isPressed) => AnimatedContainer(
        duration: XiaMotion.durationFast,
        curve: XiaMotion.ease,
        margin: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s6,
          vertical: XiaSpacing.s3,
        ),
        padding: const EdgeInsets.all(XiaSpacing.s5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(XiaRadius.lg),
          border: Border.all(
            color: isPressed ? XiaColors.accent : XiaColors.surface3,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: child,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add, size: 20, color: XiaColors.accent),
          const SizedBox(width: XiaSpacing.s2),
          Text(
            '添加新实例',
            style: theme.textTheme.titleSmall?.copyWith(
              color: XiaColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
