import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 诊断页（spec §7）。v1 扁平逆序列表，payload 默认折叠（tap-to-reveal）。
/// release 可见；首次进入弹一次性警告（SharedPreferences 标志）。
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  final Set<String> _expanded = {}; // entry.id → expanded

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWarning());
  }

  Future<void> _maybeShowWarning() async {
    // Await the FutureProvider's future so we read the real persisted flag,
    // not a loading placeholder (an orElse:true short-circuit would never show).
    final shown = await ref.read(diagnosticsWarningShownProvider.future);
    if (shown || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('诊断页'),
        content: const Text('本页含消息原文与协议细节，请勿在他人旁观看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我已了解'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // ARB #3: route the acknowledgement through the provider's markShown()
    // instead of writing SharedPreferences directly - the key lives in one
    // place (the notifier) and the write is testable.
    await ref.read(diagnosticsWarningShownProvider.notifier).markShown();
  }

  String _formatTs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}.${(dt.millisecond ~/ 100)}';
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(diagnosticsEntriesProvider);
    final store = ref.watch(apiLogStoreProvider);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '诊断',
          style: TextStyle(
            fontSize: XiaTypography.sectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 20),
            label: const Text('清空'),
            onPressed: () => _confirmClear(store),
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorView(error: e, title: '加载失败'),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icon(Icons.receipt_long),
              title: '还没有日志',
              subtitle: '连接 Gateway 并发条消息试试',
            );
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => _entryTile(entries[i]),
          );
        },
      ),
    );
  }

  Widget _entryTile(ApiLogEntry e) {
    final expanded = _expanded.contains(e.id);
    final (icon, iconColor) = switch (e.direction) {
      ApiLogDirection.outgoing => (Icons.north, XiaColors.accent),
      ApiLogDirection.incoming => (Icons.south, XiaColors.green),
      null => (Icons.radio_button_unchecked, XiaColors.text3),
    };
    final title = e.kind == ApiLogKind.state
        ? (e.state ?? 'event')
        : (e.methodOrEvent ?? e.kind.name);
    final sub = <String>[
      _formatTs(e.timestampMs),
      if (e.kind == ApiLogKind.res)
        e.ok == true ? 'ok' : 'ERR:${e.errorCode ?? "?"}'
      else if (e.kind == ApiLogKind.state && e.message != null)
        e.message!
      else if (e.durationMs != null)
        '+${e.durationMs}ms',
      if (e.byteSize != null) '${e.byteSize}B',
    ].join(' · ');

    return Column(
      // ARB #4: stable key so a prepended newest-first entry is an O(1) insert
      // (element reused by key) instead of shifting every index -> full rebuild.
      key: ValueKey(e.id),
      children: [
        ListTile(
          leading: Icon(icon, color: iconColor, size: 18),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            sub,
            style: const TextStyle(fontSize: 11, color: XiaColors.text4),
          ),
          trailing: e.payloadPreview == null
              ? null
              : Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
          onTap: e.payloadPreview == null
              ? null
              : () => setState(() {
                  if (expanded) {
                    _expanded.remove(e.id);
                  } else {
                    _expanded.add(e.id);
                  }
                }),
        ),
        if (expanded && e.payloadPreview != null)
          Container(
            width: double.infinity,
            color: XiaColors.surface2,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              e.payloadPreview!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _confirmClear(ApiLogStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('将清除所有已记录的诊断日志，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok == true) {
      store.clear();
      // diagnosticsEntriesProvider (Task 6) only re-emits on new entries, not on
      // clear(). Invalidate so it re-seeds with the now-empty snapshot.
      ref.invalidate(diagnosticsEntriesProvider);
    }
  }
}
