import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/splash/splash_screen.dart';
import 'package:claw_hub/app/theme/tokens.dart';

void main() {
  testWidgets('renders brand image asset', (tester) async {
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    expect(find.byType(Image), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName,
      'docs/design/assets/xiahub-splash-v3.png',
    );
  });

  testWidgets('renders version text at bottom center', (tester) async {
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    expect(find.text('v0.1.0+1'), findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.text('v0.1.0+1'),
        matching: find.byType(Positioned),
      ),
    );
    expect(positioned.bottom, XiaSpacing.s8);
  });
}
