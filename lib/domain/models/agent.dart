import 'quick_command.dart';

/// Agent (虾) 实体
/// 对齐: 架构 vFinal 4.0 (核心领域模型), 5.7 (动态主题)
///
/// 采用 (instanceId, remoteId) 复合唯一键方案，避免多实例间 Agent ID 冲突。
/// localId 为本地生成的 UUID，remoteId 为 Gateway 分配的 ID。
class Agent {
  final String localId; // 本地 UUID，主键
  final String remoteId; // Gateway 分配的 Agent ID
  final String instanceId; // 关联 instances.id
  final String name; // Gateway 同步的名称
  final String? nickname; // 用户自定义本地昵称，最多20字符
  final String? avatarUrl; // 本地沙盒路径或远程URL
  final String themeColor; // 动态主题色 Hex，默认 #4F83FF (V2 sapphire)
  final String? description; // Gateway 同步的描述，如"产品规划、需求分析"
  final bool isPinned; // 是否置顶
  final List<QuickCommand> quickCommands; // 预设快捷指令（MVP 从 mock 数据读取）
  final int createdAt; // 创建时间(秒)

  // US-021: Agent tombstone 状态。
  // removedAt: Gateway sync 独占写入（DriftAgentRepo.syncFromGateway 通过
  //   batch SQL UPDATE），非空表示远端已删除该 Agent。毫秒时间戳。
  // hiddenAt: v2 预留（用户主动隐藏），v1 期间无任何写入路径。
  // 两者均不经 copyWith 修改（见 copyWith 注释），只能通过 mapper 从 DB 读取注入。
  final int? removedAt;
  final int? hiddenAt;

  Agent({
    required this.localId,
    required this.remoteId,
    required this.instanceId,
    required this.name,
    this.nickname,
    this.avatarUrl,
    this.themeColor = '#4F83FF', // V2 sapphire (was V1 #007AFF iOS blue)
    this.description,
    this.isPinned = false,
    this.quickCommands = const [],
    int? createdAt,
    this.removedAt,
    this.hiddenAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 {
    _validate();
  }

  /// US-021: Agent 是否已被 Gateway 端删除（tombstoned）。
  bool get isRemoved => removedAt != null;

  /// US-021: Agent 是否已被用户主动隐藏（v2 预留，v1 恒为 false）。
  bool get isHidden => hiddenAt != null;

  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError('Agent 名称不能为空');
    }
    if (nickname != null && nickname!.length > 20) {
      throw ArgumentError('昵称最多20个字符');
    }
    if (!_isValidHexColor(themeColor)) {
      throw ArgumentError('主题色必须是有效的 Hex 颜色格式（如 #4F83FF）');
    }
  }

  static final _hexColorRegExp = RegExp(r'^#[0-9a-fA-F]{3,8}$');
  static bool _isValidHexColor(String color) => _hexColorRegExp.hasMatch(color);

  /// 复合唯一键：判断是否为同一 Agent（同一实例 + 同一远程 ID）
  bool isSameAgent(Agent other) {
    return instanceId == other.instanceId && remoteId == other.remoteId;
  }

  /// 获取显示名称（优先使用用户自定义昵称）
  String get displayName => nickname ?? name;

  // US-021: copyWith 故意 *不* 暴露 removedAt / hiddenAt 参数。
  // 现有 copyWith 用 `field: field ?? this.field` 模式，无法清空 nullable 字段
  //（copyWith(removedAt: null) 会被解读为"保持原值"）。若暴露 removedAt 参数，
  // 未来某人想用 copyWith 清 tombstone 会静默失败。强制所有 tombstone 状态变更
  // 走 DriftAgentRepo 的 DB 写入路径（mapper 从 DB 读取注入新值）。
  // 整改 Agent.copyWith 用 CopyWithSentinel 模式是历史欠债，不在 US-021 范围。
  Agent copyWith({
    String? localId,
    String? remoteId,
    String? instanceId,
    String? name,
    String? nickname,
    String? avatarUrl,
    String? themeColor,
    String? description,
    bool? isPinned,
    List<QuickCommand>? quickCommands,
    int? createdAt,
  }) {
    return Agent(
      localId: localId ?? this.localId,
      remoteId: remoteId ?? this.remoteId,
      instanceId: instanceId ?? this.instanceId,
      name: name ?? this.name,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      themeColor: themeColor ?? this.themeColor,
      description: description ?? this.description,
      isPinned: isPinned ?? this.isPinned,
      quickCommands: quickCommands ?? this.quickCommands,
      createdAt: createdAt ?? this.createdAt,
      removedAt: removedAt, // 透传，外部无法覆盖（copyWith 不暴露此参数）
      hiddenAt: hiddenAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Agent &&
          runtimeType == other.runtimeType &&
          localId == other.localId &&
          removedAt == other.removedAt &&
          hiddenAt == other.hiddenAt;

  @override
  int get hashCode => Object.hash(localId, removedAt, hiddenAt);

  @override
  String toString() =>
      'Agent(localId: $localId, remoteId: $remoteId, instanceId: $instanceId, name: $name, description: $description)';
}
