import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

      // A new entry triggers a re-emission, now throttled to 100ms to avoid
      // rebuilding the diagnostics ListView on every single log entry.
      store.logStateChange(
        instanceId: 'i1',
        state: 'connected',
        message: 'third',
      );
      await Future.delayed(const Duration(milliseconds: 110));
      final updated = await container.read(diagnosticsEntriesProvider.future);
      expect(updated.first.message, 'third');

      sub.close();
    },
  );

  test(
    'diagnosticsEntriesProvider throttles rapid entries to one emission',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final store = container.read(apiLogStoreProvider);
      final keepAlive = container.listen(diagnosticsEntriesProvider, (_, _) {});
      await container.read(diagnosticsEntriesProvider.future); // seed

      var emissionCount = 0;
      final lastEmission = container.listen(diagnosticsEntriesProvider, (
        prev,
        next,
      ) {
        if (next.hasValue) emissionCount++;
      });

      store.logStateChange(instanceId: 'i1', state: 's1', message: 'a');
      store.logStateChange(instanceId: 'i1', state: 's2', message: 'b');
      store.logStateChange(instanceId: 'i1', state: 's3', message: 'c');

      // Events arrive immediately, but throttle window is still open.
      await Future.delayed(Duration.zero);
      expect(emissionCount, 0, reason: 'rapid entries should be batched');

      await Future.delayed(const Duration(milliseconds: 110));
      expect(emissionCount, 1, reason: 'batched entries emit once');
      final updated = await container.read(diagnosticsEntriesProvider.future);
      expect(updated.first.message, 'c');

      lastEmission.close();
      keepAlive.close();
    },
  );

  test(
    'diagnosticsWarningShownProvider.markShown persists acknowledgement via the provider (ARB #3)',
    () async {
      // This file runs in its own isolate, so the SharedPreferences singleton is
      // fresh here - flag absent -> not yet acknowledged.
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(diagnosticsWarningShownProvider.future),
        isFalse,
        reason: 'flag absent initially',
      );

      // The fix: the page calls markShown() instead of prefs.setBool directly,
      // so the key lives in one place (the notifier).
      await container
          .read(diagnosticsWarningShownProvider.notifier)
          .markShown();

      // Persisted with the centralized key.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('diagnostics_warning_shown'), isTrue);

      // Provider state updated in-place (no invalidate needed).
      expect(container.read(diagnosticsWarningShownProvider).value, isTrue);
    },
  );
}
