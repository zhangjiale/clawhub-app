/// Stats provider 定义在 [app/di/providers.dart]，
/// [StatsData] 值对象在 [domain/models/stats_data.dart]。
///
/// 本文件保留为 re-export 以保持向后兼容 — agent_list_page 和
/// 相关测试无需修改 import 路径。
///
/// 新代码应直接从:
/// - [package:claw_hub/domain/models/stats_data.dart] 导入 [StatsData]
/// - [package:claw_hub/app/di/providers.dart] 导入 [statsProvider]
library;

export 'package:claw_hub/domain/models/stats_data.dart' show StatsData;
export 'package:claw_hub/app/di/providers.dart' show statsProvider;
