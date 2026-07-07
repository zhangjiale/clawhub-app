import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/core/i_api_logger.dart';

void main() {
  late ApiLogStore store;

  setUp(() => store = ApiLogStore(maxEntries: 3));

  tearDown(() => store.dispose());

  group('ApiLogStore', () {
    test('snapshot returns unmodifiable view', () {
      store.logStateChange(instanceId: 'i', state: 'connected', message: 'ok');
      final snap = store.snapshot();
      expect(snap.length, 1);
      expect(
        () => snap.add(
          ApiLogEntry(
            id: 'x',
            timestampMs: 0,
            instanceId: 'i',
            kind: ApiLogKind.state,
            message: 'x',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('FIFO eviction at capacity', () {
      for (var i = 0; i < 5; i++) {
        store.logStateChange(instanceId: 'i', state: 's$i', message: 'm$i');
      }
      final snap = store.snapshot();
      expect(snap.length, 3); // capped
      // oldest evicted → first kept is s2
      expect(snap.first.state, 's2');
      expect(snap.last.state, 's4');
    });

    test('res matches req → durationMs computed and non-negative', () {
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'chat.send',
        byteSize: 10,
        rawJson: '{"method":"chat.send","params":{"message":"hi"}}',
      );
      store.logResponse(
        instanceId: 'i',
        requestId: 'r1',
        ok: true,
        byteSize: 20,
        rawJson: '{"ok":true,"payload":{}}',
      );
      final snap = store.snapshot();
      final res = snap.lastWhere((e) => e.kind == ApiLogKind.res);
      expect(res.durationMs, isNotNull);
      expect(res.durationMs! >= 0, isTrue);
    });

    test('res with no matching req → durationMs null (does not throw)', () {
      store.logResponse(
        instanceId: 'i',
        requestId: 'orphan',
        ok: false,
        errorCode: 'CONNECTION_LOST',
        byteSize: 5,
        rawJson: '{"ok":false}',
      );
      final res = store.snapshot().single;
      expect(res.durationMs, isNull);
      expect(res.ok, isFalse);
      expect(res.errorCode, 'CONNECTION_LOST');
    });

    test('request payload is redacted', () {
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'connect',
        byteSize: 40,
        rawJson: '{"method":"connect","params":{"auth":{"token":"secret"}}}',
      );
      final req = store.snapshot().single;
      expect(req.payloadPreview, contains('<redacted>'));
      expect(req.payloadPreview, isNot(contains('secret')));
    });

    test('onEntry stream emits on each add', () async {
      final received = <ApiLogKind>[];
      final sub = store.onEntry.listen((e) => received.add(e.kind));
      store.logStateChange(instanceId: 'i', state: 'connected', message: 'ok');
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'm',
        byteSize: 1,
        rawJson: '{}',
      );
      await Future.delayed(Duration.zero);
      expect(received, [ApiLogKind.state, ApiLogKind.req]);
      await sub.cancel();
    });

    test('clear wipes entries and pending map', () {
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'm',
        byteSize: 1,
        rawJson: '{}',
      );
      store.clear();
      expect(store.snapshot(), isEmpty);
      // after clear, a res for r1 has no durationMs
      store.logResponse(
        instanceId: 'i',
        requestId: 'r1',
        ok: true,
        byteSize: 1,
        rawJson: '{}',
      );
      expect(store.snapshot().single.durationMs, isNull);
    });

    test('orphan sweep evicts stale pending reqs and emits a state log', () {
      // Injectable clock: add a batch of reqs, advance the clock past the TTL so
      // they become "stale", then one more logRequest trips the sweep threshold
      // and _maybeSweep evicts the stale batch + emits a state log. Without the
      // injectable clock the test couldn't advance time past the 30s TTL.
      var now = 1000000;
      final sweepStore = ApiLogStore(maxEntries: 500, clock: () => now);
      for (var i = 0; i < 201; i++) {
        sweepStore.logRequest(
          instanceId: 'i',
          requestId: 'req-$i',
          method: 'm',
          byteSize: 1,
          rawJson: '{}',
        );
      }
      // All 201 pending reqs are now stale (>30s old).
      now += ApiLogStore.pendingReqTtlMs + 1;
      // This logRequest pushes length > 200 and triggers the sweep.
      sweepStore.logRequest(
        instanceId: 'i',
        requestId: 'trigger',
        method: 'm',
        byteSize: 1,
        rawJson: '{}',
      );
      final hasEvictLog = sweepStore.snapshot().any(
        (e) =>
            e.kind == ApiLogKind.state &&
            (e.message?.contains('evicted') ?? false),
      );
      expect(hasEvictLog, isTrue);
    });

    test('throwing redactor input does not propagate', () {
      // redactAndTruncate never throws, but guard the contract anyway.
      expect(
        () => store.logRequest(
          instanceId: 'i',
          requestId: 'r1',
          method: 'm',
          byteSize: 1,
          rawJson: 'not json {{{',
        ),
        returnsNormally,
      );
      expect(store.snapshot().length, 1);
    });
  });
}
