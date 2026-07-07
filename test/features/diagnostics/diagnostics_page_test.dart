import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/features/diagnostics/diagnostics_page.dart';

void main() {
  late ApiLogStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({'diagnostics_warning_shown': true});
    store = ApiLogStore();
  });

  Widget buildApp() {
    return ProviderScope(
      overrides: [apiLogStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(home: DiagnosticsPage()),
    );
  }

  testWidgets('renders entries from the store (newest first)', (tester) async {
    store.logStateChange(
      instanceId: 'i1',
      state: 'connected',
      message: 'first',
    );
    store.logRequest(
      instanceId: 'i1',
      requestId: 'r1',
      method: 'chat.send',
      byteSize: 10,
      rawJson: '{}',
    );
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('chat.send'), findsOneWidget);
    expect(find.textContaining('first'), findsOneWidget);
  });

  testWidgets('tap a row expands payload preview', (tester) async {
    store.logRequest(
      instanceId: 'i1',
      requestId: 'r1',
      method: 'connect',
      byteSize: 40,
      rawJson: '{"method":"connect","params":{"auth":{"token":"secret"}}}',
    );
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    // Payload collapsed by default — secret not visible.
    expect(find.textContaining('secret'), findsNothing);
    // Tap the row to reveal.
    await tester.tap(find.textContaining('connect'));
    await tester.pumpAndSettle();
    // Redacted preview now visible.
    expect(find.textContaining('<redacted>'), findsOneWidget);
  });

  testWidgets('clear button wipes the list', (tester) async {
    store.logStateChange(
      instanceId: 'i1',
      state: 'connected',
      message: 'hello',
    );
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('hello'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    // Confirm dialog
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hello'), findsNothing);
  });
}
