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
  final String themeColor; // 动态主题色 Hex，默认 #007AFF
  final String? description; // Gateway 同步的描述，如"产品规划、需求分析"
  final bool isPinned; // 是否置顶
  final int createdAt; // 创建时间(秒)

  Agent({
    required this.localId,
    required this.remoteId,
    required this.instanceId,
    required this.name,
    this.nickname,
    this.avatarUrl,
    this.themeColor = '#007AFF',
    this.description,
    this.isPinned = false,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 {
    _validate();
  }

  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError('Agent 名称不能为空');
    }
    if (nickname != null && nickname!.length > 20) {
      throw ArgumentError('昵称最多20个字符');
    }
    if (!_isValidHexColor(themeColor)) {
      throw ArgumentError('主题色必须是有效的 Hex 颜色格式（如 #007AFF）');
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
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Agent &&
          runtimeType == other.runtimeType &&
          localId == other.localId;

  @override
  int get hashCode => localId.hashCode;

  @override
  String toString() =>
      'Agent(localId: $localId, remoteId: $remoteId, instanceId: $instanceId, name: $name, description: $description)';
}
