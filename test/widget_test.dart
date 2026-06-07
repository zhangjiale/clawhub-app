import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/main.dart';

void main() {
  testWidgets('App renders 3-tab navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ClawHubApp()));
    await tester.pumpAndSettle();

    // The app should render with the 3-tab navigation bar
    // (Text may appear in both AppBar title and NavBar label)
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Claws'), findsAtLeast(1));
    expect(find.text('Messages'), findsAtLeast(1));
    expect(find.text('Instances'), findsAtLeast(1));
  });
}
