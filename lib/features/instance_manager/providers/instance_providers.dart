import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/app/di/providers.dart';

/// 实例列表 Provider
/// 使用 ref.watch 建立依赖监听，支持后续迁移到 drift-backed StreamProvider 时自动响应数据变化
final instanceListProvider = FutureProvider<List<Instance>>((ref) async {
  return ref.watch(instanceRepoProvider).getAll();
});
