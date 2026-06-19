import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';
import 'package:claw_hub/features/settings/biometric_settings_page.dart';
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
      child: const MaterialApp(home: BiometricSettingsPage()),
    );
  }

  group('BiometricSettingsPage', () {
    testWidgets('renders biometric toggle row', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('🔐  Face ID / 指纹解锁'), findsOneWidget);
      expect(find.text('打开 App 时要求身份验证'), findsOneWidget);
    });

    testWidgets('shows disabled state when biometric is off', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsOneWidget);
      expect(vm.state.biometricEnabled, isFalse);
    });

    testWidgets('toggling switch updates state optimistically', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pump();

      // State should be updated optimistically
      expect(vm.state.biometricEnabled, isTrue);
    });

    testWidgets('renders app bar with back button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('生物识别解锁'), findsOneWidget);
    });

    testWidgets('shows explanation text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('开启后，每次打开虾Hub 需要验证你的身份'), findsOneWidget);
    });
  });
}
