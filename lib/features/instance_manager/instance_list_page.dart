import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/instance_manager/providers/instance_providers.dart';
import 'package:claw_hub/features/instance_manager/widgets/instance_card.dart';
import 'package:claw_hub/features/instance_manager/qr_scanner_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';

/// 实例列表页 (P0 MVP)
class InstanceListPage extends ConsumerWidget {
  const InstanceListPage({super.key});

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
      appBar: AppBar(title: const Text('Instances')),
      body: instancesAsync.when(
        data: (instances) {
          if (instances.isEmpty) {
            return const EmptyState(
              icon: Icons.dns_outlined,
              title: 'No Instances',
              subtitle: 'Add your first OpenClaw instance',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: instances.length,
            itemBuilder: (context, index) {
              final instance = instances[index];
              return InstanceCard(
                instance: instance,
                onTap: () {
                  context.push(AppRoutes.editInstanceWithParams(instance.id));
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
