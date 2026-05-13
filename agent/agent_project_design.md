# Agent 项目设计文档

> 基于 Claude Agent SDK Python 构建多用户 Agent 应用平台
>
> 文档版本：v2.1
> 日期：2026-05-12

---

## 目录

1. [项目概述](#1-项目概述)
2. [技术选型](#2-技术选型)
3. [整体架构设计](#3-整体架构设计)
4. [用户系统设计](#4-用户系统设计)
5. [Session 管理设计](#5-session-管理设计)
6. [前端页面设计](#6-前端页面设计)
7. [后端 API 设计](#7-后端-api设计)
8. [模型配置设计](#8-模型配置设计)
9. [工具系统设计](#9-工具系统设计)
   - 9.1 工具来源
   - 9.2 工具权限设计
   - 9.3 工具权限数据模型
   - 9.4 工具权限检查流程
   - 9.5 实际场景示例
   - 9.6 前端确认框设计
   - 9.7 工具权限配置 API
10. [项目目录结构](#10-项目目录结构)
11. [数据库设计](#11-数据库设计)
12. [实施计划](#12-实施计划)

---

## 1. 项目概述

### 1.1 项目目标

构建一个多用户 Agent 应用平台，包含：

- **用户聊天页面**：多轮对话、历史 Session 查看
- **后台设置页面**：模型配置、工具权限配置
- **多用户系统**：用户隔离、Session 管理
- **Agent 能力**：智能对话、工具调用

### 1.2 核心功能模块

```mermaid
graph TB
    subgraph FRONTEND["前端"]
        CHAT["聊天页面<br/>对话 / Session 历史"]
        SETTINGS["后台设置<br/>模型 / 工具权限"]
    end

    subgraph BACKEND["后端"]
        API["API 服务"]
        USER["用户系统"]
        SESSION["Session 管理"]
        AGENT["Agent 引擎"]
        CONFIG["配置管理"]
    end

    subgraph DATABASE["数据层"]
        DB["MySQL<br/>用户 / Session / 配置"]
        STORE["Session Store<br/>对话内容"]
    end

    FRONTEND --> API
    API --> USER
    API --> SESSION
    API --> AGENT
    API --> CONFIG
    USER --> DB
    SESSION --> DB
    SESSION --> STORE
    CONFIG --> DB
    AGENT --> SDK["Claude Agent SDK"]
```

### 1.3 用户角色

| 角色 | 权限 | 功能 |
|------|------|------|
| 普通用户 | 聊天、查看自己的 Session | 聊天页面 |
| 管理员 | 后台设置、用户管理、配置管理 | 聊天页面 + 后台设置页面 |

### 1.4 技术栈

| 层级 | 技术 | 版本 | 说明 |
|------|------|------|------|
| **前端** | React | 18+ | 用户界面 |
| | Ant Design | 5+ | UI 组件库 |
| | TypeScript | 5+ | 类型安全 |
| **后端** | Python | 3.10+ | 运行环境 |
| | FastAPI | 0.100+ | API 框架 |
| | Claude Agent SDK | 0.1.80+ | Agent 核心 |
| **数据层** | MySQL | 8.0+ | Session/用户/配置 元数据 |
| | Redis | 7+ | Session 内容缓存 |
| **部署** | Docker | - | 容器化 |

---

## 2. 技术选型

### 2.1 前端选型

| 技术 | 选择理由 |
|------|----------|
| React | 社区成熟、组件丰富、适合聊天 UI |
| Ant Design | 企业级 UI、完整组件库、后台页面友好 |
| WebSocket | 实时通信、流式消息展示 |
| Zustand | 轻量状态管理 |

### 2.2 后端选型

| 技术 | 选择理由 |
|------|----------|
| FastAPI | 高性能、原生 async、自动 API 文档 |
| Claude Agent SDK | 官方 SDK、完整 Agent 能力 |
| MySQL | 关系型数据、用户/配置存储 |
| Redis | Session 缓存、实时状态 |

### 2.3 Claude Agent SDK 内置能力

**使用 SDK 后无需开发的能力：**

| 能力 | 说明 |
|------|------|
| 查询引擎 | `query()` 单次查询 + `ClaudeSDKClient` 多轮对话 |
| 内置工具 | 30+ 工具（Bash, Read, Write, Edit, WebSearch, WebFetch...） |
| MCP 协议 | 外部 MCP Server 接入 + SDK MCP Server（in-process） |
| Hooks 系统 | PreToolUse, PostToolUse, Stop, Notification 等 |
| 权限模式 | default, acceptEdits, plan, bypassPermissions, auto |
| 会话管理 | SessionStore API、会话恢复 |
| 上下文压缩 | Auto Compact 自动压缩 |
| Prompt Cache | 自动缓存优化 |
| 多模型支持 | 动态切换模型 |

---

## 3. 整体架构设计

### 3.1 系统架构图

```mermaid
flowchart TB
    subgraph CLIENT["客户端"]
        WEB["Web 浏览器"]
        MOBILE["移动端（可选）"]
    end

    subgraph FRONTEND["前端应用"]
        REACT["React App"]
        CHAT_UI["聊天页面"]
        SETTINGS_UI["后台设置页面"]
        WS["WebSocket Client"]
    end

    subgraph BACKEND["后端服务"]
        FASTAPI["FastAPI Server"]
        
        subgraph API_MODULES["API 模块"]
            AUTH_API["认证 API"]
            CHAT_API["聊天 API"]
            SESSION_API["Session API"]
            CONFIG_API["配置 API"]
            USER_API["用户 API"]
        end
        
        subgraph CORE_MODULES["核心模块"]
            USER_MGR["用户管理"]
            SESSION_MGR["Session 管理"]
            AGENT_MGR["Agent 管理"]
            CONFIG_MGR["配置管理"]
        end
    end

    subgraph AGENT_ENGINE["Agent 引擎"]
        SDK["Claude Agent SDK"]
        TOOLS["自定义工具"]
        HOOKS["业务 Hooks"]
    end

    subgraph DATA["数据层"]
        MYSQL["MySQL<br/>用户/配置"]
        REDIS["Redis<br/>Session 缓存"]
        FILE["文件存储<br/>Session 内容"]
    end

    subgraph EXTERNAL["外部服务"]
        ANTHROPIC["Anthropic API"]
        MCP["MCP Servers"]
    end

    CLIENT --> FRONTEND
    FRONTEND --> WS
    WS --> FASTAPI
    
    FASTAPI --> API_MODULES
    API_MODULES --> CORE_MODULES
    
    CORE_MODULES --> DATA
    AGENT_MGR --> SDK
    SDK --> ANTHROPIC
    SDK --> MCP
```

### 3.2 核心数据流

```mermaid
sequenceDiagram
    participant User as 用户
    participant Frontend as 前端
    participant API as FastAPI
    participant SessionMgr as Session管理
    participant Agent as Agent引擎
    participant SDK as Claude SDK
    participant DB as 数据库

    User->>Frontend: 打开聊天页面
    Frontend->>API: GET /api/sessions (获取历史)
    API->>SessionMgr: 查询用户 Sessions
    SessionMgr->>DB: 查询数据库
    DB-->>SessionMgr: Session 列表
    SessionMgr-->>API: Session 列表
    API-->>Frontend: JSON Response
    Frontend-->>User: 显示 Session 历史

    User->>Frontend: 发送消息
    Frontend->>API: WebSocket 连接
    Frontend->>API: 发送消息 (WS)
    API->>SessionMgr: 创建/恢复 Session
    API->>Agent: 启动 Agent
    Agent->>SDK: ClaudeSDKClient.query()
    
    loop 流式响应
        SDK-->>Agent: Message 流
        Agent-->>API: SSE/WS 流
        API-->>Frontend: 流式消息
        Frontend-->>User: 实时显示
    end
    
    Agent->>SessionMgr: 保存 Session
    SessionMgr->>DB: 持久化
```

### 3.3 核心组件职责

| 组件 | 职责 | 开发方 |
|------|------|--------|
| 前端应用 | 用户界面、WebSocket 通信 | 自研 |
| API 服务 | RESTful API、WebSocket 服务 | 自研 |
| 用户管理 | 用户 CRUD、认证、权限 | 自研 |
| Session 管理 | Session 元数据、内容存储 | 自研 |
| Agent 管理 | Agent 创建、配置、生命周期 | 自研 |
| 配置管理 | 模型、Agent、工具配置 | 自研 |
| Claude Agent SDK | Agent 核心、工具执行 | Anthropic |
| Claude Code CLI | QueryEngine、压缩、缓存 | Anthropic |

---

## 4. 用户系统设计

### 4.1 用户数据模型

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 用户唯一标识 |
| username | VARCHAR(50) | 用户名 |
| email | VARCHAR(100) | 邮箱 |
| password_hash | VARCHAR(255) | 密码（bcrypt加密） |
| role | VARCHAR(20) | 角色：user, admin |
| settings | JSON | 用户个人设置 |
| created_at | TIMESTAMP | 创建时间 |
| updated_at | TIMESTAMP | 更新时间 |

**用户个人设置（settings 字段）：**

| 设置项 | 说明 |
|------|------|
| default_model | 用户默认模型 |
| max_sessions | 最大 Session 数量 |

### 4.2 认证流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant Frontend as 前端
    participant API as API
    participant JWT as JWT 服务
    participant DB as 数据库

    User->>Frontend: 登录页面输入
    Frontend->>API: POST /api/auth/login
    API->>DB: 查询用户
    DB-->>API: 用户信息
    
    API->>API: 验证密码 (bcrypt)
    
    alt 密码正确
        API->>JWT: 生成 JWT Token
        JWT-->>API: Token
        API-->>Frontend: {token, user_info}
        Frontend->>Frontend: 存储 Token (localStorage)
        Frontend-->>User: 跳转到聊天页面
    else 密码错误
        API-->>Frontend: 401 错误
        Frontend-->>User: 显示错误信息
    end
```

### 4.3 认证 API 设计

| API | 方法 | 说明 |
|------|------|------|
| `/api/auth/login` | POST | 用户登录，返回 JWT Token |
| `/api/auth/register` | POST | 用户注册 |
| `/api/auth/logout` | POST | 用户登出 |
| `/api/auth/me` | GET | 获取当前用户信息 |
| `/api/auth/refresh` | POST | 刷新 Token |

---

## 5. Session 管理设计

### 5.1 核心概念：两种 Session

**用"书"的比喻来理解：**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     "聊天对话" 的两层信息                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  类比：一本书                                                            │
│                                                                         │
│  ┌─────────────────────┐        ┌─────────────────────────────┐        │
│  │  书的封面/目录       │        │  书的内容（正文）            │        │
│  │  (DB Session)       │        │  (SDK Session)              │        │
│  │                     │        │                             │        │
│  │  - 书名 → 对话标题   │        │  - 第1章 → 第1条消息        │        │
│  │  - 作者 → 用户      │        │  - 第2章 → 第2条消息        │        │
│  │  - 页数 → token数   │        │  - 第3章 → 第3条消息        │        │
│  │  - 分类 → Agent类型 │        │  ...                        │        │
│  │                     │        │                             │        │
│  │  存在：MySQL         │        │  存在：SessionStore         │        │
│  │                     │        │  (Redis/MySQL/文件)         │        │
│  │  用途：              │        │                             │        │
│  │  - 快速找书          │        │  用途：                      │        │
│  │  - 统计有多少书      │        │  - 阅读内容                 │        │
│  │  - 不打开就能看      │        │  - 继续阅读（恢复对话）     │        │
│  │    基本信息          │        │  - Agent 需要内容才能回答  │        │
│  └─────────────────────┘        └─────────────────────────────┘        │
│                                                                         │
│  关联方式：书的 ID = 内容的 ID（同一个标识）                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**两种 Session 的具体内容：**

| 类型 | 名称 | 存储位置 | 内容 | 用途 |
|------|------|----------|------|------|
| DB Session | 业务 Session | MySQL | session_id, title, model, tokens... | 用户查看历史列表、权限验证、成本统计 |
| SDK Session | Agent Session | SessionStore | messages, context... | Agent 对话上下文、会话恢复、消息持久化 |

### 5.2 SessionStore 的位置与实现

**SessionStore 与 SDK 的关系：**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SessionStore 的关系                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Claude Agent SDK                                                      │
│   ┌─────────────────────────────────────────────────────┐              │
│   │                                                     │              │
│   │   SDK 提供：                                        │              │
│   │   - SessionStore 接口定义（规定要实现哪些方法）      │              │
│   │   - 调用 SessionStore 的时机                        │              │
│   │                                                     │              │
│   │   接口方法：                                        │              │
│   │   ┌─────────────────────────────────────┐          │              │
│   │   │  save(messages, metadata)           │          │              │
│   │   │  load() → messages, metadata        │          │              │
│   │   └─────────────────────────────────────┘          │              │
│   │              ↑                                    │              │
│   │              │ 我们自己实现                        │              │
│   │              │                                    │              │
│   │   我们实现：                                       │              │
│   │   ┌─────────────────────────────────────┐          │              │
│   │   │  MySQLSessionStore                  │          │              │
│   │   │  - save(): 存到我们选择的位置       │          │              │
│   │   │  - load(): 从我们选择的位置读       │          │              │
│   │   └─────────────────────────────────────┘          │              │
│   │                                                     │              │
│   │   SDK 运行时自动调用：                              │              │
│   │   - 每轮对话结束 → 调用 save()                     │              │
│   │   - 启动 Agent → 调用 load()                      │              │
│   │                                                     │              │
│   └─────────────────────────────────────────────────────┘              │
│                                                                         │
│   我们传给 SDK：                                                         │
│   ClaudeSDKClient(session_store=我们实现的SessionStore)                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**一句话总结：**

> SessionStore 的"规则"在 SDK 里（接口定义），"具体怎么存"由我们实现。SDK 在需要保存/加载消息时，会自动调用我们写的代码。

### 5.3 SessionStore 存储位置选择

**可以存到哪里：**

| 存储位置 | 适合场景 | 性能 | 成本 | 复杂度 |
|----------|----------|------|------|--------|
| **Redis** | 活跃对话（正在进行） | 最快 | 高（内存） | 低 |
| **MySQL** | 持久化存储 | 中 | 低 | 中 |
| **文件系统** | 大量历史对话 | 慢 | 最低 | 中 |
| **组合方案** | 推荐 | 快+持久 | 中 | 中 |

**各方案对比：**

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| 全存 MySQL | Session 内容存到 MySQL 的 JSON 字段 | 简单、可查询、持久化 | 频繁写入可能慢、表会变大 |
| 全存 Redis | Session 内容存到 Redis | 最快、适合频繁更新 | 内存成本高、需设置过期 |
| Redis + 文件 | 活跃存 Redis，历史存文件 | 快+持久+低成本 | 需管理两个存储 |
| Redis + MySQL | 活跃存 Redis，历史存 MySQL | 快+持久+可查询 | 需管理两个存储 |

### 5.4 推荐方案

```
┌─────────────────────────────────────────────────────────────────┐
│                      推荐的组合方案                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Session 元数据 → MySQL                                         │
│  - session_id, title, user_id, tokens, cost                    │
│  - 查询列表、统计、权限验证                                       │
│                                                                 │
│  Session 内容 → Redis + MySQL/文件                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  活跃对话 → Redis                                        │   │
│  │  - 正在进行的对话                                         │   │
│  │  - 读写最快                                               │   │
│  │  - 设置过期时间（如 24 小时）                              │   │
│  │                                                         │   │
│  │  历史对话 → MySQL/文件                                    │   │
│  │  - Redis 过期后迁移到这里                                 │   │
│  │  - 持久保存                                               │   │
│  │  - 成本更低                                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  简化方案：全存 MySQL                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  如果对话量不大，可直接全存 MySQL                          │   │
│  │  - 新增 sessions_content 表                              │   │
│  │  - 字段：session_id, messages(JSON), updated_at          │   │
│  │  - 架构简单，少依赖                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.5 Session 关联流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant API as API
    participant DB as MySQL
    participant Store as SessionStore
    participant SDK as Claude SDK

    User->>API: 点击"新建对话"
    API->>DB: INSERT sessions (user_id...)
    DB-->>API: session_id = "abc-123"
    
    Note over API,Store: DB Session 创建完成，获得 session_id

    User->>API: 发送消息 (session_id="abc-123")
    API->>DB: SELECT sessions WHERE id="abc-123"
    DB-->>API: Session 元数据
    
    API->>Store: 创建 SessionStore("abc-123")
    Note over Store: 用 DB session_id 作为 SessionStore 的标识
    
    API->>SDK: ClaudeSDKClient(session_store=Store)
    SDK->>Store: load() 加载历史消息
    Store-->>SDK: messages=[] (新Session为空)
    
    SDK->>SDK: 执行对话
    
    SDK->>Store: save(messages) 保存
    Note over Store: SDK 每轮对话后自动调用 save
    
    API->>DB: UPDATE sessions (tokens, cost)
```

### 5.6 Session 数据模型

**MySQL Session 表（元数据）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | VARCHAR(36) | Session ID，关联 SessionStore |
| user_id | VARCHAR(36) | 所属用户 |
| title | VARCHAR(200) | Session 标题 |
| model | VARCHAR(50) | 使用的模型 |
| agent_type | VARCHAR(50) | Agent 类型 |
| status | VARCHAR(20) | 状态：active, archived, deleted |
| total_input_tokens | INT | 输入 token 统计 |
| total_output_tokens | INT | 输出 token 统计 |
| total_cost | DECIMAL | 成本统计 |
| created_at | TIMESTAMP | 创建时间 |
| updated_at | TIMESTAMP | 更新时间 |

**SessionStore 存储内容：**

| 内容 | 说明 |
|------|------|
| session_id | 与 MySQL sessions.id 相同（关联标识） |
| messages | 对话消息列表（每条消息的完整内容） |
| context | 对话上下文信息 |
| metadata | token 统计、成本等 |

### 5.7 实际使用场景

**场景1：用户查看历史列表**

```
用户打开聊天页面
    ↓
系统查询 MySQL sessions 表
    ↓
返回对话列表（只返回元数据，不加载内容）
    ↓
用户看到：
    1. 研究React - 昨天 - 2000 tokens
    2. 写HTTP服务 - 3天前 - 1500 tokens
    ...
    
（这一步不需要 SessionStore，只查 MySQL）
```

**场景2：用户进入某个对话**

```
用户点击"研究React"
    ↓
系统用 session_id="abc-123" 创建 SessionStore
    ↓
SessionStore.load() 加载消息内容
    ↓
用户看到完整对话记录（10轮对话）
    
（这一步需要 SessionStore 加载内容）
```

**场景3：用户继续对话**

```
用户发送新消息："再写一个示例"
    ↓
Agent 用 SessionStore.load() 获取历史上下文
    ↓
Agent 看到之前的 React 讨论，理解上下文
    ↓
Agent 回复："好的，基于刚才讨论的特性..."
    ↓
SessionStore.save() 保存新消息
    ↓
MySQL 更新 token 统计
```

### 5.8 Session API 设计

| API | 方法 | 说明 |
|------|------|------|
| `/api/sessions` | GET | 获取用户 Session 列表（只返回元数据） |
| `/api/sessions` | POST | 创建新 Session |
| `/api/sessions/{id}` | GET | 获取 Session 详情（含消息内容） |
| `/api/sessions/{id}` | DELETE | 删除 Session |
| `/api/sessions/{id}/title` | PATCH | 更新标题 |
| `/api/sessions/{id}/archive` | PATCH | 归档 Session |

---

## 6. 前端页面设计

### 6.1 页面结构

```
前端页面：
├── 登录/注册页面
│
├── 聊天页面（主页面）
│   ├── Header：用户信息、设置入口
│   ├── Sidebar：Session 历史列表
│   ├── ChatArea：消息区域
│   │   ├── 消息列表（用户/助手消息）
│   │   ├── 工具调用展示
│   │   └── 流式输出动画
│   └── InputArea：输入框、发送按钮
│
└── 后台设置页面（管理员）
    ├── 用户管理
    ├── 工具权限配置
    ├── 模型配置
    └── 系统设置
```

### 6.2 聊天页面布局

```
+--------------------------------------------------+
|  Header: Logo | 用户名 | 设置按钮 |               |
+--------------------------------------------------+
|          |                                       |
| Sidebar  |         Chat Area                     |
|          |                                       |
| Session  |  +-------------------------------+   |
| 历史列表 |  | 用户消息                      |   |
|          |  +-------------------------------+   |
| [新建]   |                                       |
|          |  +-------------------------------+   |
| Session1 |  | Agent 回复（流式）            |   |
| Session2 |  | - 文本内容                    |   |
| Session3 |  | - 工具调用 [展开]             |   |
| ...      |  +-------------------------------+   |
|          |                                       |
|          |  +-------------------------------+   |
|          |  | 输入框 | 发送                  |   |
|          |  +-------------------------------+   |
+--------------------------------------------------+
```

### 6.3 消息类型渲染

| 消息类型 | 渲染方式 |
|----------|----------|
| 用户消息 | 简单文本，右侧显示 |
| 助手文本 | Markdown 渲染，左侧显示，流式动画 |
| Tool Use | 可折叠卡片，显示工具名、参数 |
| Tool Result | 可折叠卡片，显示执行结果 |
| Thinking | 隐藏或可展开的思考过程 |
| Error | 红色高亮错误信息 |

### 6.4 后台设置页面

**页面结构：**

| 页面 | 功能 |
|------|------|
| 用户管理 | 用户列表、添加/编辑用户、更改角色 |
| 工具权限配置 | 工具列表、编辑权限、设置确认要求 |
| 模型配置 | 可用模型列表、默认模型 |
| 系统设置 | API Key、成本监控 |

**工具权限配置页面：**

```
+--------------------------------------------------+
|  工具权限配置                                      |
+--------------------------------------------------+
|                                                  |
|  +--------------------------------------------+  |
|  | 工具名称 | 允许角色 | 需确认 | 启用 | 操作   |  |
|  +--------------------------------------------+  |
|  | Bash    | admin   | ✓     | ✓   | [编辑]  |  |
|  | Read    | all     | ✗     | ✓   | [编辑]  |  |
|  | Write   | admin   | ✓     | ✓   | [编辑]  |  |
|  | Edit    | admin   | ✓     | ✓   | [编辑]  |  |
|  | WebSearch| all    | ✗     | ✓   | [编辑]  |  |
|  | WebFetch | all    | ✗     | ✓   | [编辑]  |  |
|  +--------------------------------------------+  |
|                                                  |
|  说明：                                           |
|  - admin = 管理员                                 |
|  - all = 所有角色（user, admin）                  |
|  - 需确认 = 执行前需要用户点击确认                 |
|                                                  |
+--------------------------------------------------+
```

**编辑工具权限弹窗：**

```
+--------------------------------------------------+
|  编辑工具权限 - Bash                              |
+--------------------------------------------------+
|                                                  |
|  工具名称：Bash                                   |
|  描述：执行 Shell 命令                            |
|                                                  |
|  允许的角色：                                     |
|  [ ] 普通用户 (user)                              |
|  [✓] 管理员 (admin)                               |
|                                                  |
|  执行前需要确认：[✓]                              |
|                                                  |
|  启用此工具：[✓]                                  |
|                                                  |
|  [保存]  [取消]                                   |
+--------------------------------------------------+
```

---

## 7. 后端 API 设计

### 7.1 API 模块划分

| 模块 | 路径前缀 | 功能 |
|------|----------|------|
| 认证 | `/api/auth` | 登录、注册、Token 验证 |
| 用户 | `/api/users` | 用户 CRUD、权限管理 |
| Session | `/api/sessions` | Session 管理、历史查询 |
| 聊天 | `/api/chat` | WebSocket、消息发送 |
| 配置 | `/api/config` | 模型、工具配置 |

### 7.2 API 详细列表

**认证 API：**

| API | 方法 | 说明 |
|------|------|------|
| `/api/auth/login` | POST | 登录 |
| `/api/auth/register` | POST | 注册 |
| `/api/auth/logout` | POST | 登出 |
| `/api/auth/me` | GET | 获取当前用户 |
| `/api/auth/refresh` | POST | 刷新 Token |

**用户 API（管理员）：**

| API | 方法 | 说明 |
|------|------|------|
| `/api/users` | GET | 用户列表 |
| `/api/users` | POST | 创建用户 |
| `/api/users/{id}` | GET | 用户详情 |
| `/api/users/{id}` | PUT | 更新用户 |
| `/api/users/{id}` | DELETE | 删除用户 |
| `/api/users/{id}/role` | PUT | 更改角色 |

**Session API：**

| API | 方法 | 说明 |
|------|------|------|
| `/api/sessions` | GET | Session 列表（当前用户） |
| `/api/sessions` | POST | 创建 Session |
| `/api/sessions/{id}` | GET | Session 详情（含消息） |
| `/api/sessions/{id}` | DELETE | 删除 Session |
| `/api/sessions/{id}/title` | PATCH | 更新标题 |
| `/api/sessions/{id}/archive` | PATCH | 归档 |

**聊天 API：**

| API | 方法 | 说明 |
|------|------|------|
| `/api/ws/{session_id}` | WebSocket | WebSocket 连接 |
| `/api/chat/{session_id}/message` | POST | 发送消息（HTTP 备用） |
| `/api/chat/{session_id}/stream` | GET | SSE 流（备用） |

**配置 API：**

| API | 方法 | 说明 |
|------|------|------|
| `/api/config/models` | GET | 获取可用模型列表 |
| `/api/config/models` | PUT | 更新模型配置 |
| `/api/config/default-model` | GET/PUT | 默认模型 |
| `/api/config/tools` | GET | 获取所有工具配置 |
| `/api/config/tools/{name}` | GET | 获取单个工具配置 |
| `/api/config/tools/{name}` | PUT | 更新工具权限配置 |
| `/api/config/tools/{name}/enable` | PATCH | 启用/禁用工具 |
| `/api/config/mcp-servers` | GET/POST | MCP Server 配置 |

---

## 8. 模型配置设计

### 8.1 模型配置数据模型

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 配置 ID |
| name | VARCHAR(50) | 模型名称（claude-opus-4-6） |
| display_name | VARCHAR(100) | 显示名称（Claude Opus 4） |
| is_enabled | BOOLEAN | 是否启用 |
| default_temperature | DECIMAL | 默认温度 |
| max_output_tokens | INT | 最大输出 tokens |
| input_cost_per_1k | DECIMAL | 输入成本 |
| output_cost_per_1k | DECIMAL | 输出成本 |
| allowed_roles | JSON | 允许的角色列表 |

### 8.2 模型配置功能

| 功能 | 说明 |
|------|------|
| 模型列表 | 管理员配置可用模型 |
| 默认模型 | 系统默认 + 用户个人默认 |
| 权限控制 | 不同角色可用不同模型 |
| 成本显示 | 显示各模型成本信息 |

### 8.3 模型选择流程

```mermaid
flowchart TD
    START["用户发起对话"] --> CHECK_USER["检查用户个人设置"]
    
    CHECK_USER --> HAS_DEFAULT{"有个人默认模型?"}
    HAS_DEFAULT -->|"是"| USER_MODEL["使用用户默认模型"]
    HAS_DEFAULT -->|"否"| CHECK_SYSTEM["获取系统默认模型"]
    
    CHECK_SYSTEM --> CHECK_ROLE{"角色允许该模型?"}
    CHECK_ROLE -->|"是"| FINAL["使用该模型"]
    CHECK_ROLE -->|"否"| FALLBACK["使用 fallback 模型"]
    
    USER_MODEL --> CHECK_ROLE2{"角色允许该模型?"}
    CHECK_ROLE2 -->|"是"| FINAL
    CHECK_ROLE2 -->|"否"| CHECK_SYSTEM
    
    FINAL --> CREATE["创建 Agent"]
```

---

## 9. 工具系统设计

### 9.1 工具来源

| 来源 | 说明 |
|------|------|
| SDK 内置 | 30+ 工具（Bash, Read, Write, Edit, WebSearch...） |
| 自定义工具 | SDK MCP Server（in-process） |
| 外部 MCP Server | 配置的外部 MCP 服务 |

### 9.2 工具权限设计

**权限设计简化：**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          只需要工具权限                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  其他权限（不需要后台配置，用代码固定）：                                   │
│  ─────────────────────────────────────────────────────────────────────  │
│  用户角色权限 → 固定                                                      │
│  - 普通用户：聊天、查看自己的 Session                                      │
│  - 管理员：后台设置、用户管理                                              │
│                                                                         │
│  数据权限 → 固定                                                          │
│  - 用户只能看到自己的 Session                                              │
│  - 管理员可以看到所有用户                                                  │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  工具权限（需要后台配置）：                                                │
│  ─────────────────────────────────────────────────────────────────────  │
│  - 哪些工具允许哪些角色使用                                                │
│  - 是否需要用户确认才能执行                                                │
│  - 可以随时在后台修改                                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 9.3 工具权限数据模型

**tool_configs 表：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | VARCHAR(36) | 配置 ID |
| name | VARCHAR(50) | 工具名称 |
| description | TEXT | 描述 |
| is_builtin | BOOLEAN | 是否内置工具 |
| is_enabled | BOOLEAN | 是否启用 |
| allowed_roles | JSON | 允许的角色，如 `["user", "admin"]` |
| requires_confirmation | BOOLEAN | 执行前是否需要用户确认 |

**示例数据：**

| name | allowed_roles | requires_confirmation | is_enabled |
|------|---------------|----------------------|------------|
| Bash | ["admin"] | true | true |
| Read | ["user", "admin"] | false | true |
| Write | ["admin"] | true | true |
| Edit | ["admin"] | true | true |
| WebSearch | ["user", "admin"] | false | true |
| WebFetch | ["user", "admin"] | false | true |

### 9.4 工具权限检查流程

```mermaid
flowchart TD
    AGENT["Agent 决定执行工具"] --> CHECK["检查工具权限配置"]
    
    CHECK --> ENABLED{"工具启用?"}
    ENABLED -->|"否"| DENY1["拒绝：工具已禁用"]
    ENABLED -->|"是"| ROLE{"用户角色在<br/>allowed_roles 中?"}
    
    ROLE -->|"否"| DENY2["拒绝：无权限<br/>告诉用户此工具需要更高权限"]
    ROLE -->|"是"| CONFIRM{"需要确认?"}
    
    CONFIRM -->|"否"| EXECUTE["直接执行工具"]
    CONFIRM -->|"是"| ASK["前端弹出确认框"]
    
    ASK --> USER{"用户选择"}
    USER -->|"允许"| EXECUTE
    USER -->|"拒绝"| DENY3["拒绝：用户取消"]
```

### 9.5 实际场景示例

**场景1：普通用户使用 Read 工具**

```
用户角色：user
工具：Read
配置：allowed_roles = [user, admin]
      requires_confirmation = false

流程：
Agent 决定执行 Read
    ↓
检查工具配置
    ↓
user 在 allowed_roles 中？ → 是
    ↓
需要确认？ → 否
    ↓
直接执行

结果：成功执行
```

**场景2：普通用户使用 Bash 工具**

```
用户角色：user
工具：Bash
配置：allowed_roles = [admin]
      requires_confirmation = true

流程：
Agent 决定执行 Bash
    ↓
检查工具配置
    ↓
user 在 allowed_roles 中？ → 否

结果：拒绝执行，提示 "您没有权限使用此工具，此工具需要管理员权限"
```

**场景3：管理员使用 Bash 工具**

```
用户角色：admin
工具：Bash
配置：allowed_roles = [admin]
      requires_confirmation = true

流程：
Agent 决定执行 Bash
    ↓
检查工具配置
    ↓
admin 在 allowed_roles 中？ → 是
    ↓
需要确认？ → 是
    ↓
前端弹出确认框："Agent 想要执行命令: ls -la，是否允许？"
    ↓
用户点击"允许"
    ↓
执行工具

结果：成功执行
```

### 9.6 前端确认框设计

当工具需要确认时，前端弹出确认框：

```
+--------------------------------------------------+
|  ⚠️ 工具执行确认                                   |
+--------------------------------------------------+
|                                                  |
|  Agent 想要执行以下工具：                          |
|                                                  |
|  工具：Bash                                       |
|  内容：rm -rf /tmp/test                          |
|                                                  |
|  +--------------------------------------------+  |
|  |  [✓] 记住此选择，本次对话不再询问            |  |
|  +--------------------------------------------+  |
|                                                  |
|  [允许执行]  [拒绝]                               |
+--------------------------------------------------+
```

**确认框显示内容：**

| 工具 | 显示内容 |
|------|----------|
| Bash | 显示要执行的命令 |
| Read | 显示要读取的文件路径 |
| Write | 显示要写入的文件路径 |
| Edit | 显示 old_string 和 new_string 的摘要 |
| WebFetch | 显示 URL |

### 9.7 工具权限配置 API

| API | 方法 | 说明 |
|------|------|------|
| `/api/config/tools` | GET | 获取所有工具配置列表 |
| `/api/config/tools/{name}` | GET | 获取单个工具配置 |
| `/api/config/tools/{name}` | PUT | 更新工具权限配置 |
| `/api/config/tools/{name}/enable` | PATCH | 启用/禁用工具 |

---

## 10. 项目目录结构

```
agent_platform/
├── frontend/                    # 前端应用
│   ├── src/
│   │   ├── pages/               # 页面组件
│   │   ├── components/          # 公共组件
│   │   ├── hooks/               # React Hooks
│   │   ├── stores/              # 状态管理
│   │   ├── services/            # API 服务
│   │   ├── types/               # TypeScript 类型
│   │   ├── App.tsx
│   │   └── main.tsx
│   ├── package.json
│   └── vite.config.ts
│
├── backend/                     # 后端服务
│   ├── api/                     # API 路由
│   ├── models/                  # 数据模型
│   ├── services/                # 业务服务
│   ├── core/                    # 核心模块
│   ├── tools/                   # 自定义工具
│   ├── hooks/                   # 业务 Hooks
│   ├── migrations/              # 数据库迁移
│   ├── main.py                  # 入口
│   └── requirements.txt
│
├── docker/                      # Docker 配置
│   ├── docker-compose.yml
│   ├── frontend.Dockerfile
│   ├── backend.Dockerfile
│   └── nginx.conf
│
├── docs/                        # 文档
│   ├── api.md
│   ├── frontend.md
│   └── deployment.md
│
├── scripts/                     # 脚本
│   ├── init_db.py
│   └── seed_data.py
│
└── README.md
```

---

## 11. 数据库设计（MySQL）

### 11.1 数据表概览

| 表名 | 说明 |
|------|------|
| users | 用户表 |
| sessions | Session 元数据表 |
| model_configs | 模型配置表 |
| tool_configs | 工具配置表 |
| mcp_servers | MCP Server 配置表 |
| system_config | 系统配置表 |

### 11.2 Session 存储架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    Session 存储架构                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  数据类型           存储位置           用途                      │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Session 元数据      MySQL              用户历史列表              │
│  - id, title       sessions表         权限验证                  │
│  - model, type                        成本统计                  │
│  - token统计                                                   │
│                                                                 │
│  Session 消息内容    Redis + 文件       Agent 对话上下文          │
│  - messages        (SessionStore)      会话恢复                  │
│  - context                            消息持久化                │
│                                                                 │
│  关联方式:                                                       │
│  MySQL sessions.id = SessionStore.session_id                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 11.3 数据表字段设计

**用户表：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | VARCHAR(36) | UUID |
| username | VARCHAR(50) | 用户名 |
| email | VARCHAR(100) | 邮箱 |
| password_hash | VARCHAR(255) | 密码哈希 |
| role | VARCHAR(20) | 角色：user, admin |
| settings | JSON | 个人设置 |
| created_at | TIMESTAMP | 创建时间 |
| updated_at | TIMESTAMP | 更新时间 |

**Session 表 (sessions)：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | VARCHAR(36) | Session ID（关联 SDK） |
| user_id | VARCHAR(36) | 用户 ID |
| title | VARCHAR(200) | 标题 |
| model | VARCHAR(50) | 模型 |
| status | VARCHAR(20) | 状态 |
| total_input_tokens | INT | 输入 tokens |
| total_output_tokens | INT | 输出 tokens |
| total_cost | DECIMAL(10,4) | 成本 |
| created_at | TIMESTAMP | 创建时间 |
| updated_at | TIMESTAMP | 更新时间 |

**模型配置表 (model_configs)：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | VARCHAR(36) | UUID |
| name | VARCHAR(50) | 模型名 |
| display_name | VARCHAR(100) | 显示名 |
| is_enabled | BOOLEAN | 是否启用 |
| default_temperature | DECIMAL(3,2) | 温度 |
| max_output_tokens | INT | 最大 tokens |
| input_cost_per_1k | DECIMAL(10,4) | 输入成本 |
| output_cost_per_1k | DECIMAL(10,4) | 输出成本 |

**工具配置表 (tool_configs)：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | VARCHAR(36) | UUID |
| name | VARCHAR(50) | 工具名 |
| description | TEXT | 描述 |
| is_builtin | BOOLEAN | 是否内置 |
| is_enabled | BOOLEAN | 是否启用 |
| allowed_roles | JSON | 允许角色 |
| requires_confirmation | BOOLEAN | 需确认 |
| mcp_server | VARCHAR(50) | MCP 来源 |

**MCP Server 配置表 (mcp_servers)：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | VARCHAR(36) | UUID |
| name | VARCHAR(50) | Server 名 |
| command | TEXT | 启动命令 |
| args | JSON | 参数 |
| env | JSON | 环境变量 |
| is_enabled | BOOLEAN | 是否启用 |

---

## 12. 实施计划

### 12.1 开发阶段（总计 6 周）

| 阶段 | 时间 | 任务 | 产出 |
|------|------|------|------|
| Phase 1 | 第 1 周 | 后端基础 + 用户系统 | 用户认证 API、数据库 |
| Phase 2 | 第 2 周 | Session 管理 + Agent 核心 | Session API、Agent 引擎 |
| Phase 3 | 第 3 周 | 前端聊天页面 | 聊天 UI、WebSocket |
| Phase 4 | 第 4 周 | 前端后台设置页面 | 工具权限配置 UI |
| Phase 5 | 第 5 周 | 自定义工具 + Hooks | 业务工具集成 |
| Phase 6 | 第 6 周 | 测试 + 部署 | 完整系统上线 |

### 12.2 验收标准

| 标准 | 要求 |
|------|------|
| 多用户支持 | 用户注册/登录、角色权限、配置隔离 |
| 聊天功能 | 多轮对话、流式输出、Session 历史 |
| 后台配置 | 工具权限配置、模型配置、用户管理 |
| 数据持久化 | Session 存储、配置存储、用户数据 |
| 安全认证 | JWT 认证、权限控制、数据隔离 |
| 性能 | WebSocket 流式响应 < 100ms |

---

## 附录：参考资料

1. [Claude Agent SDK Python](https://github.com/anthropics/claude-agent-sdk-python)
2. [Claude Agent SDK Demos](https://github.com/anthropics/claude-agent-sdk-demos)
3. [Agent SDK Workshop](https://github.com/anthropics/agent-sdk-workshop)
4. [FastAPI 文档](https://fastapi.tiangolo.com/)
5. [React 文档](https://react.dev/)
6. [Ant Design 文档](https://ant.design/)
7. Claude Code 源码调研：`/data/caidanfeng/project/doc/md-doc/agent/claude-code-research/0_code_flow.md`