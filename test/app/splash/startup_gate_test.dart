import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/notifications/notification_bootstrap.dart';
import 'package:claw_hub/app/splash/splash_screen.dart';
import 'package:claw_hub/app/splash/startup_gate.dart';
import 'package:claw_hub/ui_kit/fatal_screen.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Fake ConnectionOrchestrator — 控制初始化的完成时机与是否抛错。
///
/// 用 `Future.delayed(completesAfter)` 模拟耗时；测试通过 `tester.pump(duration)`
/// 推进时钟来触发。`noSuchMethod` 兜底其他 IInstanceLifecycle 方法（StartupGate
/// 只调 `initialize()`，其他不碰）。
class FakeOrchestrator implements ConnectionOrchestrator {
  FakeOrchestrator({this.completesAfter = Duration.zero, this.throwsOnInit});

  final Duration completesAfter;
  final Object? throwsOnInit;

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(completesAfter);
    if (throwsOnInit != null) throw throwsOnInit!;
  }

  // 其他方法不实现 — 测试不需要
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeOrchestrator.${invocation.memberName}');
}

/// Fake NotificationBootstrap — 让我们在 init 阶段抛错（Tier 1 fatal）。
///
/// `implements` 不调用真实构造函数（Task 6 后真实构造函数需要 ProviderReader），
/// 所以 fake 不需要传 reader。`noSuchMethod` 兜底 dispose/isInitialized 等。
class FakeNotificationBootstrap implements NotificationBootstrap {
  FakeNotificationBootstrap({this.throwsOnInit});
  final Object? throwsOnInit;

  @override
  Future<void> init() async {
    if (throwsOnInit != null) throw throwsOnInit!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FakeNotificationBootstrap.${invocation.memberName}',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // PackageInfo.fromPlatform() 走 MethodChannel —— 测试环境无平台插件会抛
  // MissingPluginException，让 StartupGate 误判 init 失败而渲染 FatalScreen。
  // setMockInitialValues 直接塞 _fromPlatform 单例，短路平台调用。
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'ClawHub',
      packageName: 'com.clawhub.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // StartupGate 在 app 阶段直接渲染 `widget.child`（生产环境是
  // MaterialApp.router），FatalScreen 内的 DefaultErrorFallback 调
  // Theme.of + FilledButton（需 MaterialLocalizations）。测试用一个
  // MaterialApp 包住 StartupGate，提供 Directionality / Theme /
  // MaterialLocalizations / MediaQuery，模拟生产祖先。
  Widget wrap(StartupGate gate) => MaterialApp(home: gate);

  testWidgets('initial phase shows SplashScreen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationBootstrapProvider.overrideWith(
            (ref) => FakeNotificationBootstrap(),
          ),
          connectionOrchestratorProvider.overrideWith(
            (ref) =>
                FakeOrchestrator(completesAfter: const Duration(seconds: 10)),
          ),
        ],
        child: wrap(const StartupGate(child: Text('APP'))),
      ),
    );
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('APP'), findsNothing);
    // 清理：推进时钟越过 10s orchestrator + 800ms MinDisplayTimer，
    // 否则 flutter_test 会判 "Timer still pending" 失败。
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
    'SplashScreen shows the version during the splash phase (ARB #2)',
    (tester) async {
      // Regression for ARB finding #2: _version was set in the SAME setState as
      // _phase=app, so SplashScreen always rendered with version='' - the
      // PackageInfo fetch and version Text were dead code. After the fix, the
      // version resolves independently and renders during splash.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationBootstrapProvider.overrideWith(
              (ref) => FakeNotificationBootstrap(),
            ),
            connectionOrchestratorProvider.overrideWith(
              (ref) =>
                  FakeOrchestrator(completesAfter: const Duration(seconds: 10)),
            ),
          ],
          child: wrap(const StartupGate(child: Text('APP'))),
        ),
      );
      await tester.pump(); // first frame + postFrameCallback
      await tester.pump(); // flush PackageInfo.fromPlatform().then -> setState

      // Still in splash (orchestrator takes 10s). Version must be visible.
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(
        find.text('v1.0.0+1'),
        findsOneWidget,
        reason: 'version must render during splash, not be dead code',
      );

      // cleanup: advance past the 10s orchestrator + 800ms min display.
      await tester.pump(const Duration(seconds: 10));
    },
  );

  testWidgets('does not transition before 800ms even if init is instant', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationBootstrapProvider.overrideWith(
            (ref) => FakeNotificationBootstrap(),
          ),
          connectionOrchestratorProvider.overrideWith(
            (ref) => FakeOrchestrator(completesAfter: Duration.zero),
          ),
        ],
        child: wrap(const StartupGate(child: Text('APP'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 799));
    expect(
      find.byType(SplashScreen),
      findsOneWidget,
      reason: 'min display time not yet met',
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('APP'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('NotificationBootstrap failure → FatalScreen (Tier 1 fatal)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationBootstrapProvider.overrideWith(
            (ref) => FakeNotificationBootstrap(
              throwsOnInit: StateError('notif boom'),
            ),
          ),
          connectionOrchestratorProvider.overrideWith(
            (ref) =>
                FakeOrchestrator(completesAfter: const Duration(seconds: 10)),
          ),
        ],
        child: wrap(const StartupGate(child: Text('APP'))),
      ),
    );
    // bootstrap.init() 微任务抛错 → _runInitialization 返回 rejected Future。
    // 关键：Future.wait 默认 eagerError:false，要等所有 future settle 才 reject。
    // MinDisplayTimer.wait(800ms) 还在跑，所以 Future.wait 不会立即 reject。
    // 必须 pump 800ms 让 timer 到期 → Future.wait reject → _runStartup catch → FatalScreen。
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(FatalScreen), findsOneWidget);
    expect(find.text('APP'), findsNothing);
    // 清理：bootstrap 抛错在 orchestrator 之前，10s timer 不会创建；
    // 但 800ms MinDisplayTimer 已 schedule 且 Future.wait reject 后无人
    // cancel，必须推进时钟触发它，否则 "Timer still pending"。
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets(
    'ConnectionOrchestrator failure → app shell mounts (Tier 2 soft-fail)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationBootstrapProvider.overrideWith(
              (ref) => FakeNotificationBootstrap(),
            ),
            connectionOrchestratorProvider.overrideWith(
              (ref) => FakeOrchestrator(throwsOnInit: StateError('net boom')),
            ),
          ],
          child: wrap(const StartupGate(child: Text('APP'))),
        ),
      );
      await tester.pump();
      // orchestrator Duration.zero 抛错 → Tier-2 catch → connectionInitStateProvider
      // 写错误（in-app banner 用，本测试不断言）。_runInitialization 正常完成。
      // 推进 800ms 让 MinDisplayTimer 到期 → Future.wait 完成 → 切 app 阶段。
      // （不能用 pumpAndSettle：Tier-2 catch 不调度帧，pumpAndSettle 会在
      //  800ms 之前因 "no scheduled frame" 提前停止，导致 app 阶段永不 mount。）
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('APP'), findsOneWidget);
      expect(find.byType(FatalScreen), findsNothing);
      expect(find.byType(SplashScreen), findsNothing);
    },
  );

  testWidgets('precacheImage fires in initState', (tester) async {
    // AssetImage 在 imageCache 里的 key 是 AssetBundleImageKey（不是
    // AssetImage 本身 —— AssetBundleImageProvider extends
    // ImageProvider<AssetBundleImageKey>，见 flutter SDK
    // painting/image_provider.dart:727）。必须用同构 key 查缓存，
    // 否则 containsKey(AssetImage) 恒为 false。
    final splashKey = AssetBundleImageKey(
      bundle: rootBundle,
      // 引用 kSplashImagePath 常量，避免资产路径漂移时测试忘记同步
      // （splash_screen.dart 改路径，此测试若硬编码会假绿）。
      name: kSplashImagePath,
      scale: 1.0,
    );
    imageCache.clear();
    imageCache.clearLiveImages();
    expect(imageCache.containsKey(splashKey), isFalse, reason: 'precondition');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationBootstrapProvider.overrideWith(
            (ref) => FakeNotificationBootstrap(),
          ),
          connectionOrchestratorProvider.overrideWith(
            (ref) =>
                FakeOrchestrator(completesAfter: const Duration(seconds: 10)),
          ),
        ],
        child: wrap(const StartupGate(child: Text('APP'))),
      ),
    );
    await tester.pump(); // 首帧 + postFrameCallback → precacheImage → resolve
    await tester.pump(const Duration(milliseconds: 16)); // 保险：让 resolve 微任务跑完
    expect(
      imageCache.containsKey(splashKey),
      isTrue,
      reason: 'precacheImage should put splash asset in cache',
    );
    imageCache.clear();
    imageCache.clearLiveImages();
    // 清理：10s orchestrator + 800ms MinDisplayTimer。
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
    'Tier 2 soft-fail writes connectionInitStateProvider AsyncValue.error',
    (tester) async {
      // Spec: Tier 2 (Connection soft-fail) 不能进 FatalScreen，但必须把错误
      // 写进 connectionInitStateProvider，让 in-app banner / 后续重试逻辑看到。
      // 这个测试断言副作用真的发生了。
      final container = ProviderContainer(
        overrides: [
          notificationBootstrapProvider.overrideWith(
            (ref) => FakeNotificationBootstrap(),
          ),
          connectionOrchestratorProvider.overrideWith(
            (ref) => FakeOrchestrator(throwsOnInit: StateError('net boom')),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(connectionInitStateProvider),
        isNull,
        reason: 'precondition: nothing written yet',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: wrap(const StartupGate(child: Text('APP'))),
        ),
      );
      await tester.pump();
      // 推进 800ms 让 MinDisplayTimer 到期 → Future.wait settle → _runStartup
      // 完成 → 切到 app 阶段。同时 orchestrator 抛错触发 Tier-2 catch。
      await tester.pump(const Duration(milliseconds: 800));

      final state = container.read(connectionInitStateProvider);
      expect(state, isNotNull);
      expect(
        state!.hasError,
        isTrue,
        reason: 'Tier 2 catch should write AsyncValue.error',
      );
      expect(state.error, isA<StateError>());
    },
  );
}
