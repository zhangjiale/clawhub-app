import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';
import 'package:claw_hub/features/settings/dnd_page.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';
import 'package:claw_hub/features/settings/viewmodels/settings_view_model.dart';

class MockSettingsRepo extends Mock implements ISettingsRepo {}

void main() {
  setUpAll(() {
    registerFallbackValue(UserPreferences.defaults());
  });

  group('DoNotDisturbPage', () {
    testWidgets('renders DND toggle and label', (tester) async {
      final vm = await _createVm();
      await tester.pumpWidget(_buildTestWidget(vm));
      await tester.pump();

      expect(find.text('🌙  开启免打扰'), findsOneWidget);
      expect(find.text('开启后在设定时段内不推送通知'), findsOneWidget);
    });

    testWidgets('does not show time pickers when DND is disabled', (
      tester,
    ) async {
      final vm = await _createVm();
      await tester.pumpWidget(_buildTestWidget(vm));
      await tester.pump();

      expect(find.textContaining('开始时间'), findsNothing);
      expect(find.textContaining('结束时间'), findsNothing);
    });

    testWidgets('shows time pickers when DND is enabled', (tester) async {
      final vm = await _createVm(dndEnabled: true);
      await tester.pumpWidget(_buildTestWidget(vm));
      await tester.pump();

      expect(find.text('🌅  开始时间'), findsOneWidget);
      expect(find.text('🌇  结束时间'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
    });

    testWidgets('renders app bar with back button', (tester) async {
      final vm = await _createVm();
      await tester.pumpWidget(_buildTestWidget(vm));
      await tester.pump();

      expect(find.text('免打扰时段'), findsOneWidget);
    });

    testWidgets('shows explanation footer', (tester) async {
      final vm = await _createVm();
      await tester.pumpWidget(_buildTestWidget(vm));
      await tester.pump();

      expect(find.textContaining('免打扰时段内收到的通知将静默存储'), findsOneWidget);
    });
  });
}

/// Create a ViewModel with pre-loaded preferences.
Future<SettingsViewModel> _createVm({bool dndEnabled = false}) async {
  final repo = MockSettingsRepo();
  final defaults = UserPreferences.defaults().copyWith(dndEnabled: dndEnabled);
  when(() => repo.getPreferences()).thenAnswer((_) async => defaults);
  when(() => repo.updatePreferences(any())).thenAnswer((_) async {});
  when(() => repo.watchPreferences()).thenAnswer((_) => const Stream.empty());
  final vm = SettingsViewModel(repo: repo);
  await vm.init();
  return vm;
}

Widget _buildTestWidget(SettingsViewModel vm) {
  return ProviderScope(
    overrides: [settingsViewModelProvider.overrideWith((ref) => vm)],
    child: const MaterialApp(home: DoNotDisturbPage()),
  );
}
