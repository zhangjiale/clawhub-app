import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/i_api_logger.dart';

/// 诊断页条目流（v1 无过滤，spec §7.2）。seed = 当前 snapshot 逆序（最新在最上），
/// 之后对 store 新增条目做 100ms throttle 批量发射，避免 chatty connection 下每帧
/// 都重建 ListView（review finding #7）。autoDispose 使页面关闭后释放订阅。
final diagnosticsEntriesProvider =
    StreamProvider.autoDispose<List<ApiLogEntry>>((ref) {
      final store = ref.watch(apiLogStoreProvider);
      final controller = StreamController<List<ApiLogEntry>>();
      Timer? throttle;
      var dirty = false;

      void flush() {
        throttle = null;
        if (!dirty) return;
        dirty = false;
        controller.add(store.snapshot().reversed.toList());
      }

      void markDirty() {
        dirty = true;
        throttle ??= Timer(const Duration(milliseconds: 100), flush);
      }

      controller.add(store.snapshot().reversed.toList());
      final sub = store.onEntry.listen((_) => markDirty());

      ref.onDispose(() {
        sub.cancel();
        throttle?.cancel();
        controller.close();
      });
      return controller.stream;
    });

/// SharedPreferences key for the "diagnostics warning acknowledged" flag.
/// Centralized here so the page never references the raw string (ARB #3).
const String _kDiagnosticsWarningShown = 'diagnostics_warning_shown';

/// 首次进入诊断页的警告是否已确认（spec §7.1）。SharedPreferences 持久化。
///
/// 诊断页通过 [markShown] 确认警告，不再直接写 SharedPreferences（ARB #3：
/// 原实现读走 provider、写绕过 provider，且 key 字符串双份于两个文件）。
class DiagnosticsWarningShownNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDiagnosticsWarningShown) ?? false;
  }

  /// 标记警告已确认：落盘 + 原地更新 state（无需 invalidate）。
  Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDiagnosticsWarningShown, true);
    state = const AsyncData(true);
  }
}

final diagnosticsWarningShownProvider =
    AsyncNotifierProvider<DiagnosticsWarningShownNotifier, bool>(
      DiagnosticsWarningShownNotifier.new,
    );
