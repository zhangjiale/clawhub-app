import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/quick_command_bar.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

void main() {
  group('QuickCommandBar', () {
    final sampleCommands = [
      QuickCommand(
        id: 'qc-1',
        agentId: 'agent-1',
        label: 'Status',
        payload: '/status',
        sortOrder: 0,
      ),
      QuickCommand(
        id: 'qc-2',
        agentId: 'agent-1',
        label: 'Help',
        payload: '/help',
        sortOrder: 1,
      ),
    ];

    Widget buildBar({
      required List<QuickCommand> commands,
      ValueChanged<String>? onCommandTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: QuickCommandBar(
            commands: commands,
            onCommandTap: onCommandTap ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('renders ActionChip for each command with correct label', (tester) async {
      await tester.pumpWidget(buildBar(commands: sampleCommands));

      // Two ActionChips for two commands
      expect(find.byType(ActionChip), findsNWidgets(2));
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
    });

    testWidgets('calls onCommandTap with correct payload when chip is tapped', (tester) async {
      String? tappedPayload;
      await tester.pumpWidget(buildBar(
        commands: sampleCommands,
        onCommandTap: (payload) => tappedPayload = payload,
      ));

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(tappedPayload, '/status');
    });

    testWidgets('shows nothing when commands list is empty', (tester) async {
      await tester.pumpWidget(buildBar(commands: []));

      // The widget returns SizedBox.shrink, so no ActionChips or text
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('renders commands in a horizontal scrollable list', (tester) async {
      await tester.pumpWidget(buildBar(commands: sampleCommands));

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.scrollDirection, Axis.horizontal);
    });
  });
}
