/// 快捷指令实体
/// 对齐: 架构 vFinal 4.0 (QuickCommand), 5.7 (快捷指令与动态主题)
class QuickCommand {
  final String id; // UUID
  final String agentId; // 关联 agents.localId
  final String label; // 展示名，如 "查看状态"
  final String payload; // 指令文本，如 "/status"
  final int sortOrder; // 显示排序

  QuickCommand({
    required this.id,
    required this.agentId,
    required this.label,
    required this.payload,
    this.sortOrder = 0,
  }) {
    _validate();
  }

  void _validate() {
    if (label.trim().isEmpty) {
      throw ArgumentError('快捷指令名称不能为空');
    }
    if (label.length > 20) {
      throw ArgumentError('快捷指令名称最多20个字符');
    }
    if (payload.trim().isEmpty) {
      throw ArgumentError('快捷指令内容不能为空');
    }
  }

  /// 按 sortOrder 升序排序的比较器
  static int sortByOrder(QuickCommand a, QuickCommand b) {
    return a.sortOrder.compareTo(b.sortOrder);
  }

  QuickCommand copyWith({
    String? id,
    String? agentId,
    String? label,
    String? payload,
    int? sortOrder,
  }) {
    return QuickCommand(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      label: label ?? this.label,
      payload: payload ?? this.payload,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuickCommand &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'QuickCommand(id: $id, agentId: $agentId, label: $label, payload: $payload)';
}
