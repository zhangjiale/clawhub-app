/// 用户偏好设置实体
///
/// 对齐: PRD 3.8 (推送通知与状态提醒), component-spec 9 (设置页)
///
/// 这是应用级全局设置单例 (singleton row in database)。
/// 所有字段都是 final + const constructor — 通过 [copyWith] 产生变体。
class UserPreferences {
  // ── Notification ──────────────────────────────────────────────

  /// 通知总开关
  final bool notificationsEnabled;

  /// Agent 完成回复时通知
  final bool notifyOnReply;

  /// Agent 执行出错时通知
  final bool notifyOnError;

  /// 实例连接状态变化时通知
  final bool notifyOnConnectionChange;

  // ── Do Not Disturb ────────────────────────────────────────────

  /// 免打扰总开关
  final bool dndEnabled;

  /// 免打扰开始小时 (0–23)
  final int dndStartHour;

  /// 免打扰开始分钟 (0–59)
  final int dndStartMinute;

  /// 免打扰结束小时 (0–23)
  final int dndEndHour;

  /// 免打扰结束分钟 (0–59)
  final int dndEndMinute;

  // ── Biometric ─────────────────────────────────────────────────

  /// 生物识别解锁开关
  final bool biometricEnabled;

  // ── Background Sync ───────────────────────────────────────────

  /// 后台同步开关（US-018）。默认启用。
  final bool backgroundSyncEnabled;

  const UserPreferences({
    this.notificationsEnabled = true,
    this.notifyOnReply = true,
    this.notifyOnError = true,
    this.notifyOnConnectionChange = true,
    this.dndEnabled = false,
    this.dndStartHour = 22,
    this.dndStartMinute = 0,
    this.dndEndHour = 8,
    this.dndEndMinute = 0,
    this.biometricEnabled = false,
    this.backgroundSyncEnabled = true,
  });

  factory UserPreferences.defaults() => const UserPreferences();

  UserPreferences copyWith({
    bool? notificationsEnabled,
    bool? notifyOnReply,
    bool? notifyOnError,
    bool? notifyOnConnectionChange,
    bool? dndEnabled,
    int? dndStartHour,
    int? dndStartMinute,
    int? dndEndHour,
    int? dndEndMinute,
    bool? biometricEnabled,
    bool? backgroundSyncEnabled,
  }) {
    return UserPreferences(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyOnReply: notifyOnReply ?? this.notifyOnReply,
      notifyOnError: notifyOnError ?? this.notifyOnError,
      notifyOnConnectionChange:
          notifyOnConnectionChange ?? this.notifyOnConnectionChange,
      dndEnabled: dndEnabled ?? this.dndEnabled,
      dndStartHour: dndStartHour ?? this.dndStartHour,
      dndStartMinute: dndStartMinute ?? this.dndStartMinute,
      dndEndHour: dndEndHour ?? this.dndEndHour,
      dndEndMinute: dndEndMinute ?? this.dndEndMinute,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      backgroundSyncEnabled:
          backgroundSyncEnabled ?? this.backgroundSyncEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreferences &&
          notificationsEnabled == other.notificationsEnabled &&
          notifyOnReply == other.notifyOnReply &&
          notifyOnError == other.notifyOnError &&
          notifyOnConnectionChange == other.notifyOnConnectionChange &&
          dndEnabled == other.dndEnabled &&
          dndStartHour == other.dndStartHour &&
          dndStartMinute == other.dndStartMinute &&
          dndEndHour == other.dndEndHour &&
          dndEndMinute == other.dndEndMinute &&
          biometricEnabled == other.biometricEnabled &&
          backgroundSyncEnabled == other.backgroundSyncEnabled;

  @override
  int get hashCode => Object.hash(
    notificationsEnabled,
    notifyOnReply,
    notifyOnError,
    notifyOnConnectionChange,
    dndEnabled,
    dndStartHour,
    dndStartMinute,
    dndEndHour,
    dndEndMinute,
    biometricEnabled,
    backgroundSyncEnabled,
  );

  @override
  String toString() =>
      'UserPreferences(notifications: $notificationsEnabled, '
      'reply: $notifyOnReply, error: $notifyOnError, '
      'connChange: $notifyOnConnectionChange, '
      'dnd: $dndEnabled ($dndStartHour:${dndStartMinute.toString().padLeft(2, '0')}'
      '—$dndEndHour:${dndEndMinute.toString().padLeft(2, '0')}), '
      'biometric: $biometricEnabled, '
      'bgSync: $backgroundSyncEnabled)';
}
