import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/iconnectivity.dart';
import 'package:claw_hub/domain/models/clear_all_result.dart';
import 'package:claw_hub/domain/models/storage_info.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';
import 'package:claw_hub/features/search/providers/search_providers.dart';
import 'package:claw_hub/features/settings/providers/clear_cache_guard.dart';
import 'package:claw_hub/features/settings/viewmodels/settings_view_model.dart';

/// Global settings ViewModel provider (US-030).
///
/// Since settings are app-wide (not per-agent or per-instance), this is a
/// simple [StateNotifierProvider], not a `.family`.
///
/// [SettingsViewModel.init] reads real prefs from SQLite asynchronously.
/// The first frame shows [UserPreferences.defaults] for 1–2 frames until
/// init completes.  Mutations that arrive during the init window are queued
/// and replayed by the ViewModel — no user action is silently dropped.
///
/// The provider's [ref.onDispose] is intentionally omitted:
/// [StateNotifierProvider] already calls [dispose] on the notifier
/// automatically when the provider is disposed.
final settingsViewModelProvider =
    StateNotifierProvider<SettingsViewModel, UserPreferences>((ref) {
      final vm = SettingsViewModel(repo: ref.watch(settingsRepoProvider));
      vm.init().catchError((Object error, StackTrace stackTrace) {
        debugPrint('[SettingsProvider] init() failed: $error\n$stackTrace');
      });
      return vm;
    });

/// Storage info provider (US-030).
///
/// Fetches database size and message count lazily via [ISettingsRepo.getStorageInfo].
/// The [FutureProvider] pattern keeps storage data reactive and handles
/// loading / error states automatically via [AsyncValue].
final storageInfoProvider = FutureProvider<StorageInfo>((ref) {
  return ref.watch(settingsRepoProvider).getStorageInfo();
});

/// "清除全部缓存" 动作 Provider (US-030 收尾 + Major #1 修复)。
///
/// 返回一个 async 函数；[Provider] 常驻应用生命周期，故闭包内 `ref` 安全，
/// UI 层在 onPressed 中调用即可。
///
/// 调用流程:
/// 1. 置 [clearCacheInProgressProvider] = true（互斥 guard，阻止新 VM）
/// 2. `try` 调 [ISettingsRepo.clearAll] 清消息/工具调用/统计/头像（保留
///    agents/conversations 骨架，见 [ISettingsRepo.clearAll] 文档）
/// 3. `try/finally` 保证 invalidate 序列在 clearAll 失败时也安全 —— 即便
///    repo 抛异常，guard 仍会复位为 false，避免永久阻塞页面打开
/// 4. 失效范围（push 模型 + 顶层 FutureProvider 显式 invalidate）:
///    - 顶层 FutureProvider: [storageInfoProvider] / [conversationListProvider] /
///      [statsProvider]（不 watch tick，需显式 invalidate）
///    - ticker: `agentSyncTickerProvider++`（驱动 [agentListProvider]）
///    - push 信号: `cacheClearedTickProvider++` → 所有 watch/listen 该 tick
///      的 family VM 自动响应（agentProfileVM 重建、chatVM 温和刷新）。
///      本 provider **无需 import agent_profile / chat_room** —— 依赖箭头反转。
///    - search VM: [SearchViewModel.clear] 清内部状态（保留实例）
///    - 不再 invalidate [instanceListProvider]：clearAll 明确不删 instances，
///      该 invalidate 是冗余重查。
/// 5. 失败抛回 UI 层显示 SnackBar（仅顶层 finally 中的失败会抛）。
///    部分失败（DB 清了但头像文件清理失败）由返回的 [ClearAllResult]
///    表达 —— UI 层据此提示用户「部分清理完成」。
final clearCacheActionProvider = Provider<Future<ClearAllResult> Function()>((
  ref,
) {
  return () async {
    final repo = ref.read(settingsRepoProvider);
    ref.read(clearCacheInProgressProvider.notifier).state = true;
    try {
      final result = await repo.clearAll();
      // 顶层 FutureProvider（不 watch tick，需显式 invalidate）
      if (result.dbCleared) {
        ref.invalidate(storageInfoProvider);
        ref.invalidate(conversationListProvider);
        ref.invalidate(statsProvider);
        // agentListProvider 走 ticker（已有 ref.watch 依赖）
        ref.read(agentSyncTickerProvider.notifier).state++;
        // Push 信号:递增 tick → agentProfileVM 自动重建、chatVM 温和
        // 刷新（reloadMessages，isStreaming 守卫保护流式）。无需枚举
        // live-set，无需 import agent_profile / chat_room。
        ref.read(cacheClearedTickProvider.notifier).state++;
        // Search VM 内部状态清空（保留 VM 实例，丢弃 query/results）
        ref.read(searchViewModelProvider.notifier).clear();
      }
      return result;
    } finally {
      // 无论成功、DB 失败、还是头像清理部分失败，guard 都必须复位 —— 否则
      // agent_profile / chat_room 页面会永久打不开。
      ref.read(clearCacheInProgressProvider.notifier).state = false;
    }
  };
});

/// per-agent 清空动作 Provider (US-020 AC-3)。
///
/// 清空指定 agent 的全部对话内容与派生缓存：messages（+ tool_calls 经
/// FK CASCADE）、agent_stats、achievement_unlocks、pending_notifications、
/// FTS5 索引。保留 agents/conversations 骨架（理由同 [ISettingsRepo.clearAll]：
/// 避免破坏进行中流式会话的 FK 约束）。
///
/// **不清头像文件**：自定义头像属于 Agent「配置」（与昵称/主题色同等），
/// 不属于对话派生数据。二次确认对话框已向用户承诺「Agent 配置不受影响」，
/// 删头像会让磁盘文件与 `agents.avatar_url` 失同步，造成不一致。仅清空
/// 对话与依赖对话的派生缓存（统计/成就/DND/FTS5）。
///
/// 与 [clearCacheActionProvider] 的差异：
/// - **不设 [clearCacheInProgressProvider]** —— per-agent 清空是 ms 级原子事务，
///   无半提交窗口；阻止用户打开其他 agent 页面是粒度错配（其他 agent
///   完全不受影响）。
final clearAgentContentActionProvider =
    Provider<Future<void> Function(String agentId)>((ref) {
      return (agentId) async {
        final messageRepo = ref.read(messageRepoProvider);
        final settingsRepo = ref.read(settingsRepoProvider);

        // 1) DB 事务：清 messages/tool_calls(CASCADE)/stats/achievements/
        //    pending_notifications/FTS5。原子操作，失败抛回 UI 显示错误。
        await messageRepo.clearAgentContent(agentId);

        // 2) 失效 settings repo 内部的 storage info 缓存（消息数变了）。
        //    storageInfoProvider 自身有 repo 内部的时间缓存，仅 ref.invalidate
        //    不足以绕过，需显式清。
        settingsRepo.invalidateStorageCache();

        // 3) 顶层 FutureProvider 显式 invalidate（不 watch tick，需手动）。
        ref.invalidate(storageInfoProvider);
        ref.invalidate(conversationListProvider);
        ref.invalidate(statsProvider);
        ref.read(agentSyncTickerProvider.notifier).state++;

        // 4) Push 信号：让 ChatVM 温和 reloadMessages，AgentProfileVM 销毁
        //    重建。其他 agent 的 VM 也会响应一次（ms 级开销可忽略），换得
        //    与 clearAll 一致的广播契约。
        ref.read(cacheClearedTickProvider.notifier).state++;

        // 5) 搜索 VM 内部状态清空（保留 VM 实例本身，丢弃 query/results）。
        ref.read(searchViewModelProvider.notifier).clear();
      };
    });

/// Real-time network connectivity state provider (US-030).
///
/// Wraps [IConnectivity.onConnectivityChanged] in a [StreamProvider] so the
/// network settings page can display live connection status (WiFi / Mobile /
/// Ethernet / None) instead of only a static platform hint.
///
/// The stream starts with [ConnectivityResult.none] until the first real
/// platform event arrives, ensuring the provider never hangs in loading state.
final connectivityStateProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  return ref.watch(connectivityProvider).onConnectivityChanged;
});

/// Format a [ConnectivityResult] list into a human-readable label.
///
/// Example: [WiFi] → "WiFi", [WiFi, Mobile] → "WiFi + 移动网络",
/// [Ethernet] → "以太网", [None] → "无网络连接".
String connectivityResultLabel(List<ConnectivityResult> results) {
  if (results.isEmpty) return '无网络连接';

  // Filter out 'none' — if a real interface is active alongside it,
  // we should show the real interface, not claim offline.
  final active = results.where((r) => r != ConnectivityResult.none).toList();
  if (active.isEmpty) return '无网络连接';

  final parts = <String>[];
  for (final r in active) {
    switch (r) {
      case ConnectivityResult.wifi:
        parts.add('WiFi');
      case ConnectivityResult.mobile:
        parts.add('移动网络');
      case ConnectivityResult.ethernet:
        parts.add('以太网');
      case ConnectivityResult.bluetooth:
        parts.add('蓝牙');
      case ConnectivityResult.vpn:
        parts.add('VPN');
      case ConnectivityResult.other:
        parts.add('其他');
      case ConnectivityResult.satellite:
        parts.add('卫星网络');
      case ConnectivityResult.none:
        break; // Already filtered above
    }
  }
  if (parts.isEmpty) return '无网络连接';
  return parts.join(' + ');
}
