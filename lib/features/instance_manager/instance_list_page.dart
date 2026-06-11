import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/features/instance_manager/providers/instance_providers.dart';
import 'package:claw_hub/features/instance_manager/widgets/instance_card.dart';
import 'package:claw_hub/features/instance_manager/qr_scanner_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';

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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final useCase = ref.read(deleteInstanceUseCaseProvider);
      await useCase.execute(instance.id);
      ref.invalidate(instanceListProvider);
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  /// 显示添加方式选择底部弹窗 (US-001)
  Future<void> _showAddOptions(BuildContext context) async {
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
      context.push('/instances/add');
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
      body: instancesAsync.when(
        data: (instances) {
          if (instances.isEmpty) {
            return Column(
              children: [
                const Expanded(
                  child: EmptyState(
                    icon: Icons.dns_outlined,
                    title: 'No Instances',
                    subtitle: 'Add your first OpenClaw instance',
                  ),
                ),
                _AddInstanceCard(
                  onTap: () => _showAddOptions(context),
                ),
                const SizedBox(height: 16),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: instances.length + 1, // +1 for inline add card
            itemBuilder: (context, index) {
              if (index == instances.length) {
                return _AddInstanceCard(
                  onTap: () => _showAddOptions(context),
                );
              }
              final instance = instances[index];
              return InstanceCard(
                instance: instance,
                onTap: () {
                  context.push(AppRoutes.editInstanceWithParams(instance.id));
                },
                onDelete: () => _onDelete(context, ref, instance),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

/// 内联"添加实例"虚线卡片 — 对齐原型设计
class _AddInstanceCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddInstanceCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outline.withAlpha(60),
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            // Dashed effect via dotted border pattern
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '添加新实例',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
