import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/notifications/notification_bootstrap.dart';
import 'package:claw_hub/app/splash/startup_gate.dart';
import 'package:claw_hub/ui_kit/fatal_screen.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// 找 splash 占位的桃粉 ColoredBox（#FDD3BC）。
///
/// MaterialApp 的 Scaffold 自带透明黑色 ColoredBox 背景，
/// `find.byType(ColoredBox)` 至少匹配 2 个。用 predicate 锁定 StartupGate
/// 自己挂的那个，避免 Scaffold 干扰断言。
Finder _findPeachPlaceholder() => find.byWidgetPredicate(
  (w) => w is ColoredBox && w.color == const Color(0xFFFDD3BC),
);

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
///
/// 状态化（`throwsOnInit` 可变）：让 Retry 测试在第二次 init 时改为成功——
/// provider override 只在 ProviderContainer 首次创建时跑一次，覆写 callback
/// 重新跑需要 dispose container；简单做法是让 fake 内部状态可变。
class FakeNotificationBootstrap implements NotificationBootstrap {
  FakeNotificationBootstrap({this._throwsOnInit});

  Object? _throwsOnInit;
  int initCalls = 0;

  set throwsOnInit(Object? value) => _throwsOnInit = value;

  @override
  Future<void> init() async {
    initCalls++;
    if (_throwsOnInit != null) throw _throwsOnInit!;
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
  // StartupGate 在 app 阶段直接渲染 `widget.child`（生产环境是
  // MaterialApp.router），FatalScreen 内的 DefaultErrorFallback 调
  // Theme.of + FilledButton（需 MaterialLocalizations）。测试用一个
  // MaterialApp 包住 StartupGate，提供 Directionality / Theme /
  // MaterialLocalizations / MediaQuery，模拟生产祖先。
  Widget wrap(StartupGate gate) => MaterialApp(home: gate);

  testWidgets('initial phase shows peach placeholder (native-only)', (
    tester,
  ) async {
    var onReadyCalls = 0;
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
        child: wrap(
          StartupGate(
            onAppReady: () => onReadyCalls++,
            child: const Text('APP'),
          ),
        ),
      ),
    );
    await tester.pump();
    // splash 阶段：渲染 #FDD3BC ColoredBox（Flutter 侧占位，native splash
    // 在系统层独显）。
    expect(_findPeachPlaceholder(), findsOneWidget);
    expect(find.text('APP'), findsNothing);
    expect(find.byType(FatalScreen), findsNothing);
    expect(onReadyCalls, 0, reason: 'must not fire before init complete');

    // 清理：推进时钟越过 10s orchestrator + 800ms MinDisplayTimer，
    // 否则 flutter_test 会判 "Timer still pending" 失败。
    await tester.pump(const Duration(seconds: 10));
    expect(onReadyCalls, 1, reason: 'splash→app 切换后 fire onAppReady 一次');
  });

  testWidgets('does not transition before 800ms even if init is instant', (
    tester,
  ) async {
    var onReadyCalls = 0;
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
        child: wrap(
          StartupGate(
            onAppReady: () => onReadyCalls++,
            child: const Text('APP'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 799));
    expect(
      _findPeachPlaceholder(),
      findsOneWidget,
      reason: 'min display time not yet met',
    );
    expect(find.text('APP'), findsNothing);
    expect(onReadyCalls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    // setState 触发重建 → 切到 app 阶段。Flush 一帧让 widget 树重建。
    await tester.pump();
    expect(find.text('APP'), findsOneWidget);
    expect(_findPeachPlaceholder(), findsNothing);
    // postFrameCallback 在 splash→app 切换的下一帧 fire onAppReady
    await tester.pump();
    expect(onReadyCalls, 1);
  });

  testWidgets(
    'NotificationBootstrap failure → FatalScreen (Tier 1 fatal) + fire onAppReady',
    (tester) async {
      var onReadyCalls = 0;
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
          child: wrap(
            StartupGate(
              onAppReady: () => onReadyCalls++,
              child: const Text('APP'),
            ),
          ),
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
      // 再 pump 一帧让 setState(_initError=...) 触发的重建完成 + postFrameCallback fire
      await tester.pump();
      expect(find.byType(FatalScreen), findsOneWidget);
      expect(find.text('APP'), findsNothing);
      expect(onReadyCalls, 1, reason: 'fatal 路径也要 fire onAppReady 退出 native');

      // 清理：bootstrap 抛错在 orchestrator 之前，10s timer 不会创建；
      // 但 800ms MinDisplayTimer 已 schedule 且 Future.wait reject 后无人
      // cancel，必须推进时钟触发它，否则 "Timer still pending"。
      await tester.pump(const Duration(milliseconds: 800));
    },
  );

  testWidgets(
    'ConnectionOrchestrator failure → app shell mounts (Tier 2 soft-fail) + fire onAppReady',
    (tester) async {
      var onReadyCalls = 0;
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
          child: wrap(
            StartupGate(
              onAppReady: () => onReadyCalls++,
              child: const Text('APP'),
            ),
          ),
        ),
      );
      await tester.pump();
      // orchestrator Duration.zero 抛错 → Tier-2 catch → connectionInitStateProvider
      // 写错误（in-app banner 用，本测试不断言）。_runInitialization 正常完成。
      // 推进 800ms 让 MinDisplayTimer 到期 → Future.wait 完成 → 切 app 阶段。
      // （不能用 pumpAndSettle：Tier-2 catch 不调度帧，pumpAndSettle 会在
      //  800ms 之前因 "no scheduled frame" 提前停止，导致 app 阶段永不 mount。）
      await tester.pump(const Duration(milliseconds: 800));
      // Flush setState(_phase=app) 触发的重建 + postFrameCallback
      await tester.pump();
      expect(find.text('APP'), findsOneWidget);
      expect(find.byType(FatalScreen), findsNothing);
      expect(_findPeachPlaceholder(), findsNothing);
      expect(onReadyCalls, 1, reason: 'soft-fail 也是终态，必须 fire onAppReady');
    },
  );

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

      var onReadyCalls = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: wrap(
            StartupGate(
              onAppReady: () => onReadyCalls++,
              child: const Text('APP'),
            ),
          ),
        ),
      );
      await tester.pump();
      // 推进 800ms 让 MinDisplayTimer 到期 → Future.wait settle → _runStartup
      // 完成 → 切到 app 阶段。同时 orchestrator 抛错触发 Tier-2 catch。
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();

      final state = container.read(connectionInitStateProvider);
      expect(state, isNotNull);
      expect(
        state!.hasError,
        isTrue,
        reason: 'Tier 2 catch should write AsyncValue.error',
      );
      expect(state.error, isA<StateError>());
      expect(onReadyCalls, 1);
    },
  );

  testWidgets(
    'FatalScreen Retry re-runs startup and fires onAppReady again (idempotent guard resets)',
    (tester) async {
      var onReadyCalls = 0;
      // 单例状态化 fake：第一次 init 抛错 → 进 FatalScreen；Retry 时把
      // throwsOnInit 清空 → 第二次 init 成功 → 切 app 阶段。
      final bootstrap = FakeNotificationBootstrap(
        throwsOnInit: StateError('first try boom'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationBootstrapProvider.overrideWith((ref) => bootstrap),
            connectionOrchestratorProvider.overrideWith(
              (ref) => FakeOrchestrator(completesAfter: Duration.zero),
            ),
          ],
          child: wrap(
            StartupGate(
              onAppReady: () => onReadyCalls++,
              child: const Text('APP'),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(); // flush setState(_initError) + postFrameCallback
      expect(find.byType(FatalScreen), findsOneWidget);
      expect(onReadyCalls, 1, reason: 'first fatal 触发 onAppReady');

      // 触发 Retry 前：把 fake 切到成功模式（模拟"用户修了底层 bug 再试"）。
      // _retrying 守卫只挡 200ms 内连点；外部测试一次 tap 不会撞。
      bootstrap.throwsOnInit = null;

      // FatalScreen 里 DefaultErrorFallback 渲染一个 FilledButton（带
      // onRetry closure）。tap 它触发 StartupGate.onRetry → setState
      // 重置 + _runStartup 重跑。
      await tester.tap(find.byType(FilledButton).first);
      // 推进 800ms 让 MinDisplayTimer 到期 + flush setState + postFrameCallback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester
          .pump(); // flush setState(_phase=app) + postFrameCallback fire
      expect(find.text('APP'), findsOneWidget);
      expect(find.byType(FatalScreen), findsNothing);
      expect(
        onReadyCalls,
        2,
        reason: 'Retry 后必须 fire onAppReady 第二次（idempotent 守卫允许）',
      );
    },
  );
}
