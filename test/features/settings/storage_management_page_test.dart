import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/storage_info.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/storage_management_page.dart';

void main() {
  group('StorageManagementPage', () {
    testWidgets('renders loading state when data is pending', (tester) async {
      // Use a never-completing future for loading state
      final completer = Completer<StorageInfo>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageInfoProvider.overrideWith((ref) => completer.future),
          ],
          child: const MaterialApp(home: StorageManagementPage()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete(const StorageInfo(databaseSizeBytes: 0));
    });

    testWidgets('renders storage info when data loads successfully', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageInfoProvider.overrideWith(
              (ref) async => const StorageInfo(
                databaseSizeBytes: 1024 * 100,
                messageCount: 42,
              ),
            ),
          ],
          child: const MaterialApp(home: StorageManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('100.0 KB'), findsOneWidget);
      expect(find.text('42 条'), findsOneWidget);
      expect(find.text('自动清理'), findsOneWidget);
    });

    testWidgets('renders error state when data fetch fails', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageInfoProvider.overrideWith(
              (ref) async => throw Exception('Database locked'),
            ),
          ],
          child: const MaterialApp(home: StorageManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('无法加载存储信息'), findsOneWidget);
      expect(find.textContaining('Database locked'), findsOneWidget);
    });

    testWidgets('renders app bar with back button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageInfoProvider.overrideWith(
              (ref) async =>
                  const StorageInfo(databaseSizeBytes: 0, messageCount: 0),
            ),
          ],
          child: const MaterialApp(home: StorageManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('存储管理'), findsOneWidget);
    });

    testWidgets('shows explanation footer about local storage', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageInfoProvider.overrideWith(
              (ref) async =>
                  const StorageInfo(databaseSizeBytes: 500, messageCount: 10),
            ),
          ],
          child: const MaterialApp(home: StorageManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('消息记录存储在设备本地'), findsOneWidget);
    });
  });
}
