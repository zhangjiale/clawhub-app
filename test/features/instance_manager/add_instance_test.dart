import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/instance_manager/add_instance_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/usecases/gateway_change_exceptions.dart';
import 'package:claw_hub/domain/usecases/gateway_change_resolution.dart';
import 'package:claw_hub/domain/usecases/save_instance.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 永不完成的 InstanceRepo — 用来测试 `_isLoaded` 加载未完成时的 UI 状态。
class _PendingInstanceRepo extends InMemoryInstanceRepo {
  @override
  Future<Instance?> getById(String id) {
    return Completer<Instance?>().future; // 永不完成
  }
}

/// getById 返回 null 的 InstanceRepo —— 模拟"在另一会话中已被删除"。
class _MissingInstanceRepo extends InMemoryInstanceRepo {
  @override
  Future<Instance?> getById(String id) async => null;
}

/// 已有实例的 InstanceRepo — 编辑模式下立即填充表单。
class _PrefilledInstanceRepo extends InMemoryInstanceRepo {
  _PrefilledInstanceRepo(Instance existing) {
    save(existing);
  }
}

/// 可脚本化的 fake UseCase — 按调用次序返回不同行为，
/// 便于精确控制 GatewayChangeRequiredException / PurgeFailedException 路径。
class _ScriptedSaveUseCase implements SaveInstanceUseCase {
  final List<_Step> steps;
  final List<GatewayChangeResolution?> resolutionsSeen = [];
  int _calls = 0;

  _ScriptedSaveUseCase(this.steps);

  @override
  Future<Instance> execute({
    required String name,
    required String gatewayUrl,
    required String token,
    String? instanceId,
    GatewayChangeResolution? onGatewayChange,
  }) async {
    resolutionsSeen.add(onGatewayChange);
    final step = steps[_calls++];
    return step.apply(name, gatewayUrl, token, instanceId);
  }

  // noSuchMethod 兜底未用方法（_normalizeHost 等静态成员不走这里）
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

abstract class _Step {
  Future<Instance> apply(String name, String url, String token, String? id);
}

class _ThrowGatewayChangeRequired extends _Step {
  final int count;
  _ThrowGatewayChangeRequired(this.count);
  @override
  Future<Instance> apply(String name, String url, String token, String? id) {
    throw GatewayChangeRequiredException(localAgentCount: count);
  }
}

class _ThrowPurgeFailed extends _Step {
  @override
  Future<Instance> apply(String name, String url, String token, String? id) {
    throw const PurgeFailedException(
      message: '清除本地数据失败，请重试',
      cause: 'db error',
    );
  }
}

/// 模拟 testConnection 在 WS 握手失败时抛 SocketException 等运行时异常。
class _ThrowGenericException extends _Step {
  final Exception error;
  _ThrowGenericException(this.error);
  @override
  Future<Instance> apply(String name, String url, String token, String? id) {
    throw error;
  }
}

void main() {
  group('AddInstancePage 互斥参数', () {
    test('同时传 instanceId 与 scanResult → debug 模式抛 AssertionError', () {
      // Issue #5 防御：编辑场景不应携带扫码预填值，否则会静默改写已有实例。
      // assert 在 release 被编译掉，此测试仅在 debug（flutter test 默认）生效。
      expect(
        () => AddInstancePage(
          instanceId: 'inst-1',
          scanResult: QrScanResult(gatewayUrl: 'wss://x:18789', token: 't'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  Widget buildTestApp({String? instanceId, QrScanResult? scanResult}) {
    return ProviderScope(
      overrides: [
        instanceRepoProvider.overrideWith((ref) => InMemoryInstanceRepo()),
        gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
      ],
      child: MaterialApp(
        home: AddInstancePage(instanceId: instanceId, scanResult: scanResult),
      ),
    );
  }

  group('AddInstancePage', () {
    testWidgets('shows form fields', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Add Instance'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3)); // name, url, token
    });

    testWidgets('save button is present', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows edit title when instanceId provided', (tester) async {
      await tester.pumpWidget(buildTestApp(instanceId: 'inst-1'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Instance'), findsOneWidget);
    });

    testWidgets('shows validation error for empty name', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Instance name is required'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid URL', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'not-a-url');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid Gateway URL'), findsOneWidget);
    });

    // US-001: QR scan pre-fill tests
    testWidgets('displays scan pre-fill banner when scanResult provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          scanResult: const QrScanResult(
            name: 'Scanned Instance',
            gatewayUrl: 'wss://192.168.1.100:18789',
            token: 'scan-token',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banner should be visible
      expect(find.text('Info pre-filled from QR code'), findsOneWidget);
    });

    testWidgets('pre-fills form fields from scan result', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          scanResult: const QrScanResult(
            name: 'Scanned Instance',
            gatewayUrl: 'wss://192.168.1.100:18789',
            token: 'scan-token',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fields should be pre-filled
      expect(find.text('Scanned Instance'), findsOneWidget);
      expect(find.text('wss://192.168.1.100:18789'), findsOneWidget);
      // Token is obscured, verify it's filled by checking the field value
      final tokenField = tester.widget<TextFormField>(
        find.byType(TextFormField).at(2),
      );
      expect(tokenField.controller?.text, 'scan-token');
    });

    testWidgets('no scan banner when scanResult is null', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Info pre-filled from QR code'), findsNothing);
    });
  });

  group('AddInstancePage Gateway change flow', () {
    final existing = Instance(
      id: 'inst-1',
      name: 'Original',
      gatewayUrl: 'wss://old.example.com:18789',
      tokenRef: 'old-token',
    );

    Widget buildEdit({
      required IInstanceRepo instanceRepo,
      required SaveInstanceUseCase useCase,
    }) {
      return ProviderScope(
        overrides: [
          instanceRepoProvider.overrideWith((ref) => instanceRepo),
          gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          saveInstanceUseCaseProvider.overrideWith((ref) => useCase),
        ],
        child: MaterialApp(home: AddInstancePage(instanceId: existing.id)),
      );
    }

    testWidgets('编辑模式 _isLoaded == false 时 Save 按钮 disabled', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instanceRepoProvider.overrideWith((ref) => _PendingInstanceRepo()),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: MaterialApp(home: AddInstancePage(instanceId: 'inst-pending')),
        ),
      );
      // 不 pumpAndSettle —— _PendingInstanceRepo.getById 永不完成
      await tester.pump();

      // 强断言（Issue #8）：直接验证 PrimaryButton.onPressed == null
      final saveBtn = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(
        saveBtn.onPressed,
        isNull,
        reason: '_isLoaded==false 时 Save 按钮必须 onPressed=null',
      );
    });

    testWidgets(
      'UseCase 抛 GatewayChangeRequiredException → 弹窗 + 用户选 purgeLocal → 再次调 execute(purgeLocal)',
      (tester) async {
        // 第二次也抛错（避免走到 context.pop()，MaterialApp 无法 pop 会让 pumpAndSettle 死锁）
        // 我们只验 useCase 被以正确的 resolution 第二次调用 — 这是本测试的核心断言。
        final scriptedUseCase = _ScriptedSaveUseCase([
          _ThrowGatewayChangeRequired(3),
          _ThrowPurgeFailed(),
        ]);
        await tester.pumpWidget(
          buildEdit(
            instanceRepo: _PrefilledInstanceRepo(existing),
            useCase: scriptedUseCase,
          ),
        );
        await tester.pumpAndSettle();

        // 改 URL host
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'wss://new.example.com:18789',
        );
        await tester.tap(find.text('Save'));
        // 弹窗 transition ~150ms — 用固定 pump 而非 pumpAndSettle
        // （SnackBar 在 PurgeFailed 后会触发，自带 4s timer 会让 pumpAndSettle 超时）
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // dialog 应出现并显示 "3 个 Agent"
        expect(find.textContaining('3 个 Agent'), findsOneWidget);

        // 点 "清除并切换" — 触发第二次 execute(purgeLocal)
        await tester.tap(find.text('清除并切换'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 第二次 execute 应携带 purgeLocal
        expect(scriptedUseCase.resolutionsSeen, [
          null,
          GatewayChangeResolution.purgeLocal,
        ]);
      },
    );

    testWidgets('PurgeFailedException 显示 snackbar 且 _isSaving 恢复', (
      tester,
    ) async {
      final scriptedUseCase = _ScriptedSaveUseCase([
        _ThrowGatewayChangeRequired(2),
        _ThrowPurgeFailed(),
      ]);
      await tester.pumpWidget(
        buildEdit(
          instanceRepo: _PrefilledInstanceRepo(existing),
          useCase: scriptedUseCase,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'wss://new.example.com:18789',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // dialog 出现
      expect(find.text('清除并切换'), findsOneWidget);
      await tester.tap(find.text('清除并切换'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // SnackBar 应出现
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('清除本地数据失败'), findsOneWidget);

      // 加强断言（Issue #7）：_isSaving 必须恢复 → Save 按钮重新可点
      final saveBtn = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(
        saveBtn.onPressed,
        isNotNull,
        reason: 'PurgeFailedException 后 _isSaving 应恢复',
      );
      expect(saveBtn.isLoading, isFalse);
    });

    testWidgets('编辑模式 getById 返回 null (实例已被删除) → _isLoaded 应 true 让用户能保存', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instanceRepoProvider.overrideWith((ref) => _MissingInstanceRepo()),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: MaterialApp(home: AddInstancePage(instanceId: 'inst-missing')),
        ),
      );
      await tester.pumpAndSettle();

      // Save 按钮必须可点（onPressed != null）—— 不是永远 disabled
      final saveBtn = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(
        saveBtn.onPressed,
        isNotNull,
        reason: 'getById 返回 null 时 Save 按钮不应永久禁用',
      );
    });

    testWidgets(
      'testConnection 抛运行时异常 (DNS/握手失败) → 兜底 SnackBar + _isSaving 恢复',
      (tester) async {
        final scripted = _ScriptedSaveUseCase([
          _ThrowGenericException(Exception('SocketException: failed lookup')),
        ]);
        await tester.pumpWidget(
          buildEdit(
            instanceRepo: _PrefilledInstanceRepo(existing),
            useCase: scripted,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(1),
          'wss://new.example.com:18789',
        );
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 用户能看到错误，不是静默吞掉
        expect(find.byType(SnackBar), findsOneWidget);

        // _isSaving 必须恢复
        final saveBtn = tester.widget<PrimaryButton>(
          find.byType(PrimaryButton),
        );
        expect(saveBtn.onPressed, isNotNull);
        expect(saveBtn.isLoading, isFalse);
      },
    );

    testWidgets('GatewayUnreachableException → 兜底 SnackBar 提示', (tester) async {
      final scripted = _ScriptedSaveUseCase([
        _ThrowGenericException(const GatewayUnreachableException()),
      ]);
      await tester.pumpWidget(
        buildEdit(
          instanceRepo: _PrefilledInstanceRepo(existing),
          useCase: scripted,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'wss://unreachable.example.com:18789',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Gateway 不可达'), findsOneWidget);
    });
  });
}
