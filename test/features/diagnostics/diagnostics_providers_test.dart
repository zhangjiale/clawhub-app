import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/diagnostics/providers/diagnostics_providers.dart';

void main() {
  test(
    'diagnosticsEntriesProvider seeds with snapshot and emits newest-first',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final store = container.read(apiLogStoreProvider);
      store.logStateChange(
        instanceId: 'i1',
        state: 'connected',
        message: 'first',
      );
      store.logStateChange(
        instanceId: 'i1',
        state: 'disconnected',
        message: 'second',
      );

      final sub = container.listen(diagnosticsEntriesProvider, (_, _) {});
      // First emission = seed snapshot, reversed (newest first)
      final first = await container.read(diagnosticsEntriesProvider.future);
      expect(first.first.message, 'second'); // newest first
      expect(first.last.message, 'first');

      // A new entry triggers a re-emission. The store's broadcast controller and
      // this provider's controller are both async (sync:false), so the re-emission
      // crosses two microtask hops; pump the event queue before re-reading .future
      // (which otherwise returns the already-completed seed value immediately).
      store.logStateChange(
        instanceId: 'i1',
        state: 'connected',
        message: 'third',
      );
      await Future.delayed(Duration.zero);
      final updated = await container.read(diagnosticsEntriesProvider.future);
      expect(updated.first.message, 'third');

      sub.close();
    },
  );
}
