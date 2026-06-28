---
# ClawHub 数据库 Schema v3.0 (Zero-Trigger)
# 与架构设计 vFinal 对齐
# 原则: 数据库层零触发器，所有逻辑由应用层 Repository/UseCase 维护
# 生成时间: 2026-06-07
---

-- ============================================================
-- 0. 初始化 PRAGMA
-- ============================================================
PRAGMA foreign_keys = ON;
PRAGMA encoding = 'UTF-8';

-- ============================================================
-- 1. 清理旧表 (按依赖逆序，避免外键约束冲突)
-- ============================================================
DROP TABLE IF EXISTS tool_calls;
DROP TABLE IF EXISTS quick_commands;
DROP TABLE IF EXISTS agent_stats;
DROP TABLE IF EXISTS notification_queue;
DROP TABLE IF EXISTS sync_cursors;
DROP TABLE IF EXISTS messages_fts;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS conversations;
DROP TABLE IF EXISTS agents;
DROP TABLE IF EXISTS instances;
DROP TABLE IF EXISTS app_settings;
DROP TABLE IF EXISTS analytics_events;

-- ============================================================
-- 2. 核心父表
-- ============================================================

-- 2.1 实例管理表 (instances)
-- 对齐: 架构 vFinal 5.1 (ACL 状态机), 5.6 (网络环境感知)
-- health_status: 0=Unknown, 1=Online, 2=Offline, 3=Connecting, 4=ExpectedOffline
CREATE TABLE instances (
    id TEXT PRIMARY KEY,                       -- UUID, 业务主键
    name TEXT NOT NULL UNIQUE,                 -- 实例名称，如"我的MacBook"
    gateway_url TEXT NOT NULL,                 -- ws://... 或 wss://...
    token_ref TEXT NOT NULL,                   -- iOS Keychain / Android Keystore 引用 Key
    health_status INTEGER DEFAULT 0,           -- 健康状态枚举
    is_local_network INTEGER DEFAULT 0,        -- 0:外网, 1:内网(正则预判)
    last_connected_at INTEGER,                 -- 最后连接成功时间戳(秒)
    created_at INTEGER NOT NULL                -- 创建时间(秒)
);

-- 2.2 全局配置表 (app_settings)
-- 对齐: 架构 vFinal 5.9 (免打扰), 5.10 (生物识别), 5.11 (通知权限)
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,                       -- JSON 或纯文本
    updated_at INTEGER NOT NULL                -- 最后修改时间(秒)
);

-- 2.3 埋点事件表 (analytics_events)
-- 对齐: 架构 vFinal 第9章 (AOP Tracker), 8.2 目录结构
CREATE TABLE analytics_events (
    id TEXT PRIMARY KEY,                       -- UUID
    event_name TEXT NOT NULL,                  -- 如 "message_sent"
    params TEXT,                               -- JSON 格式参数
    timestamp INTEGER NOT NULL                 -- 事件时间(秒)
);

-- ============================================================
-- 3. Agent 与会话层
-- ============================================================

-- 3.1 Agent (虾) 配置表 (agents)
-- 对齐: 架构 vFinal 4.0 (核心领域模型), 5.7 (动态主题)
-- 采用双 ID 策略: local_id 为本地 UUID 主键，remote_id 为 Gateway 分配的远端 ID
-- UNIQUE(instance_id, remote_id) 保证同一实例下远端 ID 不重复
CREATE TABLE agents (
    local_id TEXT PRIMARY KEY,                  -- 本地 UUID，业务主键
    remote_id TEXT NOT NULL,                   -- Gateway 分配的 Agent ID
    instance_id TEXT NOT NULL,                 -- 关联 instances.id
    name TEXT NOT NULL,                        -- Gateway 同步的名称
    nickname TEXT,                             -- 用户自定义本地昵称
    avatar_url TEXT,                           -- 本地沙盒路径或远程URL
    theme_color TEXT DEFAULT '#007AFF',        -- 动态主题色 Hex
    is_pinned INTEGER DEFAULT 0,               -- 是否置顶: 0=否, 1=是
    created_at INTEGER NOT NULL,
    UNIQUE(instance_id, remote_id),            -- 同一实例下远端 ID 唯一
    FOREIGN KEY (instance_id) REFERENCES instances(id) ON DELETE CASCADE
);

-- 3.2 会话聚合根表 (conversations)
-- 对齐: 架构 vFinal 4.0 (Conversation 聚合根), 5.2 (预览生成引擎)
-- id 生成规则: hash(instance_id + agent_id), 确保全局唯一
-- 注意: last_message_preview / unread_count / last_message_time 由应用层 Repository 事务维护
CREATE TABLE conversations (
    id TEXT PRIMARY KEY,                       -- 复合键: hash(instance_id + agent_id)
    agent_id TEXT NOT NULL,                    -- 关联 agents.local_id
    instance_id TEXT NOT NULL,                 -- 冗余: 用于路由和统计
    last_message_id TEXT,                      -- 关联 messages.client_id (应用层维护)
    last_message_preview TEXT,                 -- 预览引擎生成的40字预览 (应用层维护)
    last_message_time INTEGER DEFAULT 0,       -- 用于消息页时间降序排列(毫秒)
    unread_count INTEGER DEFAULT 0,            -- 未读角标 (应用层维护)
    is_muted INTEGER DEFAULT 0,                -- 是否免打扰: 0=否, 1=是
    FOREIGN KEY (agent_id) REFERENCES agents(local_id) ON DELETE CASCADE
);

-- ============================================================
-- 4. 消息流层
-- ============================================================

-- 4.1 消息流表 (messages)
-- 对齐: 架构 vFinal 5.3 (7状态消息生命周期), 5.12 (大文件分片)
-- 物理主键 rowid 为 INTEGER，兼容 FTS5 content_rowid 机制
-- 状态枚举: 0=Draft, 1=Pending, 2=Sending, 3=Sent, 4=Delivered, 5=Failed, 6=Expired
-- 角色枚举: 0=User, 1=Agent, 2=System
-- 类型枚举: 0=Text, 1=Image, 2=File, 3=ToolCall
CREATE TABLE messages (
    rowid INTEGER PRIMARY KEY AUTOINCREMENT,   -- 物理主键，FTS5 映射用
    client_id TEXT UNIQUE NOT NULL,            -- 本地 UUID (发送与去重兜底)
    server_id TEXT UNIQUE,                     -- Gateway 返回 ID (全局去重)
    conversation_id TEXT NOT NULL,             -- 关联 conversations.id
    agent_id TEXT NOT NULL,                    -- 冗余: 用于统计和清理，关联 agents.local_id
    role INTEGER NOT NULL,                     -- 角色枚举
    content TEXT,                              -- 文本内容或文件路径
    type INTEGER NOT NULL,                     -- 消息类型枚举
    status INTEGER NOT NULL,                   -- 7状态生命周期枚举
    logical_clock INTEGER NOT NULL,            -- 逻辑时钟，解决同秒排序
    timestamp INTEGER NOT NULL,                -- 消息时间(毫秒)
    metadata TEXT,                             -- JSON: 缩略图路径/文件元数据/工具调用ID等
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

-- 4.2 工具调用子表 (tool_calls)
-- 对齐: 架构 vFinal 4.0 (ToolCall 子实体), 5.3 (工具调用状态机)
-- 状态枚举: 0=Pending, 1=Running, 2=Success, 3=Failed
CREATE TABLE tool_calls (
    id TEXT PRIMARY KEY,                       -- UUID
    message_id TEXT NOT NULL,                  -- 关联 messages.client_id
    tool_name TEXT NOT NULL,                   -- 工具名称
    status INTEGER NOT NULL,                   -- 工具调用状态枚举
    input_args TEXT,                           -- JSON 格式输入参数
    output_result TEXT,                        -- JSON 格式输出结果
    started_at INTEGER,                        -- 开始时间(毫秒)
    ended_at INTEGER,                          -- 结束时间(毫秒)
    FOREIGN KEY (message_id) REFERENCES messages(client_id) ON DELETE CASCADE
);

-- ============================================================
-- 5. 辅助业务表
-- ============================================================

-- 5.1 快捷指令表 (quick_commands)
-- 对齐: 架构 vFinal 4.0 (QuickCommand), 5.7 (快捷指令与动态主题)
CREATE TABLE quick_commands (
    id TEXT PRIMARY KEY,                       -- UUID
    agent_id TEXT NOT NULL,                    -- 关联 agents.local_id
    label TEXT NOT NULL,                     -- 展示名: "查看状态"
    payload TEXT NOT NULL,                   -- 指令文本: "/status"
    sort_order INTEGER DEFAULT 0,              -- 显示排序
    FOREIGN KEY (agent_id) REFERENCES agents(local_id) ON DELETE CASCADE
);

-- 5.2 虾成长面板统计(已删除, round 3B schema v6→v7)
-- 历史: 原 agent_stats 缓存表于 round 3B 删除(写无读路径,统计由
-- EvaluateAchievementsUseCase 全量实时聚合)。`AgentStats` domain model
-- 仍存在(`lib/domain/models/agent_stats.dart`),仅作为结果类型。
-- DROP TABLE IF EXISTS agent_stats 已在 §1 清理序列中处理。

-- 5.3 免打扰通知暂存队列 (notification_queue)
-- 对齐: 架构 vFinal 5.9 (推送通知与后台保活引擎)
-- type 枚举: 0=任务完成, 1=错误, 2=状态变化
-- is_processed: 0=未处理(静默队列中), 1=已推送
CREATE TABLE notification_queue (
    id TEXT PRIMARY KEY,                       -- UUID
    agent_id TEXT NOT NULL,                    -- 关联 agents.local_id，用于路由和通知
    instance_id TEXT NOT NULL,                 -- 关联 instances.id (用于路由)
    title TEXT NOT NULL,                       -- 通知标题
    body TEXT NOT NULL,                        -- 通知内容
    type INTEGER NOT NULL,                     -- 通知类型枚举
    target_route TEXT NOT NULL,                -- 深度链接: "clawhub://chat/{agent_id}"
    is_processed INTEGER DEFAULT 0,          -- 处理状态
    created_at INTEGER NOT NULL                -- 创建时间(秒)
);

-- 5.4 同步游标表 (sync_cursors)
-- 对齐: 架构 vFinal 6.2 (断线重连与历史补偿)
-- 存储每个实例的增量同步游标，用于断线后拉取缺失消息
CREATE TABLE sync_cursors (
    instance_id TEXT PRIMARY KEY,              -- 关联 instances.id
    cursor TEXT NOT NULL,                    -- Gateway 返回的同步游标/last_message_id
    updated_at INTEGER NOT NULL,             -- 最后更新时间(毫秒)
    FOREIGN KEY (instance_id) REFERENCES instances(id) ON DELETE CASCADE
);

-- ============================================================
-- 6. 全文搜索 FTS5 虚拟表
-- ============================================================
-- 对齐: 架构 vFinal 5.4 (全局搜索与锚点定位)
-- 注意: 零触发器原则下，FTS5 虚拟表不再通过触发器自动同步。
-- 应用层 Repository 必须在 insert/update/delete message 时手动同步 messages_fts。
-- 具体做法见下方"应用层同步规范"。

CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,                                   -- 搜索内容
    content='messages',                          -- 映射外部表
    content_rowid='rowid',                       -- 映射外部表的整数主键
    tokenize='unicode61'                         -- 内置分词器，后续可插拔 jieba
);

-- ============================================================
-- 7. 索引策略 (性能保障)
-- ============================================================

-- 7.1 实例层索引
CREATE INDEX idx_instances_status ON instances(health_status);

-- 7.2 Agent 层索引
CREATE INDEX idx_agents_instance ON agents(instance_id);
CREATE INDEX idx_agents_remote ON agents(instance_id, remote_id);    -- 远端 ID 查找
CREATE INDEX idx_agents_pin_name ON agents(instance_id, is_pinned DESC, name ASC);

-- 7.3 会话层索引
CREATE INDEX idx_conv_time ON conversations(last_message_time DESC);
CREATE INDEX idx_conv_agent ON conversations(agent_id);          -- 快速定位会话

-- 7.4 消息层索引 (核心)
CREATE INDEX idx_msgs_conv_time ON messages(conversation_id, timestamp DESC);
CREATE INDEX idx_msgs_server ON messages(server_id);               -- 去重查询
CREATE INDEX idx_msgs_agent ON messages(agent_id);               -- 统计与定期清理
CREATE INDEX idx_msgs_status ON messages(status);                -- Outbox 恢复 (PENDING)
CREATE INDEX idx_msgs_conv_clock ON messages(conversation_id, logical_clock DESC); -- 逻辑时钟

-- 7.5 工具调用索引
CREATE INDEX idx_tool_calls_msg ON tool_calls(message_id);

-- 7.6 辅助表索引
CREATE INDEX idx_qcmd_order ON quick_commands(agent_id, sort_order);
CREATE INDEX idx_notify_pending ON notification_queue(is_processed, created_at);
CREATE INDEX idx_analytics_time ON analytics_events(timestamp);

-- ============================================================
-- 8. 初始种子数据
-- ============================================================

-- 应用默认配置 (首次启动时由 MigrationManager 或应用层插入)
INSERT INTO app_settings (key, value, updated_at) VALUES
('notification_master', '1', strftime('%s', 'now')),
('dnd_start', '22:00', strftime('%s', 'now')),
('dnd_end', '08:00', strftime('%s', 'now')),
('biometric_lock', '0', strftime('%s', 'now')),
('biometric_timeout_seconds', '300', strftime('%s', 'now')),  -- 后台5分钟触发
('theme_mode', 'system', strftime('%s', 'now'));               -- system/light/dark

-- ============================================================
-- 9. Schema 版本标记
-- ============================================================
PRAGMA user_version = 3;

-- ============================================================
-- 10. 应用层同步规范 (供开发者参考，非 SQL 执行)
-- ============================================================
-- 由于零触发器原则，以下逻辑必须在应用层 Repository 中显式实现：
--
-- 10.1 FTS5 手动同步
--   插入消息时:
--     INSERT INTO messages_fts(rowid, content) VALUES (newRowid, content);
--   删除消息时:
--     INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', oldRowid, content);
--   更新消息内容时:
--     INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', oldRowid, oldContent);
--     INSERT INTO messages_fts(rowid, content) VALUES (newRowid, newContent);
--   注意: 仅当 content 字段实际变化时才执行更新，避免无效 I/O。
--
-- 10.2 会话聚合维护 (替代原 trg_conversation_update)
--   在 SendMessageUseCase / ReceiveMessageUseCase 中，使用 DB.transaction():
--     1. INSERT INTO messages (...)
--     2. UPDATE conversations SET
--          last_message_id = ?,
--          last_message_time = ?,
--          last_message_preview = ?,
--          unread_count = unread_count + (role == AGENT ? 1 : 0)
--        WHERE id = ?;
--   预览生成规则 (应用层纯函数):
--     prefix = (role == USER) ? '你: ' : ''
--     if type == IMAGE: preview = prefix + '[图片]'
--     if type == FILE:  preview = prefix + '[文件]'
--     if type == TOOL_CALL: preview = prefix + '[工具调用]'
--     else: preview = prefix + truncate(stripMarkdown(content), 40)
--
-- 10.3 1000条红线清理 (替代原 trg_message_limit_cleanup)
--   策略A: 应用层启动时异步清理 (推荐)
--     在 App 启动后，后台 Isolate 执行:
--       for each agent_id in agents:
--         count = SELECT count(*) FROM messages WHERE agent_id = ?
--         if count > 1000:
--           DELETE FROM messages WHERE agent_id = ?
--             AND rowid NOT IN (SELECT rowid FROM messages WHERE agent_id = ? ORDER BY timestamp DESC LIMIT 1000)
--   策略B: 每次发送消息后检查 (简单但可能阻塞 UI)
--     不推荐，因为清理操作可能耗时。
--   策略C: 定期任务 (如每天凌晨)
--     结合 WorkManager / Background Fetch 执行。
--
-- 10.4 消息去重 (替代原 UNIQUE 约束的兜底)
--   虽然 server_id 和 client_id 有 UNIQUE 约束，但应用层仍需先查询再插入:
--     if exists(server_id) or exists(client_id): return existingMessage
--     else: insert
--   避免依赖数据库抛异常来做业务判断。
--
-- 10.5 级联删除 (外键已定义 ON DELETE CASCADE)
--   注意: 删除 instances/agents/conversations 时，外键级联会自动清理子表数据。
--   这是数据库层的约束机制，不属于"业务逻辑触发器"，因此保留外键。
--
-- ============================================================
-- 11. 迁移注意事项
-- ============================================================
-- 1. SQLCipher: 实际连接时需在 drift/NativeDatabase 中传入密码参数。
--    若 SQLCipher 集成受阻，可降级为 SQLite + flutter_secure_storage 仅加密 Token。
-- 2. 外键约束: 执行表重建迁移时，必须先执行 PRAGMA foreign_keys = OFF。
-- 3. FTS5 重建: 当 messages 表结构变更时，必须 DROP TABLE messages_fts 后重建虚拟表，
--    并执行 INSERT INTO messages_fts(messages_fts) VALUES('rebuild');
-- 4. 时间戳单位: messages/tool_calls 使用毫秒(排序精度)，其他表使用秒(节省空间)。
-- 5. agents 双 ID 策略: 采用 local_id (本地 UUID) 为主键，remote_id (Gateway 分配) 为唯一约束。
--    所有外键均指向 agents(local_id)，领域层 Conversation.agentId / Message.agentId 存储 local_id。
-- 6. 零触发器原则: 所有业务逻辑必须在 Dart/Kotlin/Swift 中实现，禁止在 SQLite 中写触发器。
--    这保证了: 逻辑可见、可单测、可调试、可降级。
