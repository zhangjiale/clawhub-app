import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

/// QuickCommandsEditor — per-agent quick command CRUD with drag-reorder,
/// swipe-to-delete, and a 10-item cap.
///
/// All state mutations surface via [onChanged]; the widget itself never
/// calls any repository or service. Parent (typically a ViewModel) is the
/// single source of truth for persistence.
class QuickCommandsEditor extends StatefulWidget {
  /// The owning agent's localId. Used to construct new [QuickCommand]s
  /// when the user adds one through the bottom sheet.
  final String agentId;

  /// Current list of quick commands. The widget is purely a view over this
  /// list — reordering, adding, and deleting all produce new lists that
  /// are emitted via [onChanged] with sortOrder re-normalized 0..n-1.
  final List<QuickCommand> commands;

  /// Sole write path. Called with a new list after every add/delete/reorder.
  final ValueChanged<List<QuickCommand>> onChanged;

  /// Maximum allowed number of quick commands. Default 10.
  final int maxItems;

  const QuickCommandsEditor({
    super.key,
    required this.agentId,
    required this.commands,
    required this.onChanged,
    this.maxItems = 10,
  });

  @override
  State<QuickCommandsEditor> createState() => _QuickCommandsEditorState();
}

class _QuickCommandsEditorState extends State<QuickCommandsEditor> {
  bool get _atMax => widget.commands.length >= widget.maxItems;

  void _emit(List<QuickCommand> next) {
    final reSorted = [
      for (var i = 0; i < next.length; i++) next[i].copyWith(sortOrder: i),
    ];
    widget.onChanged(reSorted);
  }

  void _onAdd({required String label, required String payload}) {
    // Guard against TOCTOU race: commands may have grown to max while the
    // bottom sheet was open (e.g. gateway sync pushing updates).
    if (_atMax) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('每个虾最多10个快捷指令')));
      return;
    }
    final newCmd = QuickCommand(
      id: const Uuid().v4(),
      agentId: widget.agentId,
      label: label,
      payload: payload,
      sortOrder: widget.commands.length,
    );
    _emit([...widget.commands, newCmd]);
  }

  void _onDelete(int index) {
    final next = [...widget.commands]..removeAt(index);
    _emit(next);
  }

  void _onReorder(int oldIndex, int newIndex) {
    final next = [...widget.commands];
    final cmd = next.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(insertAt, cmd);
    _emit(next);
  }

  void _onAddPressed() {
    if (_atMax) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('每个虾最多10个快捷指令')));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _AddCommandSheet(
        onSubmit: (label, payload) {
          Navigator.of(sheetCtx).pop();
          _onAdd(label: label, payload: payload);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.commands.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: XiaSpacing.s4),
            child: Text(
              '还没有快捷指令，点击下方 + 添加',
              style: TextStyle(color: XiaColors.text3, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          )
        else
          // 不要包 Flexible：QuickCommandsEditor 的实际父容器是无界高度的
          // ListView（见 AgentConfigPage 的 ListView body），flex 子节点会
          // 触发 "RenderFlex children have non-zero flex but incoming
          // height constraints are unbounded" 异常，框架吞掉后导致
          // ReorderableListView 不渲染任何 item。shrinkWrap:true + 不可滚
          // 动物理已经让列表按内容自适应高度，不需要 Flexible。
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: widget.commands.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final cmd = widget.commands[index];
              return Dismissible(
                key: Key('qc-dismiss-${cmd.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: XiaSpacing.s4),
                  color: XiaColors.red,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => _onDelete(index),
                child: _QuickCommandRow(
                  key: Key('qc-row-${cmd.id}'),
                  command: cmd,
                  index: index,
                ),
              );
            },
          ),
        const SizedBox(height: XiaSpacing.s2),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.add),
            color: _atMax ? XiaColors.text4 : null,
            tooltip: _atMax ? '已达上限 (10/10)' : '添加快捷指令',
            onPressed: _onAddPressed,
          ),
        ),
      ],
    );
  }
}

class _QuickCommandRow extends StatelessWidget {
  final QuickCommand command;
  final int index;

  const _QuickCommandRow({
    super.key,
    required this.command,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s3,
        vertical: XiaSpacing.s2,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: XiaColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command.label,
                  style: const TextStyle(
                    color: XiaColors.text1,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  command.payload,
                  style: const TextStyle(
                    color: XiaColors.text3,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: XiaSpacing.s2),
              child: Icon(Icons.drag_handle, color: XiaColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCommandSheet extends StatefulWidget {
  final void Function(String label, String payload) onSubmit;
  const _AddCommandSheet({required this.onSubmit});

  @override
  State<_AddCommandSheet> createState() => _AddCommandSheetState();
}

class _AddCommandSheetState extends State<_AddCommandSheet> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _payloadCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(_labelCtrl.text.trim(), _payloadCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: XiaSpacing.s4,
        right: XiaSpacing.s4,
        top: XiaSpacing.s4,
        bottom: MediaQuery.of(context).viewInsets.bottom + XiaSpacing.s4,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '添加快捷指令',
              style: TextStyle(
                color: XiaColors.text1,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: XiaSpacing.s3),
            TextFormField(
              controller: _labelCtrl,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：查看状态',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '名称不能为空';
                if (v.length > 20) return '名称最多20个字符';
                return null;
              },
            ),
            const SizedBox(height: XiaSpacing.s2),
            TextFormField(
              controller: _payloadCtrl,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: '指令',
                hintText: '如：/status',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '指令不能为空';
                if (v.length > 100) return '指令最多100个字符';
                return null;
              },
            ),
            const SizedBox(height: XiaSpacing.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: XiaSpacing.s2),
                FilledButton(onPressed: _submit, child: const Text('保存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
