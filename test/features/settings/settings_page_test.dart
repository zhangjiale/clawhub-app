import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/storage_info.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';
import 'package:claw_hub/features/settings/settings_page.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/viewmodels/settings_view_model.dart';

class MockSettingsRepo extends Mock implements ISettingsRepo {}

void main() {
  setUpAll(() {
    registerFallbackValue(UserPreferences.defaults());
  });

  late MockSettingsRepo repo;
  late SettingsViewModel vm;

  setUp(() async {
    repo = MockSettingsRepo();
    when(
      () => repo.getPreferences(),
    ).thenAnswer((_) async => UserPreferences.defaults());
    when(() => repo.updatePreferences(any())).thenAnswer((_) async {});
    when(() => repo.watchPreferences()).thenAnswer((_) => const Stream.empty());

    vm = SettingsViewModel(repo: repo);
    await vm.init();
  });

  /// Default test harness: returns 2.0 MB so the cache row shows a
  /// realistic, non-empty label. Override [storageSize] for variation.
  Widget buildTestWidget({StorageInfo? storageSize}) {
    return ProviderScope(
      overrides: [
        settingsViewModelProvider.overrideWith((ref) => vm),
        storageInfoProvider.overrideWith(
          (ref) async =>
              storageSize ??
              const StorageInfo(databaseSizeBytes: 1024 * 1024 * 2),
        ),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  group('SettingsPage', () {
    testWidgets('renders all 6 setting rows', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('通知设置'), findsOneWidget);
      expect(find.text('免打扰时段'), findsOneWidget);
      expect(find.text('生物识别锁'), findsOneWidget);
      expect(find.text('本地缓存'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget); // V2 section title uppercase
    });

    testWidgets('shows notification status based on ViewModel state', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Default: notifications enabled
      expect(find.text('已开启'), findsOneWidget);
    });

    testWidgets('shows DND time range when enabled', (tester) async {
      // Update state: DND enabled with specific time
      vm = SettingsViewModel(repo: repo);
      await vm.init();
      await vm.setDndEnabled(true);
      await vm.setDndTimeRange(
        startHour: 23,
        startMinute: 0,
        endHour: 7,
        endMinute: 0,
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('23:00 — 07:00'), findsOneWidget);
    });

    testWidgets('shows DND off label when disabled', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // "未开启" appears for both DND and biometric; both should be present
      expect(find.text('未开启'), findsNWidgets(2));
    });

    testWidgets('renders footer', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // V2: SettingsPage has more sections, so footer may be off-screen —
      // scroll until visible.
      await tester.scrollUntilVisible(
        find.textContaining('Powered by OpenClaw Gateway Protocol'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.textContaining('Powered by OpenClaw Gateway Protocol'),
        findsOneWidget,
      );
    });

    testWidgets('renders app bar with back button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Cache size row — must reflect storageInfoProvider (regression #7)
    // -------------------------------------------------------------------------
    group('cache size row', () {
      testWidgets('shows human-readable size from storageInfoProvider', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(
            storageSize: const StorageInfo(
              databaseSizeBytes: 1024 * 1024 * 12 + 1024 * 400, // 12.4 MB
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('12.4 MB'), findsOneWidget);
      });

      testWidgets('formats small sizes in KB', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            storageSize: const StorageInfo(databaseSizeBytes: 1024 * 256),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('256.0 KB'), findsOneWidget);
      });
    });
  });
}
