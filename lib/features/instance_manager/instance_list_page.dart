import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/instance_manager/providers/instance_providers.dart';
import 'package:claw_hub/features/instance_manager/widgets/instance_card.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';

/// 实例列表页 (P0 MVP)
class InstanceListPage extends ConsumerWidget {
  const InstanceListPage({super.key});

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
        onPressed: () => context.push('/instances/add'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
