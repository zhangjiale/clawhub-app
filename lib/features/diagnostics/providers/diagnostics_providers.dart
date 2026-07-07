import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/i_api_logger.dart';

/// 诊断页条目流（v1 无过滤，spec §7.2）。seed = 当前 snapshot 逆序（最新在最上），
/// 之后每次 store 新增条目重新发逆序列表。O(500) per emission；autoDispose 使页面
/// 关闭后释放订阅，避免终身 O(500) 快照拷贝（store 单例常驻，重开页面 re-seed）。
final diagnosticsEntriesProvider =
    StreamProvider.autoDispose<List<ApiLogEntry>>((ref) {
      final store = ref.watch(apiLogStoreProvider);
      final controller = StreamController<List<ApiLogEntry>>();
      controller.add(store.snapshot().toList().reversed.toList());
      final sub = store.onEntry.listen(
        (_) => controller.add(store.snapshot().toList().reversed.toList()),
      );
      ref.onDispose(() {
        sub.cancel();
        controller.close();
      });
      return controller.stream;
    });

/// 首次进入诊断页的警告是否已确认（spec §7.1）。SharedPreferences 持久化。
/// 诊断页在确认警告时直接写 SharedPreferences 并 invalidate 本 provider。
final diagnosticsWarningShownProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('diagnostics_warning_shown') ?? false;
});
