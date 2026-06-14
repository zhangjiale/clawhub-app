# ClawHub (虾Hub) — 文档索引

## 目录结构

```
docs/
├── README.md                    # 本文件
├── product/                     # 产品文档
│   ├── prd.md                   # 产品需求文档 (PRD)
│   └── user-stories.md          # 用户故事地图与 Sprint 规划
├── design/                      # 设计规范
│   ├── design-tokens.md         # Design Token 规范 (色彩/字体/间距/圆角/阴影/动效)
│   ├── component-spec.md        # 组件标注与交互规范
│   └── assets/                  # 设计资源 (App 图标 / 启动屏 / 虾状态图)
├── technical/                   # 技术文档
│   ├── api-protocol.md          # OpenClaw Gateway WebSocket 协议规格书
│   ├── architecture.md          # 技术架构与组件拆解 (含技术选型、数据模型、Provider清单)
│   └── database-schema.sql      # SQLite 数据库 Schema (Zero-Trigger 设计)
├── engineering/                 # 工程规范
│   └── iron-laws.md             # 17 条不可违背的编码铁律 + Code Review 检查清单
├── prototypes/                  # 设计原型
│   └── premium-demo.html        # Premium 暗色主题 HTML 原型 (所有 Design Token 的来源)
└── archive/                     # 历史归档
    ├── 架构设计5.1.md            # 早期架构设计文档 (已被 architecture.md 取代)
    ├── 架构补充.txt              # 去触发器化重构笔记 (已融入 database-schema.sql)
    └── superpowers/             # 历史实施计划与设计文档
```

## 快速导航

| 我想... | 看这个 |
|---------|--------|
| 理解产品要做什么 | `product/prd.md` |
| 了解开发排期和 Story 拆分 | `product/user-stories.md` |
| 查看 UI 颜色/字体/间距定义 | `design/design-tokens.md` |
| 查看每个页面的组件标注 | `design/component-spec.md` |
| 理解 WebSocket 协议和认证流程 | `technical/api-protocol.md` |
| 了解技术选型和项目结构 | `technical/architecture.md` |
| 查看数据库表结构 | `technical/database-schema.sql` |
| 了解编码规范 | `engineering/iron-laws.md` |
| 看原始设计原型 | `prototypes/premium-demo.html` |

## 文档关系

```
PRD → UserStory → Architecture
                    ├── API Protocol (WebSocket)
                    ├── Database Schema
                    └── Iron Laws (编码规范)

HTML Prototype → Design Tokens → Component Spec
                                    └── Flutter Widgets (代码中注释引用)
```
