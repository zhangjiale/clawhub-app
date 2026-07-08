import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/splash/min_display_timer.dart';

void main() {
  test('does not complete before duration elapses', () {
    FakeAsync().run((async) {
      var done = false;
      MinDisplayTimer.wait(
        const Duration(milliseconds: 800),
      ).then((_) => done = true);
      async.elapse(const Duration(milliseconds: 799));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });
  });
}
