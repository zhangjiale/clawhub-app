# 系统架构图 v2（未来架构 · Planned）

> ⚠️ **本文档描述的是未来架构，尚未实现。**
> 当前实现请参考 [`../architecture.md`](../architecture.md)（v1.0 · 2026-06-10 · 虾Hub MVP 架构）。

---

## 状态

| 项 | 状态 |
|---|---|
| 文档版本 | v2.0 (draft) |
| 提案时间 | 2026-06-29 |
| 实现状态 | 🔴 未开始 |
| 预计实现 | 待定 |
| 维护人 | 乐哥 |

## 与现状的差异

| 维度 | 当前架构 (v1) | 未来架构 (v2，本文档) |
|---|---|---|
| App ↔ Gateway | Flutter App **直连** OpenClaw Gateway | Flutter App → **自建后端中转** → OpenClaw Gateway |
| 协议层 | App 需懂 OpenClaw nodes 协议 | App 只对自建后端，协议简单 |
| 鉴权 | App 直持 Gateway API Key | App 用 JWT，后端统一持 Gateway API Key |
| 对话历史 | Gateway 默认不存 | 后端持久化到 MySQL |
| 多端复用 | 每端各对接一次 | 一份后端，多端共用 |
| 后端实现 | 无 | Java 21 + Spring Boot 3 + WebFlux（待建） |

## 新增组件（本版引入）

### 自建后端 (ClawHub Backend)
- WebSocket Server（对 App）
- REST API（历史 / 配置 / 列表）
- JWT Auth Filter
- Session Manager（App session ↔ Gateway session 映射）
- Message Router（多 agent 路由）
- History Writer/Reader
- WebSocket Client（对 Gateway，nodes 协议）
- Gateway API Key 持有 + 限流/重试/审计

### 基础设施新增
- Redis（session 映射 / 在线状态 / 限流计数）
- MySQL 8（对话历史 / 用户偏好 / 设备表）
- MinIO / OSS（图片 / 语音 / 文件中转）

## 文件说明

| 文件 | 用途 |
|---|---|
| `clawhub-architecture.svg` | 矢量源文件（可编辑） |
| `clawhub-architecture.png` | 渲染好的位图（1600×1143，便于贴文档/PPT） |

## 关键数据流

详见架构图底部"关键数据流"区，三条主链路：

1. **发送** — App → WS Server → Auth → Router → WS Client → Gateway → LLM
2. **接收** — LLM → Gateway → WS Client → History Writer (落 MySQL) → Router → WS Server → App
3. **多 Agent 路由** — Session Manager 维护映射

## 实现路径（M0 → M3）

- **M0** — Flutter App 直连 Gateway（当前，已跑通）
- **M1** — 抽最小后端，仅协议代理 + 鉴权中转
- **M2** — 加历史持久化 + 多 agent 路由
- **M3** — 加聚合 / 缓存 / 限流，开放给其他客户端

## 修订记录

- 2026-06-29 — 初版 v2 草案（自建后端方案）
