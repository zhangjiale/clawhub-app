import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/features/chat_room/widgets/quick_command_bar.dart';

void main() {
  group('QuickCommandBar agent theme', () {
    final commands = [
      QuickCommand(
        id: '1',
        agentId: 'agent-1',
        label: '状态',
        payload: '/status',
      ),
    ];

    Widget wrap(Widget child, {AgentTheme? agentTheme}) => MaterialApp(
      theme: ThemeData(extensions: agentTheme != null ? [agentTheme] : []),
      home: Scaffold(body: child),
    );

    testWidgets('pill text uses AgentTheme primary color', (tester) async {
      await tester.pumpWidget(
        wrap(
          QuickCommandBar(commands: commands, onCommandTap: (_) {}),
          agentTheme: const AgentTheme(primary: Color(0xFF5F9B96)),
        ),
      );

      final text = tester.widget<Text>(find.text('状态'));
      expect(text.style!.color, const Color(0xFF5F9B96));
    });

    testWidgets('pill text falls back to coral when no AgentTheme', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(QuickCommandBar(commands: commands, onCommandTap: (_) {})),
      );

      final text = tester.widget<Text>(find.text('状态'));
      expect(text.style!.color, const Color(0xFFC27C68));
    });

    testWidgets('tap invokes onCommandTap with payload', (tester) async {
      String? captured;
      await tester.pumpWidget(
        wrap(
          QuickCommandBar(
            commands: commands,
            onCommandTap: (payload) => captured = payload,
          ),
          agentTheme: const AgentTheme(primary: Color(0xFF5F9B96)),
        ),
      );

      await tester.tap(find.text('状态'));
      expect(captured, '/status');
    });
  });
}
