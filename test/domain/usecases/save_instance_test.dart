import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/usecases/save_instance.dart';
import 'package:claw_hub/domain/usecases/gateway_change_resolution.dart';
import 'package:claw_hub/domain/usecases/gateway_change_exceptions.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';

class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockGatewayClient extends Mock implements IGatewayClient {}

class MockAgentRepo extends Mock implements IAgentRepo {}

Agent _fakeAgent(String remoteId, {int? removedAt, int? hiddenAt}) => Agent(
  localId: 'local-$remoteId',
  remoteId: remoteId,
  instanceId: 'inst-1',
  name: 'Agent $remoteId',
  createdAt: 1700000000,
  removedAt: removedAt,
  hiddenAt: hiddenAt,
);

void main() {
  late SaveInstanceUseCase useCase;
  late MockInstanceRepo instanceRepo;
  late MockGatewayClient gatewayClient;
  late MockAgentRepo agentRepo;

  setUpAll(() {
    registerFallbackValue(
      Instance(
        id: 'fb',
        name: 'fb',
        gatewayUrl: 'wss://fb.com:18789',
        tokenRef: 'fb',
      ),
    );
    registerFallbackValue(<QuickCommand>[]);
  });

  setUp(() {
    instanceRepo = MockInstanceRepo();
    gatewayClient = MockGatewayClient();
    agentRepo = MockAgentRepo();
    useCase = SaveInstanceUseCase(
      instanceRepo: instanceRepo,
      agentRepo: agentRepo,
      gatewayClient: gatewayClient,
    );

    // 默认：本地无 agents（不触发 GatewayChangeRequiredException）
    when(
      () => agentRepo.getByInstanceId(any()),
    ).thenAnswer((_) async => <Agent>[]);
    when(
      () => agentRepo.getAllByInstanceId(any()),
    ).thenAnswer((_) async => <Agent>[]);
    when(() => agentRepo.deleteByInstanceId(any())).thenAnswer((_) async {});
  });

  group('Create', () {
    test('添加有效实例（连通性测试通过）', () async {
      when(
        () => instanceRepo.nameExists(
          '我的MacBook',
          excludeId: any(named: 'excludeId'),
        ),
      ).thenAnswer((_) async => false);
      when(
        () => gatewayClient.testConnection(any()),
      ).thenAnswer((_) async => true);
      when(
        () => instanceRepo.save(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Instance);

      final result = await useCase.execute(
        name: '我的MacBook',
        gatewayUrl: 'wss://my.example.com:18789',
        token: 'test-token-123',
      );

      expect(result.name, '我的MacBook');
      expect(result.healthStatus, HealthStatus.online);
      expect(result.isLocalNetwork, isFalse);
      verify(() => gatewayClient.testConnection(any())).called(1);
      verify(() => instanceRepo.save(any())).called(1);
    });

    test('名称为空应失败', () async {
      expect(
        () => useCase.execute(
          name: '',
          gatewayUrl: 'wss://test.com:18789',
          token: 'token',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('名称重复应失败', () async {
      when(
        () =>
            instanceRepo.nameExists('重复名称', excludeId: any(named: 'excludeId')),
      ).thenAnswer((_) async => true);

      expect(
        () => useCase.execute(
          name: '重复名称',
          gatewayUrl: 'wss://test.com:18789',
          token: 'token',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('已存在'),
          ),
        ),
      );
    });

    test('连通性测试失败应标记为离线', () async {
      when(
        () =>
            instanceRepo.nameExists('离线实例', excludeId: any(named: 'excludeId')),
      ).thenAnswer((_) async => false);
      when(
        () => gatewayClient.testConnection(any()),
      ).thenAnswer((_) async => false);
      when(
        () => instanceRepo.save(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Instance);

      final result = await useCase.execute(
        name: '离线实例',
        gatewayUrl: 'ws://192.168.1.100:18789',
        token: 'token',
      );

      expect(result.healthStatus, HealthStatus.offline);
      verify(() => instanceRepo.save(any())).called(1);
    });
  });

  group('Update', () {
    final existingInstance = Instance(
      id: 'inst-1',
      name: '原名称',
      gatewayUrl: 'wss://old.example.com:18789',
      tokenRef: 'old-token',
    );

    test('编辑名称保持相同时跳过唯一性检查', () async {
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenAnswer((_) async => existingInstance);
      // nameExists should NOT be called because name didn't change
      when(
        () => gatewayClient.testConnection(any()),
      ).thenAnswer((_) async => true);
      when(
        () => instanceRepo.save(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Instance);

      final result = await useCase.execute(
        name: '原名称',
        gatewayUrl: 'wss://new.example.com:18789',
        token: 'new-token',
        instanceId: 'inst-1',
      );

      expect(result.name, '原名称');
      verify(() => instanceRepo.save(any())).called(1);
      verifyNever(
        () =>
            instanceRepo.nameExists(any(), excludeId: any(named: 'excludeId')),
      );
    });

    test('编辑修改名称时检查唯一性（排除自身）', () async {
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenAnswer((_) async => existingInstance);
      when(
        () => instanceRepo.nameExists('新名称', excludeId: 'inst-1'),
      ).thenAnswer((_) async => false);
      when(
        () => gatewayClient.testConnection(any()),
      ).thenAnswer((_) async => true);
      when(
        () => instanceRepo.save(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Instance);

      final result = await useCase.execute(
        name: '新名称',
        gatewayUrl: 'wss://test.com:18789',
        token: 'token',
        instanceId: 'inst-1',
      );

      expect(result.name, '新名称');
      verify(
        () => instanceRepo.nameExists('新名称', excludeId: 'inst-1'),
      ).called(1);
    });

    test('编辑时新名称被其他实例占用应失败', () async {
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenAnswer((_) async => existingInstance);
      when(
        () => instanceRepo.nameExists('已被占用', excludeId: 'inst-1'),
      ).thenAnswer((_) async => true);

      expect(
        () => useCase.execute(
          name: '已被占用',
          gatewayUrl: 'wss://test.com:18789',
          token: 'token',
          instanceId: 'inst-1',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('已存在'),
          ),
        ),
      );
    });

    test('编辑不存在的实例应失败', () async {
      when(
        () => instanceRepo.getById('nonexistent'),
      ).thenAnswer((_) async => null);

      expect(
        () => useCase.execute(
          name: '某名称',
          gatewayUrl: 'wss://test.com:18789',
          token: 'token',
          instanceId: 'nonexistent',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Gateway change detection (host)', () {
    final existingInstance = Instance(
      id: 'inst-1',
      name: '原名称',
      gatewayUrl: 'wss://old.example.com:18789',
      tokenRef: 'old-token',
    );

    setUp(() {
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenAnswer((_) async => existingInstance);
      when(
        () => instanceRepo.save(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Instance);
      when(
        () => gatewayClient.testConnection(any()),
      ).thenAnswer((_) async => true);
    });

    test('host 不变（仅改端口/token）不查 agentRepo, 不抛异常', () async {
      // 旧 wss://old.example.com:18789 → 新 wss://old.example.com:9090
      await useCase.execute(
        name: '原名称',
        gatewayUrl: 'wss://old.example.com:9090',
        token: 'new-token',
        instanceId: 'inst-1',
      );
      verifyNever(() => agentRepo.getByInstanceId(any()));
      verifyNever(() => agentRepo.getAllByInstanceId(any()));
      verifyNever(() => agentRepo.deleteByInstanceId(any()));
      verify(() => instanceRepo.save(any())).called(1);
    });

    test('host 变化 + 本地 agents 为空 → 不抛, 正常 save', () async {
      when(
        () => agentRepo.getAllByInstanceId('inst-1'),
      ).thenAnswer((_) async => <Agent>[]);
      await useCase.execute(
        name: '原名称',
        gatewayUrl: 'wss://new.example.com:18789',
        token: 'token',
        instanceId: 'inst-1',
      );
      verify(() => agentRepo.getAllByInstanceId('inst-1')).called(1);
      verifyNever(() => agentRepo.getByInstanceId(any()));
      verifyNever(() => agentRepo.deleteByInstanceId(any()));
      verify(() => instanceRepo.save(any())).called(1);
    });

    test(
      'host 变化 + 本地 agents 非空 + onGatewayChange=null → 抛 GatewayChangeRequiredException',
      () async {
        when(() => agentRepo.getAllByInstanceId('inst-1')).thenAnswer(
          (_) async => [_fakeAgent('a'), _fakeAgent('b'), _fakeAgent('c')],
        );

        expect(
          () => useCase.execute(
            name: '原名称',
            gatewayUrl: 'wss://new.example.com:18789',
            token: 'token',
            instanceId: 'inst-1',
          ),
          throwsA(
            isA<GatewayChangeRequiredException>().having(
              (e) => e.localAgentCount,
              'localAgentCount',
              3,
            ),
          ),
        );
      },
    );

    test(
      'host 变化 + onGatewayChange=null + 本地非空 → save / testConnection / deleteByInstanceId 都未到达',
      () async {
        when(
          () => agentRepo.getAllByInstanceId('inst-1'),
        ).thenAnswer((_) async => [_fakeAgent('a')]);

        await expectLater(
          () => useCase.execute(
            name: '原名称',
            gatewayUrl: 'wss://new.example.com:18789',
            token: 'token',
            instanceId: 'inst-1',
          ),
          throwsA(isA<GatewayChangeRequiredException>()),
        );

        verifyNever(() => gatewayClient.testConnection(any()));
        verifyNever(() => agentRepo.deleteByInstanceId(any()));
        verifyNever(() => instanceRepo.save(any()));
      },
    );

    test(
      'host 变化 + 本地仅有 tombstoned agents → 仍触发 GatewayChangeRequiredException',
      () async {
        // US-021: host 切换警告必须统计全部本地 agent（含 tombstoned），否则用户
        // 可能在不知情的情况下清除仍有历史消息的数据。
        when(() => agentRepo.getAllByInstanceId('inst-1')).thenAnswer(
          (_) async => [
            _fakeAgent('a', removedAt: DateTime.now().millisecondsSinceEpoch),
          ],
        );
        // 默认列表接口（过滤后）为空，模拟 bug 场景：若用 getByInstanceId 会漏判。
        when(
          () => agentRepo.getByInstanceId('inst-1'),
        ).thenAnswer((_) async => <Agent>[]);

        expect(
          () => useCase.execute(
            name: '原名称',
            gatewayUrl: 'wss://new.example.com:18789',
            token: 'token',
            instanceId: 'inst-1',
          ),
          throwsA(
            isA<GatewayChangeRequiredException>().having(
              (e) => e.localAgentCount,
              'localAgentCount',
              1,
            ),
          ),
        );
      },
    );

    test(
      'onGatewayChange=purgeLocal → testConnection 后 delete 再 save (顺序)',
      () async {
        await useCase.execute(
          name: '原名称',
          gatewayUrl: 'wss://new.example.com:18789',
          token: 'token',
          instanceId: 'inst-1',
          onGatewayChange: GatewayChangeResolution.purgeLocal,
        );

        verifyInOrder([
          () => gatewayClient.testConnection(any()),
          () => agentRepo.deleteByInstanceId('inst-1'),
          () => instanceRepo.save(any()),
        ]);
        // 关键：用户已给出 resolution → 不再查 getByInstanceId
        verifyNever(() => agentRepo.getByInstanceId(any()));
      },
    );

    test(
      'onGatewayChange=purgeLocal + testConnection 抛 → delete 未调用 (数据保护)',
      () async {
        when(
          () => gatewayClient.testConnection(any()),
        ).thenThrow(Exception('network unreachable'));

        await expectLater(
          () => useCase.execute(
            name: '原名称',
            gatewayUrl: 'wss://new.example.com:18789',
            token: 'token',
            instanceId: 'inst-1',
            onGatewayChange: GatewayChangeResolution.purgeLocal,
          ),
          throwsA(isA<Exception>()),
        );

        verifyNever(() => agentRepo.deleteByInstanceId(any()));
        verifyNever(() => instanceRepo.save(any()));
      },
    );

    test(
      'onGatewayChange=purgeLocal + deleteByInstanceId 抛 → 包装为 PurgeFailedException, save 未到达',
      () async {
        final dbError = StateError('db locked');
        when(() => agentRepo.deleteByInstanceId('inst-1')).thenThrow(dbError);

        await expectLater(
          () => useCase.execute(
            name: '原名称',
            gatewayUrl: 'wss://new.example.com:18789',
            token: 'token',
            instanceId: 'inst-1',
            onGatewayChange: GatewayChangeResolution.purgeLocal,
          ),
          throwsA(
            isA<PurgeFailedException>().having(
              (e) => e.cause,
              'cause',
              same(dbError),
            ),
          ),
        );

        verifyNever(() => instanceRepo.save(any()));
      },
    );

    test(
      'onGatewayChange=keepLocal → 不调 getByInstanceId, 不调 deleteByInstanceId, save 正常',
      () async {
        await useCase.execute(
          name: '原名称',
          gatewayUrl: 'wss://new.example.com:18789',
          token: 'token',
          instanceId: 'inst-1',
          onGatewayChange: GatewayChangeResolution.keepLocal,
        );

        verifyNever(() => agentRepo.getByInstanceId(any()));
        verifyNever(() => agentRepo.deleteByInstanceId(any()));
        verify(() => instanceRepo.save(any())).called(1);
      },
    );
  });

  group('Gateway change safety guards', () {
    final existingInstance = Instance(
      id: 'inst-1',
      name: '原名称',
      gatewayUrl: 'wss://old.example.com:18789',
      tokenRef: 'old-token',
    );

    setUp(() {
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenAnswer((_) async => existingInstance);
      when(
        () => instanceRepo.save(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Instance);
    });

    test('purgeLocal + testConnection 返回 false (新 Gateway 不可达) '
        '→ 抛 GatewayUnreachableException, delete/save 都未到达', () async {
      when(
        () => gatewayClient.testConnection(any()),
      ).thenAnswer((_) async => false);

      await expectLater(
        () => useCase.execute(
          name: '原名称',
          gatewayUrl: 'wss://new.example.com:18789',
          token: 'token',
          instanceId: 'inst-1',
          onGatewayChange: GatewayChangeResolution.purgeLocal,
        ),
        throwsA(isA<GatewayUnreachableException>()),
      );

      verifyNever(() => agentRepo.deleteByInstanceId(any()));
      verifyNever(() => instanceRepo.save(any()));
    });

    test(
      'purgeLocal + host 未变化 (调用方传错 resolution) → 不 delete, 正常 save',
      () async {
        when(
          () => gatewayClient.testConnection(any()),
        ).thenAnswer((_) async => true);

        await useCase.execute(
          name: '原名称',
          gatewayUrl: 'wss://old.example.com:9090', // 仅端口变化
          token: 'new-token',
          instanceId: 'inst-1',
          onGatewayChange: GatewayChangeResolution.purgeLocal,
        );

        verifyNever(() => agentRepo.deleteByInstanceId(any()));
        verify(() => instanceRepo.save(any())).called(1);
      },
    );

    test(
      'keepLocal + testConnection 返回 false → 不 purge, 正常 save (离线只是网络抖动)',
      () async {
        when(
          () => gatewayClient.testConnection(any()),
        ).thenAnswer((_) async => false);

        await useCase.execute(
          name: '原名称',
          gatewayUrl: 'wss://new.example.com:18789',
          token: 'token',
          instanceId: 'inst-1',
          onGatewayChange: GatewayChangeResolution.keepLocal,
        );

        verifyNever(() => agentRepo.deleteByInstanceId(any()));
        verify(() => instanceRepo.save(any())).called(1);
      },
    );
  });
}
