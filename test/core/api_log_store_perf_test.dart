import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/api_log_store.dart';

void main() {
  test(
    'logRequest on a 5MB frame completes in < 5ms (truncate-then-parse holds)',
    () {
      final store = ApiLogStore();
      addTearDown(store.dispose);

      // 5MB JSON: a chat.send with a huge base64-ish attachment payload.
      final big =
          '{"method":"chat.send","params":{"message":"hi","attachments":[{"content":"${'A' * 5_000_000}"}]}}';
      final payloadSize = big.length;

      // Warm-up call: lets the VM JIT-compile the regex/uuid paths so the
      // Stopwatch measurement reflects the algorithm's steady-state cost
      // (O(threshold) via truncate-then-parse), not one-off compilation overhead.
      store.logRequest(
        instanceId: 'warmup',
        requestId: 'warmup',
        method: 'chat.send',
        byteSize: payloadSize,
        rawJson: big,
      );

      final sw = Stopwatch()..start();
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'chat.send',
        byteSize: payloadSize,
        rawJson: big,
      );
      sw.stop();

      expect(
        sw.elapsedMilliseconds,
        lessThan(5),
        reason:
            'logRequest must stay O(threshold) via truncate-then-parse; '
            'full jsonDecode of a 5MB frame would blow this budget.',
      );
    },
  );
}
