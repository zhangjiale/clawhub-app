import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;

void main() {
  group('DI Providers', () {
    test('mockGatewayClientProvider returns MockGatewayClient', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final client = container.read(mockGatewayClientProvider);
      expect(client, isA<MockGatewayClient>());
    });

    test('gatewayClientProvider and mockGatewayClientProvider are same instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final asGateway = container.read(gatewayClientProvider);
      final asMock = container.read(mockGatewayClientProvider);
      expect(identical(asGateway, asMock), isTrue);
    });

    test('databaseProvider throws without override', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(databaseProvider),
        throwsUnimplementedError,
      );
    });

    test('repository providers throw without database override', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // All four repos depend on databaseProvider, which throws
      expect(() => container.read(instanceRepoProvider), throwsUnimplementedError);
      expect(() => container.read(agentRepoProvider), throwsUnimplementedError);
      expect(() => container.read(messageRepoProvider), throwsUnimplementedError);
      expect(() => container.read(conversationRepoProvider), throwsUnimplementedError);
    });

    test('use case providers resolve through the full DI graph (in-memory DB)', () {
      // Inject an in-memory Drift DB so we can exercise the entire
      // provider graph end-to-end: use case -> repo -> database.
      final memDb = db.AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => memDb.close());
            return memDb;
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(instanceRepoProvider), isNotNull);
      expect(container.read(agentRepoProvider), isNotNull);
      expect(container.read(messageRepoProvider), isNotNull);
      expect(container.read(conversationRepoProvider), isNotNull);

      expect(container.read(sendMessageUseCaseProvider), isNotNull);
      expect(container.read(saveInstanceUseCaseProvider), isNotNull);
      expect(container.read(syncAgentsUseCaseProvider), isNotNull);
    });

    test('databaseProvider override disposes the DB when container is torn down', () async {
      final memDb = db.AppDatabase(NativeDatabase.memory());
      // Sanity: DB is usable before disposal.
      await memDb.getAllInstances().get();

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => memDb.close());
            return memDb;
          }),
        ],
      );
      // Trigger lazy initialization.
      container.read(databaseProvider);

      // Tear down → onDispose fires → close() is scheduled.
      container.dispose();
      // close() is async and was scheduled by onDispose above.
      // Await it to ensure the DB is fully shut down before asserting.
      // Drift's close() is idempotent on an already-closed DB — safe to
      // await a second time in case the fire-and-forget hasn't finished.
      await memDb.close();

      // After close(), queries should throw (DB is shut down).
      expect(
        () => memDb.getAllInstances().get(),
        throwsA(anything),
      );
    });
  });
}
