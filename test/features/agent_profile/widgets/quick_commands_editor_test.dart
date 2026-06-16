import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/features/agent_profile/widgets/quick_commands_editor.dart';

void main() {
  group('QuickCommandsEditor', () {
    const agentId = 'agent-1';
    final sampleCommands = [
      QuickCommand(
        id: '1',
        agentId: agentId,
        label: '状态',
        payload: '/status',
        sortOrder: 0,
      ),
      QuickCommand(
        id: '2',
        agentId: agentId,
        label: '重置',
        payload: '/reset',
        sortOrder: 1,
      ),
      QuickCommand(
        id: '3',
        agentId: agentId,
        label: '记忆',
        payload: '/memory',
        sortOrder: 2,
      ),
    ];

    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 800, child: child)),
    );

    testWidgets('renders all command labels', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuickCommandsEditor(
            agentId: agentId,
            commands: sampleCommands,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('状态'), findsOneWidget);
      expect(find.text('重置'), findsOneWidget);
      expect(find.text('记忆'), findsOneWidget);
    });

    testWidgets('swipe-to-dismiss on row calls onChanged with re-sorted list', (
      tester,
    ) async {
      List<QuickCommand>? captured;
      await tester.pumpWidget(
        wrap(
          QuickCommandsEditor(
            agentId: agentId,
            commands: sampleCommands,
            onChanged: (l) => captured = l,
          ),
        ),
      );

      final dismissFinder = find.byKey(const Key('qc-dismiss-2'));
      expect(dismissFinder, findsOneWidget);

      await tester.drag(dismissFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.length, 2);
      expect(captured![0].id, '1');
      expect(captured![1].id, '3');
      expect(captured![0].sortOrder, 0);
      expect(captured![1].sortOrder, 1);
    });

    testWidgets(
      'tapping + button at maxItems shows SnackBar with limit message',
      (tester) async {
        final tenCommands = List.generate(
          10,
          (i) => QuickCommand(
            id: '$i',
            agentId: agentId,
            label: 'Cmd$i',
            payload: '/$i',
            sortOrder: i,
          ),
        );
        await tester.pumpWidget(
          wrap(
            QuickCommandsEditor(
              agentId: agentId,
              commands: tenCommands,
              onChanged: (_) {},
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        expect(find.text('每个虾最多10个快捷指令'), findsOneWidget);
      },
    );

    testWidgets('drag handle reorder calls onChanged with re-sorted list', (
      tester,
    ) async {
      List<QuickCommand>? captured;
      await tester.pumpWidget(
        wrap(
          QuickCommandsEditor(
            agentId: agentId,
            commands: sampleCommands,
            onChanged: (l) => captured = l,
          ),
        ),
      );

      // Drag the first row's handle down past the second row.
      final firstHandle = find.byIcon(Icons.drag_handle).first;
      await tester.drag(firstHandle, const Offset(0, 120));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.length, 3);
      final ids = captured!.map((c) => c.id).toList();
      // Order must have changed from [1,2,3] and sortOrder must be 0..n-1.
      expect(ids, isNot(equals(['1', '2', '3'])));
      for (var i = 0; i < captured!.length; i++) {
        expect(captured![i].sortOrder, i);
      }
    });
  });
}
