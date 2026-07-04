// ---------------------------------------------------------------------------
// US-018 background isolate composition root.
//
// This file is the entry point workmanager dispatches to from a fresh
// background isolate (no ProviderScope). It therefore rebuilds every
// dependency from scratch and intentionally imports `app/` + `data/` — it is
// a composition root, so it lives in `app/` (not `core/`) to respect the
// layering rule: `core/` must not depend on `app/` or `data/`.
//
// `buildGatewayClient` is also consumed by the main isolate's
// `wsGatewayClientProvider` (lib/app/di/providers.dart) so the Gateway
// construction stays single-sourced across both isolates.
// ---------------------------------------------------------------------------

import 'package:claw_hub/app/config/app_config.dart';
import 'package:claw_hub/app/config/platform_info.dart';
import 'package:claw_hub/core/acl/ed25519_identity_provider.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_device_identity_provider.dart';
import 'package:claw_hub/core/acl/i_device_token_store.dart';
import 'package:claw_hub/core/acl/secure_storage_device_token_store.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/background_sync_prefs_shared_prefs.dart';
import 'package:claw_hub/core/lifecycle/background_sync_runner.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_notifier.dart';
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
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Top-level logger reused across every [callbackDispatcher] invocation.
/// The workmanager plugin spins up a fresh isolate per task; this constant
/// is intentionally stateless so it's safe to capture into closures.
const ILogger _kBgSyncLogger = DebugPrintLogger();

// ---------------------------------------------------------------------------
// buildGatewayClient — shared Gateway constructor (main + background isolate)
// ---------------------------------------------------------------------------

/// Constructs the production [WsGatewayClient] with the canonical
/// [ConnectionConfig] (locale / platform / clientId / deviceFamily /
/// clientDisplayName / clientVersion).
///
/// Shared between the main isolate (`wsGatewayClientProvider` in
/// providers.dart) and the background isolate ([callbackDispatcher]) so the
/// ConnectionConfig + platform-detection logic lives in exactly one place —
/// a protocol upgrade changes one function, not two parallel constructions.
///
/// [identityProvider] / [deviceTokenStore] are optional: the main isolate
/// passes its Riverpod-provided instances (preserving test overrides); the
/// background isolate omits them and gets the secure-storage-backed defaults
/// (identical to `deviceIdentityProvider` / `deviceTokenStoreProvider`).
///
/// [modelIdentifierLoader] is omitted by the background isolate: it is a
/// FutureProvider backed by a platform channel in the main isolate, which has
/// no ProviderScope in the background isolate. The gateway tolerates a
/// missing modelIdentifier (diagnostic only, not auth-critical).
WsGatewayClient buildGatewayClient({
  required ILogger logger,
  IDeviceIdentityProvider? identityProvider,
  IDeviceTokenStore? deviceTokenStore,
  Future<String?> Function()? modelIdentifierLoader,
}) {
  final os = platformOS(); // 'ios', 'android', 'macos', 'web', ...
  final clientId = ClientIds.forPlatform(os);
  final deviceFamily = os == 'ios' || os == 'android' ? 'phone' : 'desktop';

  // TODO: read locale from PlatformDispatcher.instance.locale when
  // i18n is implemented.
  return WsGatewayClient(
    identityProvider:
        identityProvider ??
        Ed25519IdentityProvider(
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
    modelIdentifierLoader: modelIdentifierLoader,
    deviceTokenStore:
        deviceTokenStore ??
        SecureStorageDeviceTokenStore(
          secureStorage: const FlutterSecureStorage(),
        ),
    logger: logger,
  );
}

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
    final logger = _kBgSyncLogger;
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

      // 3. Build gateway client for background isolate.
      //    Shared with the main isolate's wsGatewayClientProvider via
      //    buildGatewayClient() — only modelIdentifierLoader differs (omitted
      //    here: no ProviderScope / platform channel in the background
      //    isolate; the gateway tolerates a missing modelIdentifier —
      //    diagnostic only, not auth-critical).
      final gateway = buildGatewayClient(logger: logger);

      // 4. Build and run the sync runner
      final notifier = _BackgroundIsolateNotifier(
        prefs: prefs,
        evaluator: EvaluateNotificationUseCase(),
        notificationRepo: DriftNotificationRepo(db),
        logger: logger,
      );
      // US-018 — message merge + dedup happen inside the runner via
      // IMessageRepo.batchInsertByIndexedIds (per-agent cursor refactor,
      // see background_sync_runner.dart:_syncAgent). The runner does NOT
      // take a separate mergeUseCase — concurrency guards live in the repo.
      final messageRepoForRunner = DriftMessageRepo(db);
      final runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: DriftInstanceRepo(db),
        gatewayClient: gateway,
        agentRepo: DriftAgentRepo(db),
        messageRepo: messageRepoForRunner,
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
///
/// All dependencies are injected so each `handlePulledMessages` call avoids
/// re-reading prefs or rebuilding repos — they were already constructed once
/// in [callbackDispatcher].
class _BackgroundIsolateNotifier implements IBackgroundSyncNotifier {
  final UserPreferences prefs;
  final EvaluateNotificationUseCase evaluator;
  final INotificationRepo notificationRepo;
  final ILogger logger;

  _BackgroundIsolateNotifier({
    required this.prefs,
    required this.evaluator,
    required this.notificationRepo,
    required this.logger,
  });

  @override
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String agentRemoteId) resolveAgent,
  }) async {
    await BackgroundNotifierShared.enqueuePulled(
      messages: messages,
      resolveAgent: resolveAgent,
      prefs: prefs,
      evaluator: evaluator,
      repo: notificationRepo,
      logger: logger,
    );
  }
}
