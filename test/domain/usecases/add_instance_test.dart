import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/usecases/add_instance.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';

class MockInstanceRepo extends Mock implements IInstanceRepo {}
class MockGatewayClient extends Mock implements IGatewayClient {}

void main() {
  late AddInstanceUseCase useCase;
  late MockInstanceRepo instanceRepo;
  late MockGatewayClient gatewayClient;

  setUpAll(() {
    registerFallbackValue(Instance(
      id: 'fb', name: 'fb', gatewayUrl: 'wss://fb.com:18789', tokenRef: 'fb',
    ));
  });

  setUp(() {
    instanceRepo = MockInstanceRepo();
    gatewayClient = MockGatewayClient();
    useCase = AddInstanceUseCase(
      instanceRepo: instanceRepo,
      gatewayClient: gatewayClient,
    );
  });

  test('添加有效实例（连通性测试通过）', () async {
    when(() => instanceRepo.nameExists('我的MacBook', excludeId: any(named: 'excludeId')))
        .thenAnswer((_) async => false);
    when(() => gatewayClient.testConnection(any()))
        .thenAnswer((_) async => true);
    when(() => instanceRepo.save(any()))
        .thenAnswer((inv) async => inv.positionalArguments[0] as Instance);

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
    when(() => instanceRepo.nameExists('重复名称', excludeId: any(named: 'excludeId')))
        .thenAnswer((_) async => true);

    expect(
      () => useCase.execute(
        name: '重复名称',
        gatewayUrl: 'wss://test.com:18789',
        token: 'token',
      ),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message, 'message', contains('已存在'),
      )),
    );
  });

  test('连通性测试失败应标记为离线', () async {
    when(() => instanceRepo.nameExists('离线实例', excludeId: any(named: 'excludeId')))
        .thenAnswer((_) async => false);
    when(() => gatewayClient.testConnection(any()))
        .thenAnswer((_) async => false);
    when(() => instanceRepo.save(any()))
        .thenAnswer((inv) async => inv.positionalArguments[0] as Instance);

    final result = await useCase.execute(
      name: '离线实例',
      gatewayUrl: 'ws://192.168.1.100:18789',
      token: 'token',
    );

    expect(result.healthStatus, HealthStatus.offline);
    verify(() => instanceRepo.save(any())).called(1);
  });
}
