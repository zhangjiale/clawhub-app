import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:claw_hub/core/acl/ed25519_identity_provider.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_device_identity_provider.dart';
import 'package:claw_hub/core/acl/i_device_token_store.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/secure_storage_device_token_store.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:claw_hub/data/services/avatar_storage_service.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/iconnectivity.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/data/repositories/drift_conversation_repo.dart';
import 'package:claw_hub/data/repositories/drift_settings_repo.dart';
import 'package:claw_hub/data/repositories/drift_achievement_repo.dart';
import 'package:claw_hub/data/repositories/drift_activity_repo.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/services/achievement_checker.dart';
import 'package:claw_hub/data/local/database/database.dart'
    hide UserPreferences;
import 'package:claw_hub/domain/models/stats_data.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/domain/usecases/save_instance.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/domain/usecases/delete_instance.dart';
import 'package:claw_hub/domain/usecases/outbox_processor.dart';
import 'package:claw_hub/domain/usecases/message_catch_up_service.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/app/connection/instance_event.dart';
import 'package:claw_hub/app/config/app_config.dart';
import 'package:claw_hub/app/config/device_model_loader.dart';
import 'package:claw_hub/app/config/platform_info.dart';
import 'package:claw_hub/app/notifications/notification_coordinator.dart';
import 'package:claw_hub/core/i_local_notification_service.dart';
import 'package:claw_hub/data/repositories/drift_notification_repo.dart';
import 'package:claw_hub/data/services/local_notification_service.dart';

/// ============================================================
/// ClawHub 依赖注入容器 (Riverpod)
/// 对齐: 架构 vFinal 3.0 (系统逻辑架构), 8.2 (app/di/)
/// ============================================================

// --- Shared invalidation tokens (no circular deps) ---

/// Agent 同步完成信号 — [ConnectionOrchestrator] 在 _syncAgentsForInstance
/// 成功后写入被同步的 instanceId。
///
/// [agentListProvider] / [conversationListProvider] 通过 watch 此值在
/// 任意实例同步完成后自动 refresh UI。每次 sync 都递增 [revision]，即使
/// 连续两次同步同一个 instanceId，也会产生不相等的新值，避免 Riverpod
/// 因同值写入去重而丢掉第二次通知。
///
/// Chat / AgentProfile 的 ticker listener 必须按
/// `tick.instanceId == self.instanceId` 过滤再触发本实例的 refreshAgent —— 否则
/// 任意实例 sync 会导致所有 active ChatRoom/Profile 页面的
/// `_agentRepo.getById()` 被重查一次（N 个实例 × 1 sync = N 次冗余 read）。
class AgentSyncTick {
  final int revision;
  final String instanceId;

  const AgentSyncTick({required this.revision, required this.instanceId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentSyncTick &&
          revision == other.revision &&
          instanceId == other.instanceId;

  @override
  int get hashCode => Object.hash(revision, instanceId);
}

final agentSyncTickerProvider = StateProvider<AgentSyncTick?>((ref) => null);

/// Outbox 冲刷完成信号 — [OutboxProcessor.flushOutbox] 成功发送至少一条消息后递增。
///
/// 按 instanceId 隔离，避免实例 A 冲刷时触发实例 B/C/D 的 ChatViewModel
/// 不必要的 reloadMessages() 调用（广播风暴）。
///
/// **收窄后的职责**：仅作"整轮 flush 完成 → 重载消息列表"的 fire-once 信号，
/// 让聊天气泡反映冲刷后的最终 SENT 状态（PENDING → SENDING → SENT 的状态变更
/// 不经 messageStream，per-write 的 watchOutboxCount stream 无法表达"整轮结束"语义）。
///
/// outbox **计数**已改为 stream 驱动（[IMessageRepo.watchOutboxCount]），
/// 不再经过此 ticker —— 本信号仅用于消息列表重载。
/// 完整移除本信号需方案 A 全量的 watchByConversation，留待后续迭代。
final outboxFlushTickerProvider = StateProvider.family<int, String>(
  (ref, instanceId) => 0,
);

/// 配对信息 — instanceId → GatewayPairingInfo。
///
/// [ConnectionOrchestrator] 在收到 PAIRING_REQUIRED 时写入，
/// UI 层 watch 此 provider 以在实例卡片上展示审批指引。
final pairingInfoProvider = StateProvider<Map<String, GatewayPairingInfo>>(
  (ref) => {},
);

/// 重连耗尽状态 — instanceId 集合（US-016 AC-3）。
///
/// [ConnectionOrchestrator] 在重连耗尽时通过 [ReconnectExhaustedEvent]
/// 将 instanceId 加入此 Set。连接成功后从 Set 中移除。
/// UI 层 watch 此 provider 以展示"无法连接到虾"重试提示。
final reconnectExhaustedProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// 历史同步截断状态 — instanceId 集合（US-016 AC-2）。
///
/// [MessageCatchUpService] 在断线重连增量同步撞到翻页上限（仍有更早历史
/// 未拉取）时，由 [connectionOrchestratorProvider] 的事件处理器将
/// instanceId 加入此 Set；下次完整同步（非截断）后移除。
///
/// 与 [reconnectExhaustedProvider] 不同：截断信息无法从连接状态枚举派生
/// （它是同步结果而非连接状态），故独立承载——这是必要的"额外数据"，
/// 不构成 SSOT 双源问题。UI 层 watch 此 provider 以展示
/// "历史消息较多，仅同步了最近部分"提示，避免用户误以为历史已完整。
final catchUpTruncatedProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

// --- Shared Stats (used by agent_list and chat_room features) ---

/// 全局统计 Provider — 从实例、Agent、消息仓库聚合统计快照。
///
/// 数据类 [StatsData] 已迁至 [package:claw_hub/domain/models/stats_data.dart]
/// (Clean Architecture: 值对象属于 domain/models/，非 app/di/)。
///
/// [chat_room] 在消息发送/接收后通过 [ref.invalidate] 刷新此 provider，
/// 使 agent_list 页的统计栏自动反映最新计数。
final statsProvider = FutureProvider<StatsData>((ref) async {
  final instances = await ref.watch(instanceRepoProvider).getAll();
  final agents = await ref.watch(agentRepoProvider).getAll();
  final messageRepo = ref.watch(messageRepoProvider);

  final activeInstances = instances
      .where((i) => i.healthStatus.isConnectable)
      .length;

  final onlineInstanceIds = instances
      .where((i) => i.healthStatus.isConnectable)
      .map((i) => i.id)
      .toSet();

  final onlineAgents = agents
      .where((a) => onlineInstanceIds.contains(a.instanceId))
      .length;

  final agentIds = agents.map((a) => a.localId).toList();
  final counts = await messageRepo.getMessageCountsByAgent(agentIds);
  final totalMessages = counts.values.fold<int>(0, (sum, c) => sum + c);

  return StatsData(
    activeInstances: activeInstances,
    totalInstances: instances.length,
    onlineAgents: onlineAgents,
    totalAgents: agents.length,
    totalMessages: totalMessages,
  );
});

// --- Connection Initialization State ---

/// 连接编排器初始化状态。
///
/// [ConnectionOrchestrator.initialize] 完成后设置为 [AsyncValue.data]，
/// 失败时设置为 [AsyncValue.error]。UI 可 watch 此 provider 以在
/// 初始化失败时展示 SnackBar 或重试按钮。
final connectionInitStateProvider = StateProvider<AsyncValue<void>?>(
  (ref) => null,
);

// --- Gateway Client ---

/// Mock Gateway 客户端（开发/调试用，生产环境默认使用 [wsGatewayClientProvider]）
final mockGatewayClientProvider = Provider<MockGatewayClient>((ref) {
  final client = MockGatewayClient();
  ref.onDispose(() => client.dispose());
  return client;
});

/// 设备身份提供者 — Ed25519 密钥管理 + V3 签名。
///
/// 使用 [FlutterSecureStorage] 持久化密钥对。
/// 可通过 override 注入 fake 以进行单元测试。
final deviceIdentityProvider = Provider<IDeviceIdentityProvider>((ref) {
  return Ed25519IdentityProvider(
    secureStorage: const FlutterSecureStorage(),
    logger: ref.watch(loggerProvider),
  );
});

/// 设备令牌（deviceToken）存储 — 持久化 Gateway 签发的设备令牌（差距 #1）。
///
/// 后续重连时优先复用缓存令牌（spec §2.2 后续重连复用该令牌），
/// 避免重复走 device.pair 审批流程。
/// 可通过 override 注入 fake 以进行单元测试。
final deviceTokenStoreProvider = Provider<IDeviceTokenStore>((ref) {
  return SecureStorageDeviceTokenStore(
    secureStorage: const FlutterSecureStorage(),
  );
});

/// Cached device model identifier — the platform channel call only needs
/// to happen once per app lifetime. Injecting a FutureProvider keeps the
/// loader's expensive call (10–50ms iOS/Android) out of every reconnect.
final deviceModelIdentifierProvider = FutureProvider<String?>((ref) {
  return loadDeviceModelIdentifier();
});

/// 真实 WebSocket Gateway 客户端（当前生产默认实现）。
///
/// 开发/调试时如需使用 Mock 数据，将 [gatewayClientProvider] 的返回值
/// 改回 `ref.watch(mockGatewayClientProvider)` 即可全局切回 Mock。
///
/// 自动检测运行平台（iOS / Android），选择对应的 [ClientIds] 枚举值，
/// 确保 Gateway 将虾Hub 识别为官方客户端。
final wsGatewayClientProvider = Provider<WsGatewayClient>((ref) {
  final os = platformOS(); // 'ios', 'android', 'macos', 'web', ...
  final clientId = ClientIds.forPlatform(os);
  final deviceFamily = os == 'ios' || os == 'android' ? 'phone' : 'desktop';

  // TODO: read locale from PlatformDispatcher.instance.locale when
  // i18n is implemented.
  final client = WsGatewayClient(
    identityProvider: ref.watch(deviceIdentityProvider),
    config: ConnectionConfig(
      locale: 'zh-CN',
      platform: os,
      clientId: clientId,
      deviceFamily: deviceFamily,
      clientDisplayName: '虾Hub',
      clientVersion: AppClientInfo.version,
    ),
    // 设备型号在 DI 容器启动时解析一次并缓存,connect 时只读取缓存值,
    // 避免每次 reconnect 都重新走 platform channel(10-50ms 阻塞)。
    modelIdentifierLoader: () => ref.read(deviceModelIdentifierProvider.future),
    // 差距 #1: 持久化 deviceToken，后续重连优先复用。
    deviceTokenStore: ref.watch(deviceTokenStoreProvider),
  );
  ref.onDispose(() => client.dispose());
  return client;
});

/// Gateway 防腐层接口（面向接口编程，方便 Mock ↔ 真实实现互换）
///
/// 当前指向 MockGatewayClient（MVP / 开发阶段默认，可离线开发）。
/// 生产环境：改为 `return ref.watch(wsGatewayClientProvider);`
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(wsGatewayClientProvider);
});

// --- Network Monitoring ---

/// 日志接口 — 生产环境使用 [DebugPrintLogger]。
///
/// 测试可通过 override 注入 fake 以验证日志输出。
final loggerProvider = Provider<ILogger>((ref) => const DebugPrintLogger());

/// 网络连接监听器 — 面向 [IConnectivity] 接口，便于单测 mock。
///
/// 由 [ConnectionOrchestrator] 订阅，用于检测 WiFi ↔ 4G 切换，
/// 自动降级/恢复内网实例的连接状态。
final connectivityProvider = Provider<IConnectivity>(
  (ref) => ConnectivityAdapter(),
);

// --- Avatar Storage ---

/// 头像文件存储服务 — 面向 [IAvatarStorageService] 接口，便于单测 mock。
///
/// 头像文件存储在 `{appDocDir}/avatars/{agentLocalId}.jpg`。
/// [AgentProfileViewModel] 通过此接口保存/删除/检查头像文件。
final avatarStorageServiceProvider = Provider<IAvatarStorageService>((ref) {
  return AvatarStorageService(logger: ref.watch(loggerProvider));
});

// --- Connection Orchestrator ---

/// 全局连接编排器 — 管理所有 Gateway 实例的连接生命周期。
///
/// 生命周期与 App 一致；由 `_ConnectionInitializer.initState`（见 main.dart）
/// 在 widget 树首次 build 时调用 [ConnectionOrchestrator.initialize]，
/// 以确保 ProviderScope 已就绪后才启动自动连接和网络监听。
///
/// 同时作为 [IInstanceLifecycle] 注入到 [SaveInstanceUseCase]，
/// 使 UseCase 在持久化完成后自动触发 WebSocket 连接编排，
/// UI 层无需直接依赖编排器。
final connectionOrchestratorProvider = Provider<ConnectionOrchestrator>((ref) {
  final orchestrator = ConnectionOrchestrator(
    gatewayClient: ref.watch(gatewayClientProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    connectivity: ref.watch(connectivityProvider),
  );

  // 订阅编排器生命周期事件（替代旧的三段回调闭包）。
  // 订阅在 provider body 内同步建立，早于 initialize() 的异步事件源
  // （已核对 main.dart:76-77 时序），故无晚订阅丢事件风险。
  final streamSub = orchestrator.events.listen(
    (event) {
      switch (event) {
        case AgentsSyncedEvent(:final instanceId):
          // ticker 携带被同步的 instanceId,让 chat/agent_profile 的
          // listener 能按实例过滤（BUG B 修复,避免跨实例 N+1 getById）。
          final notifier = ref.read(agentSyncTickerProvider.notifier);
          notifier.state = AgentSyncTick(
            revision: (notifier.state?.revision ?? 0) + 1,
            instanceId: instanceId,
          );
        case PairingInfoChangedEvent(:final instanceId, :final info):
          final notifier = ref.read(pairingInfoProvider.notifier);
          final newMap = Map<String, GatewayPairingInfo>.from(notifier.state);
          if (info == null) {
            newMap.remove(instanceId);
          } else {
            newMap[instanceId] = info;
          }
          notifier.state = newMap;
        case InstanceConnectedEvent(:final instanceId):
          // 在 agent sync 完成后触发。fire-and-forget。
          unawaited(() async {
            // Step 1: Message incremental sync (US-016 AC-1/AC-2)
            // Best-effort — failure does NOT block outbox flush.
            try {
              final catchUpService = ref.read(messageCatchUpServiceProvider);
              final result = await catchUpService.catchUp(instanceId);
              // US-016 AC-2: surface truncation to UI. 撞翻页上限意味着更早
              // 历史未拉取——必须通知 UI，否则用户会误以为历史已完整。
              // 非截断（含 0 插入）则清除上次的截断标记。
              final truncatedNotifier = ref.read(
                catchUpTruncatedProvider.notifier,
              );
              final wasTruncated = truncatedNotifier.state.contains(instanceId);
              if (result.truncated && !wasTruncated) {
                truncatedNotifier.state = {
                  ...truncatedNotifier.state,
                  instanceId,
                };
              } else if (!result.truncated && wasTruncated) {
                truncatedNotifier.state = {...truncatedNotifier.state}
                  ..remove(instanceId);
              }
            } catch (e, st) {
              ref
                  .read(loggerProvider)
                  .error(
                    '[Post-connect] Message catch-up failed for '
                    '$instanceId: $e',
                    st,
                  );
            }

            // Step 2: Outbox flush (US-015) — always runs.
            try {
              final processor = ref.read(outboxProcessorProvider);
              final sent = await processor.flushOutbox(instanceId);
              if (sent > 0) {
                ref
                    .read(outboxFlushTickerProvider(instanceId).notifier)
                    .state++;
              }
            } catch (e, st) {
              ref
                  .read(loggerProvider)
                  .error(
                    '[Post-connect] Outbox flush failed for $instanceId: $e',
                    st,
                  );
            }

            // Clear reconnectExhausted state on successful reconnect
            final notifier = ref.read(reconnectExhaustedProvider.notifier);
            if (notifier.state.contains(instanceId)) {
              notifier.state = {...notifier.state}..remove(instanceId);
            }
          }());

        case ReconnectExhaustedEvent(:final instanceId):
          // US-016 AC-3: auto-reconnect exhausted, show retry prompt
          final notifier = ref.read(reconnectExhaustedProvider.notifier);
          if (!notifier.state.contains(instanceId)) {
            notifier.state = {...notifier.state, instanceId};
          }
      }
    },
    onError: (Object error, StackTrace stack) {
      // 事件处理器自身的未捕获异常 — 日志记录，不崩溃。
      // 取代旧 onInstanceConnected 闭包里静默吞异常的 catch (_)。
      ref
          .read(loggerProvider)
          .error('[ConnectionOrchestrator] Event handler error: $error', stack);
    },
  );

  ref.onDispose(() {
    streamSub.cancel();
    orchestrator.dispose();
  });
  return orchestrator;
});

// --- Database ---

/// Drift/SQLite 数据库实例。
///
/// 默认实现会创建磁盘上的数据库，并在 provider 被 dispose 时自动 close。
/// [main()] 通过 `overrideWith` 提前创建好实例并注入，同样会注册 dispose 钩子
/// 以保证应用退出时数据库被正确关闭。测试侧可用内存 DB 替换。
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden in main() via '
    'databaseProvider.overrideWith(...) so the AppDatabase lifecycle '
    '(creation + close) is owned by a single place.',
  );
});

// --- Repositories ---

final instanceRepoProvider = Provider<IInstanceRepo>((ref) {
  return DriftInstanceRepo(ref.watch(databaseProvider));
});

final agentRepoProvider = Provider<IAgentRepo>((ref) {
  return DriftAgentRepo(
    ref.watch(databaseProvider),
    avatarStorage: ref.watch(avatarStorageServiceProvider),
  );
});

final messageRepoProvider = Provider<IMessageRepo>((ref) {
  return DriftMessageRepo(ref.watch(databaseProvider));
});

final conversationRepoProvider = Provider<IConversationRepo>((ref) {
  return DriftConversationRepo(ref.watch(databaseProvider));
});

final settingsRepoProvider = Provider<ISettingsRepo>((ref) {
  return DriftSettingsRepo(
    ref.watch(databaseProvider),
    avatarStorageService: ref.watch(avatarStorageServiceProvider),
    logger: ref.watch(loggerProvider),
  );
});

final achievementRepoProvider = Provider<IAchievementRepo>((ref) {
  return DriftAchievementRepo(ref.watch(databaseProvider));
});

final activityRepoProvider = Provider<IActivityRepo>((ref) {
  return DriftActivityRepo(ref.watch(databaseProvider));
});

final evaluateAchievementsUseCaseProvider =
    Provider<EvaluateAchievementsUseCase>(
      (ref) => EvaluateAchievementsUseCase(ref.watch(achievementRepoProvider)),
    );

final achievementCheckerProvider = Provider<IAchievementChecker>((ref) {
  return AchievementChecker(
    ref.watch(evaluateAchievementsUseCaseProvider),
    ref.watch(loggerProvider),
  );
});

// --- Notifications (US-018) ---

/// 平台本地通知服务 (ACL) — 封装 flutter_local_notifications。
final iLocalNotificationServiceProvider = Provider<ILocalNotificationService>((
  ref,
) {
  final service = LocalNotificationService();
  ref.onDispose(service.dispose);
  return service;
});

/// DND 静默队列仓库。
final notificationRepoProvider = Provider<INotificationRepo>((ref) {
  return DriftNotificationRepo(ref.watch(databaseProvider));
});

/// 通知评估 UseCase (纯 domain，无状态)。
final evaluateNotificationUseCaseProvider =
    Provider<EvaluateNotificationUseCase>(
      (_) => const EvaluateNotificationUseCase(),
    );

/// 持有最新 UserPreferences 快照，供 dispatcher/coordinator 同步读取。
/// 由 [NotificationBootstrap] 通过 watchPreferences() 流更新。
final notificationPrefsHolderProvider = StateProvider<UserPreferences>(
  (_) => UserPreferences.defaults(),
);

/// 通知协调器 (app 层) — 桥接 Gateway 流到 dispatcher，并拥有 dispatcher。
/// 生命周期由 [NotificationBootstrap] 管理 (start/dispose)。
final notificationCoordinatorProvider = Provider<NotificationCoordinator>((
  ref,
) {
  final coordinator = NotificationCoordinator(
    orchestratorEvents: ref.watch(connectionOrchestratorProvider).events,
    gatewayClient: ref.watch(gatewayClientProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    notificationRepo: ref.watch(notificationRepoProvider),
    notificationService: ref.watch(iLocalNotificationServiceProvider),
    evaluator: ref.watch(evaluateNotificationUseCaseProvider),
    prefsProvider: () => ref.read(notificationPrefsHolderProvider),
    clock: DateTime.now,
    logger: ref.watch(loggerProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

// --- Use Cases ---

final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  return SendMessageUseCase(
    messageRepo: ref.watch(messageRepoProvider),
    conversationRepo: ref.watch(conversationRepoProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
  );
});

/// OutboxProcessor — 离线消息队列冲刷处理器（US-015）。
///
/// 在 [ConnectionOrchestrator] 检测到实例重连成功且 agent 同步完成后触发，
/// 按 [Message.logicalClock] 升序冲刷 PENDING + FAILED 消息。
final outboxProcessorProvider = Provider<OutboxProcessor>((ref) {
  return OutboxProcessor(
    messageRepo: ref.watch(messageRepoProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    sendMessageUseCase: ref.watch(sendMessageUseCaseProvider),
    logger: ref.watch(loggerProvider),
  );
});

/// MessageCatchUpService — 断线重连后增量同步 Gateway 新消息（US-016）。
///
/// 在 [OutboxProcessor.flushOutbox] 之前运行，确保本地消息库拥有
/// 完整的会话上下文后再冲刷待发送队列。
final messageCatchUpServiceProvider = Provider<MessageCatchUpService>((ref) {
  return MessageCatchUpService(
    agentRepo: ref.watch(agentRepoProvider),
    messageRepo: ref.watch(messageRepoProvider),
    conversationRepo: ref.watch(conversationRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
    logger: ref.watch(loggerProvider),
  );
});

final saveInstanceUseCaseProvider = Provider<SaveInstanceUseCase>((ref) {
  return SaveInstanceUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
    lifecycle: ref.watch(connectionOrchestratorProvider),
    logger: ref.watch(loggerProvider),
  );
});

final deleteInstanceUseCaseProvider = Provider<DeleteInstanceUseCase>((ref) {
  return DeleteInstanceUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    lifecycle: ref.watch(connectionOrchestratorProvider),
  );
});

final syncAgentsUseCaseProvider = Provider<SyncAgentsUseCase>((ref) {
  return SyncAgentsUseCase(
    instanceRepo: ref.watch(instanceRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    gatewayClient: ref.watch(gatewayClientProvider),
    logger: ref.watch(loggerProvider),
  );
});
