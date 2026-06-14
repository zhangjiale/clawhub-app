import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:claw_hub/main.dart';

/// On-device smoke test.
///
/// Requires a connected device or emulator.
/// Run with: flutter test integration_test/
///
/// Verifies the app launches and renders on real hardware
/// — catches platform-specific issues that headless tests miss.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches on device without crash', (tester) async {
    await tester.pumpWidget(const ClawHubApp());
    // Allow the app one frame to render — on device, pumpAndSettle
    // can hang if there are infinite animations, so use single pump.
    await tester.pump();

    // App should not crash on first frame.
    expect(tester.takeException(), isNull);
  });
}
