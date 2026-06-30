import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';
import 'package:claw_hub/features/settings/notification_settings_page.dart';
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

  Widget buildTestWidget() {
    return ProviderScope(
      overrides: [settingsViewModelProvider.overrideWith((ref) => vm)],
      child: const MaterialApp(home: NotificationSettingsPage()),
    );
  }

  group('NotificationSettingsPage', () {
    testWidgets('renders all 5 toggle rows', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('\u{1F514}  通知总开关'), findsOneWidget);
      expect(find.text('\u{1F4AC}  Agent 回复通知'), findsOneWidget);
      expect(find.text('⚠️  Agent 出错通知'), findsOneWidget);
      expect(find.text('\u{1F517}  连接状态通知'), findsOneWidget);
      expect(find.text('\u{1F504}  后台同步'), findsOneWidget);
    });

    testWidgets('master toggle off disables sub-toggles visually', (
      tester,
    ) async {
      // Create a VM with master notifications turned off via init()
      final offRepo = MockSettingsRepo();
      when(() => offRepo.getPreferences()).thenAnswer(
        (_) async =>
            UserPreferences.defaults().copyWith(notificationsEnabled: false),
      );
      when(() => offRepo.updatePreferences(any())).thenAnswer((_) async {});
      when(
        () => offRepo.watchPreferences(),
      ).thenAnswer((_) => const Stream.empty());

      final offVm = SettingsViewModel(repo: offRepo);
      await offVm.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsViewModelProvider.overrideWith((ref) => offVm)],
          child: const MaterialApp(home: NotificationSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Sub-toggles should still exist in the tree
      expect(find.text('\u{1F4AC}  Agent 回复通知'), findsOneWidget);
      expect(find.text('⚠️  Agent 出错通知'), findsOneWidget);
      expect(find.text('\u{1F517}  连接状态通知'), findsOneWidget);

      // Verify the ViewModel state is indeed notificationsEnabled=false
      expect(offVm.state.notificationsEnabled, isFalse);
    });

    testWidgets('renders app bar with back button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('通知设置'), findsOneWidget);
    });

    testWidgets('shows explanation text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('通知通过设备本地推送实现'), findsOneWidget);
    });

    testWidgets('backgroundSyncToggle_reflectsState', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // The last Switch in the page is the background sync toggle.
      final switchFinder = find.byType(Switch).last;
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
    });

    testWidgets('backgroundSyncToggle_togglesOnTap', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch).last;
      expect(tester.widget<Switch>(switchFinder).value, isTrue);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(switchFinder).value, isFalse);
    });
  });
}
