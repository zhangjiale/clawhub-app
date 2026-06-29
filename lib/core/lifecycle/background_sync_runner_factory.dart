import 'package:claw_hub/app/config/app_config.dart';
import 'package:claw_hub/app/config/platform_info.dart';
import 'package:claw_hub/core/acl/ed25519_identity_provider.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/secure_storage_device_token_store.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/background_sync_prefs_shared_prefs.dart';
import 'package:claw_hub/core/lifecycle/background_sync_runner.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_notifier.dart';
import 'package:claw_hub/data/local/database/database.dart'
    hide Message, Agent, PendingNotification;
import 'package:claw_hub/data/local/database/database_initializer.dart';
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/data/repositories/drift_last_sync_repo.dart';
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/data/repositories/drift_notification_repo.dart';
import 'package:claw_hub/data/repositories/drift_settings_repo.dart';
import 'package:claw_hub/data/services/background_notifier_shared.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

// ---------------------------------------------------------------------------
// callbackDispatcher — background isolate entry point
// ---------------------------------------------------------------------------

/// US-018 background isolate entry point.
///
/// MUST be top-level + @pragma('vm:entry-point') — workmanager calls it from
/// a fresh isolate with NO ProviderScope. Rebuild every dependency from
/// scratch here.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final logger = const DebugPrintLogger();
    try {
      final db = await createAppDatabase();

      // 1. Gate check — skip if main isolate is active
      final gate = BackgroundSyncGate(
        prefs: const SharedPreferencesBackgroundSyncPrefs(),
      );
      if (await gate.shouldSkip()) {
        logger.info('[BgSync] dispatcher: main active, skip');
        await db.close();
        return true;
      }

      // 2. Settings check — skip if toggle is off
      final settingsRepo = DriftSettingsRepo(db, logger: logger);
      final prefs = await settingsRepo.getPreferences();
      if (!prefs.backgroundSyncEnabled) {
        logger.info('[BgSync] dispatcher: toggle off, skip');
        await db.close();
        return true;
      }

      // 3. Build gateway client for background isolate
      //    Ed25519IdentityProvider reads from flutter_secure_storage (same
      //    process — keychain access works).
      //    Mirror the main isolate's ConnectionConfig (providers.dart:238-263)
      //    as closely as feasible without a ProviderScope.
      final os = platformOS();
      final clientId = ClientIds.forPlatform(os);
      final deviceFamily = os == 'ios' || os == 'android' ? 'phone' : 'desktop';
      final gateway = WsGatewayClient(
        identityProvider: Ed25519IdentityProvider(
          secureStorage: const FlutterSecureStorage(),
          logger: logger,
        ),
        config: ConnectionConfig(
          locale: 'zh-CN',
          platform: os,
          clientId: clientId,
          deviceFamily: deviceFamily,
          clientDisplayName: '虾Hub',
          clientVersion: AppClientInfo.version,
        ),
        // modelIdentifierLoader is omitted here: it's a FutureProvider in the
        // main isolate (deviceModelIdentifierProvider) that reads from
        // platform channel. The background isolate has no ProviderScope.
        // The gateway tolerates a missing modelIdentifier — it's diagnostic,
        // not auth-critical.
        deviceTokenStore: SecureStorageDeviceTokenStore(
          secureStorage: const FlutterSecureStorage(),
        ),
      );

      // 4. Build and run the sync runner
      final notifier = _BackgroundIsolateNotifier(db, logger);
      final runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: DriftInstanceRepo(db),
        gatewayClient: gateway,
        agentRepo: DriftAgentRepo(db),
        messageRepo: DriftMessageRepo(db),
        lastSyncRepo: DriftLastSyncRepo(db),
        dispatcher: notifier,
        budget: BackgroundSyncBudget(),
        logger: logger,
        now: () => DateTime.now().millisecondsSinceEpoch,
      );

      await runner.executeOnce();
      await gateway.dispose();
      await db.close();
      return true;
    } catch (e, st) {
      logger.error('[BgSync] dispatcher failed: $e', st);
      return false; // workmanager will retry per its backoff (acceptable)
    }
  });
}

// ---------------------------------------------------------------------------
// _BackgroundIsolateNotifier
// ---------------------------------------------------------------------------

/// Minimal notifier for the background isolate: routes pulled messages
/// through the persistent pending_notifications path (same contract as the
/// main NotificationDispatcher.handlePulledMessages, but without the live
/// event stream / DND timer). Reuses BackgroundNotifierShared.enqueuePulled.
class _BackgroundIsolateNotifier implements IBackgroundSyncNotifier {
  final AppDatabase _db;
  final ILogger _logger;
  final EvaluateNotificationUseCase _evaluator;

  _BackgroundIsolateNotifier(this._db, this._logger)
    : _evaluator = EvaluateNotificationUseCase();

  @override
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String instanceId, String agentRemoteId)
    resolveAgent,
  }) async {
    final settingsRepo = DriftSettingsRepo(_db, logger: _logger);
    final prefs = await settingsRepo.getPreferences();
    final notificationRepo = DriftNotificationRepo(_db);

    await BackgroundNotifierShared.enqueuePulled(
      messages: messages,
      resolveAgent: resolveAgent,
      prefs: prefs,
      evaluator: _evaluator,
      repo: notificationRepo,
      logger: _logger,
    );
  }
}
