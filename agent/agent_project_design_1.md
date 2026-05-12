# Agent 项目设计文档

> 基于 Claude Agent SDK Python 构建多用户 Agent 应用平台
>
> 文档版本：v2.0
> 日期：2026-05-12

---

## 目录

1. [项目概述](#1-项目概述)
2. [技术选型](#2-技术选型)
3. [整体架构设计](#3-整体架构设计)
4. [用户系统设计](#4-用户系统设计)
5. [Session 管理设计](#5-session-管理设计)
6. [前端页面设计](#6-前端页面设计)
7. [后端 API 设计](#7-后端-api-设计)
8. [模型配置设计](#8-模型配置设计)
9. [Agent 模块设计](#9-agent-模块设计)
10. [工具系统设计](#10-工具系统设计)
11. [项目目录结构](#11-项目目录结构)
12. [数据库设计](#12-数据库设计)
13. [实施计划](#13-实施计划)

---

## 1. 项目概述

### 1.1 项目目标

构建一个多用户 Agent 应用平台，包含：

- **用户聊天页面**：多轮对话、历史 Session 查看
- **后台设置页面**：模型配置、权限管理、工具配置
- **多用户系统**：用户隔离、独立配置、Session 管理
- **Agent 能力**：智能对话、工具调用、多 Agent 协作

### 1.2 核心功能模块

```mermaid
graph TB
    subgraph FRONTEND["前端"]
        CHAT["聊天页面<br/>对话 / Session 历史"]
        SETTINGS["后台设置<br/>模型 / 权限 / 工具"]
    end

    subgraph BACKEND["后端"]
        API["API 服务"]
        USER["用户系统"]
        SESSION["Session 管理"]
        AGENT["Agent 引擎"]
        CONFIG["配置管理"]
    end

    subgraph DATABASE["数据层"]
        DB["数据库<br/>用户 / Session / 配置"]
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
| 管理员 | 所有配置 + 用户管理 | 后台设置页面 |
| 超级管理员 | 系统级配置 | 全部功能 |

### 1.4 技术栈

| 层级 | 技术 | 版本 | 说明 |
|------|------|------|------|
| **前端** | React | 18+ | 用户界面 |
| | Ant Design | 5+ | UI 组件库 |
| | TypeScript | 5+ | 类型安全 |
| **后端** | Python | 3.10+ | 运行环境 |
| | FastAPI | 0.100+ | API 框架 |
| | Claude Agent SDK | 0.1.80+ | Agent 核心 |
| **数据层** | PostgreSQL | 15+ | 主数据库 |
| | Redis | 7+ | Session 缓存 |
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
| PostgreSQL | 关系型数据、用户/配置存储 |
| Redis | Session 缓存、实时状态 |

### 2.3 Claude Agent SDK 优势

**SDK 内置能力（无需开发）：**

```
SDK 内置：
├── 查询引擎 (query() + ClaudeSDKClient)
├── 30+ 内置工具 (Bash, Read, Write, Edit, WebSearch...)
├── MCP 协议集成
├── Hooks 系统
├── 权限模式 (default/acceptEdits/plan/bypassPermissions)
├── 上下文压缩 (Auto Compact)
├── Prompt Cache
└── 多模型支持
```

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
        PG["PostgreSQL<br/>用户/配置"]
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

---

## 4. 用户系统设计

### 4.1 用户数据模型

```python
# models/user.py
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
import uuid

class User(BaseModel):
    """用户模型"""
    id: str = str(uuid.uuid4())
    username: str
    email: str
    password_hash: str  # bcrypt 加密
    role: str = "user"  # user, admin, super_admin
    created_at: datetime = datetime.utcnow()
    updated_at: datetime = datetime.utcnow()
    
    # 用户配置（可覆盖系统默认）
    settings: UserSettings = UserSettings()

class UserSettings(BaseModel):
    """用户个人设置"""
    default_model: str = "claude-sonnet-4-5"
    permission_mode: str = "default"
    allowed_tools: list[str] = []  # 用户可用的工具
    max_sessions: int = 100  # 最大 Session 数量
    max_tokens_per_session: int = 100000
```

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

### 4.3 认证 API

```python
# api/auth.py
from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import HTTPBearer
from pydantic import BaseModel

router = APIRouter(prefix="/api/auth", tags=["认证"])
security = HTTPBearer()

class LoginRequest(BaseModel):
    username: str
    password: str

class LoginResponse(BaseModel):
    token: str
    user: User
    expires_at: str

@router.post("/login", response_model=LoginResponse)
async def login(req: LoginRequest):
    """用户登录"""
    user = await get_user_by_username(req.username)
    if not user or not verify_password(req.password, user.password_hash):
        raise HTTPException(401, "用户名或密码错误")
    
    token = create_jwt_token(user.id)
    return LoginResponse(token=token, user=user, expires_at=get_expire_time())

@router.post("/register")
async def register(req: RegisterRequest):
    """用户注册"""
    # 检查用户名是否存在
    # 创建用户
    # 返回 token

@router.get("/me", response_model=User)
async def get_current_user(token: str = Depends(security)):
    """获取当前用户信息"""
    user_id = verify_jwt_token(token)
    user = await get_user_by_id(user_id)
    return user
```

---

## 5. Session 管理设计

### 5.1 Session 数据模型

```python
# models/session.py
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
import uuid

class Session(BaseModel):
    """Session 元数据"""
    id: str = str(uuid.uuid4())
    user_id: str
    title: str = "新对话"  # 自动生成或用户命名
    model: str = "claude-sonnet-4-5"
    agent_type: str = "assistant"  # assistant, researcher, coder...
    status: str = "active"  # active, archived, deleted
    created_at: datetime = datetime.utcnow()
    updated_at: datetime = datetime.utcnow()
    
    # Token 统计
    total_input_tokens: int = 0
    total_output_tokens: int = 0
    total_cost: float = 0.0

class SessionContent(BaseModel):
    """Session 内容（存储在文件或 Redis）"""
    session_id: str
    messages: list[dict]  # Message 列表
    context: dict  # 上下文信息
```

### 5.2 Session 存储策略

| 数据类型 | 存储位置 | 原因 |
|----------|----------|------|
| Session 元数据 | PostgreSQL | 查询、过滤、统计 |
| Session 内容（活跃） | Redis | 快速访问、流式写入 |
| Session 内容（历史） | 文件系统/对象存储 | 大数据、持久化 |
| Session 累计统计 | PostgreSQL | 成本追踪、分析 |

### 5.3 Session API

```python
# api/session.py
from fastapi import APIRouter, Depends, Query
from typing import List

router = APIRouter(prefix="/api/sessions", tags=["Session"])

@router.get("/", response_model=List[Session])
async def list_sessions(
    user: User = Depends(get_current_user),
    status: str = Query(default="active"),
    page: int = Query(default=1),
    page_size: int = Query(default=20)
):
    """获取用户的 Session 列表"""
    sessions = await get_user_sessions(
        user_id=user.id,
        status=status,
        offset=(page - 1) * page_size,
        limit=page_size
    )
    return sessions

@router.get("/{session_id}", response_model=SessionDetail)
async def get_session_detail(
    session_id: str,
    user: User = Depends(get_current_user)
):
    """获取 Session 详情（包含消息内容）"""
    # 验证 Session 属于该用户
    session = await get_session(session_id)
    if session.user_id != user.id:
        raise HTTPException(403, "无权访问此 Session")
    
    # 获取消息内容
    content = await get_session_content(session_id)
    return SessionDetail(session=session, messages=content.messages)

@router.post("/", response_model=Session)
async def create_session(
    req: CreateSessionRequest,
    user: User = Depends(get_current_user)
):
    """创建新 Session"""
    session = await create_new_session(
        user_id=user.id,
        model=req.model or user.settings.default_model,
        agent_type=req.agent_type
    )
    return session

@router.delete("/{session_id}")
async def delete_session(
    session_id: str,
    user: User = Depends(get_current_user)
):
    """删除 Session"""
    # 验证权限
    # 标记为 deleted 或彻底删除

@router.patch("/{session_id}/title")
async def update_session_title(
    session_id: str,
    req: UpdateTitleRequest,
    user: User = Depends(get_current_user)
):
    """更新 Session 标题"""
```

### 5.4 Session Store 实现

```python
# services/session_store.py
from claude_agent_sdk import SessionStore
import json
import os

class DatabaseSessionStore(SessionStore):
    """自定义 Session 存储，对接数据库"""
    
    def __init__(self, session_id: str, user_id: str):
        self.session_id = session_id
        self.user_id = user_id
        self.redis_key = f"session:{user_id}:{session_id}"
    
    async def save(self, messages: list, metadata: dict):
        """保存 Session 到 Redis（活跃）和文件（备份）"""
        # Redis 快速存储
        await redis.set(
            self.redis_key,
            json.dumps({"messages": messages, "metadata": metadata}),
            ex=3600 * 24  # 24 小时过期
        )
        
        # 异步写入文件（持久化）
        await self._write_to_file(messages, metadata)
    
    async def load(self) -> tuple[list, dict]:
        """加载 Session"""
        # 先从 Redis 读
        data = await redis.get(self.redis_key)
        if data:
            return json.loads(data)
        
        # Redis 没有，从文件读
        return await self._read_from_file()
    
    async def _write_to_file(self, messages, metadata):
        """写入文件"""
        path = f"/data/sessions/{self.user_id}/{self.session_id}.json"
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            json.dump({"messages": messages, "metadata": metadata}, f)
    
    async def _read_from_file(self):
        """从文件读取"""
        path = f"/data/sessions/{self.user_id}/{self.session_id}.json"
        if os.path.exists(path):
            with open(path) as f:
                return json.load(f)
        return [], {}
```

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
│   └── InputArea：输入框、发送按钮、Agent 选择
│
└── 后台设置页面（管理员）
    ├── 用户管理
    │   ├── 用户列表
    │   ├── 添加/编辑用户
    │   └── 权限分配
    ├── 模型配置
    │   ├── 可用模型列表
    │   ├── 默认模型设置
    │   ├── 模型参数（temperature 等）
    ├── Agent 配置
    │   ├── Agent 类型管理
    │   ├── 工具绑定
    │   ├── System Prompt 编辑
    ├── 工具配置
    │   ├── 工具列表
    │   ├── MCP Server 配置
    │   ├── 权限规则
    └── 系统设置
        ├── API Key 管理
        ├── 成本监控
        ├── 日志查看
```

### 6.2 聊天页面设计

**页面布局：**

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
|          |  | 输入框 | Agent选择 | 发送     |   |
|          |  +-------------------------------+   |
+--------------------------------------------------+
```

**消息类型渲染：**

| 消息类型 | 渲染方式 |
|----------|----------|
| 用户消息 | 简单文本，右侧显示 |
| 助手文本 | Markdown 渲染，左侧显示，流式动画 |
| Tool Use | 可折叠卡片，显示工具名、参数 |
| Tool Result | 可折叠卡片，显示执行结果 |
| Thinking | 隐藏或可展开的思考过程 |
| Error | 红色高亮错误信息 |

### 6.3 后台设置页面设计

**模型配置页面：**

```
+--------------------------------------------------+
|  模型配置                                         |
+--------------------------------------------------+
|                                                  |
|  可用模型列表：                                   |
|  +--------------------------------------------+  |
|  | [x] claude-opus-4-6   | 默认: [] | 参数   |  |
|  | [x] claude-sonnet-4-5 | 默认: [*] | 参数   |  |
|  | [x] claude-haiku-4-5  | 省: [] | 参数   |  |
|  +--------------------------------------------+  |
|                                                  |
|  全局默认模型：claude-sonnet-4-5                  |
|                                                  |
|  模型参数：                                       |
|  - Temperature: [0.7] 滑动条                     |
|  - Max Tokens: [4096]                            |
|                                                  |
|  [保存配置]                                       |
+--------------------------------------------------+
```

**Agent 配置页面：**

```
+--------------------------------------------------+
|  Agent 类型管理                                   |
+--------------------------------------------------+
|                                                  |
|  +--------------------------------------------+  |
|  | Agent 名称 | System Prompt | 工具 | 操作 |  |
|  +--------------------------------------------+  |
|  | Researcher | [编辑]        | [配置] | [删除]|  |
|  | Coder      | [编辑]        | [配置] | [删除]|  |
|  | Assistant  | [编辑]        | [配置] | [删除]|  |
|  +--------------------------------------------+  |
|                                                  |
|  [+ 新建 Agent 类型]                              |
|                                                  |
+--------------------------------------------------+
```

### 6.4 前端技术实现

**目录结构：**

```
frontend/
├── src/
│   ├── pages/
│   │   ├── Login.tsx           # 登录页
│   │   ├── Chat.tsx            # 聊天页
│   │   ├── Settings/           # 后台设置
│   │   │   ├── index.tsx       # 设置主页
│   │   │   ├── Models.tsx      # 模型配置
│   │   │   ├── Agents.tsx      # Agent 配置
│   │   │   ├── Tools.tsx       # 工具配置
│   │   │   ├── Users.tsx       # 用户管理
│   │   │   └── System.tsx      # 系统设置
│   │
│   ├── components/
│   │   ├── Chat/
│   │   │   ├── MessageList.tsx
│   │   │   ├── MessageItem.tsx
│   │   │   ├── ToolCallView.tsx
│   │   │   ├── InputArea.tsx
│   │   │   └── SessionSidebar.tsx
│   │   ├── Settings/
│   │   │   ├── ModelConfigForm.tsx
│   │   │   ├── AgentConfigForm.tsx
│   │   │   └── UserTable.tsx
│   │   └── common/
│   │       ├── Header.tsx
│   │       ├── Sidebar.tsx
│   │       └── Loading.tsx
│   │
│   ├── hooks/
│   │   ├── useWebSocket.ts     # WebSocket 连接
│   │   ├── useSession.ts       # Session 管理
│   │   └── useAuth.ts          # 认证
│   │
│   ├── stores/
│   │   ├── userStore.ts        # 用户状态
│   │   ├── chatStore.ts        # 聊天状态
│   │   └── settingsStore.ts    # 设置状态
│   │
│   ├── services/
│   │   ├── api.ts              # API 调用
│   │   ├── websocket.ts        # WebSocket
│   │   └── auth.ts             # 认证服务
│   │
│   └── types/
│   │   ├── user.ts
│   │   ├── session.ts
│   │   ├── message.ts
│   │   └── config.ts
│   │
│   ├── App.tsx
│   ├── router.tsx
│   └── main.tsx
│
├── package.json
├── tsconfig.json
└── vite.config.ts
```

**WebSocket 消息处理：**

```typescript
// hooks/useWebSocket.ts
import { useEffect, useRef } from 'react'
import { useChatStore } from '../stores/chatStore'

export function useWebSocket(sessionId: string) {
  const wsRef = useRef<WebSocket | null>(null)
  const { addMessage, updateStreamingMessage } = useChatStore()

  useEffect(() => {
    const ws = new WebSocket(`ws://api.example.com/ws/${sessionId}`)
    
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data)
      
      switch (data.type) {
        case 'message_start':
          addMessage({
            id: data.message_id,
            role: 'assistant',
            content: '',
            status: 'streaming'
          })
          break
          
        case 'content_block_delta':
          updateStreamingMessage(data.message_id, data.delta)
          break
          
        case 'message_stop':
          updateStreamingMessage(data.message_id, { status: 'complete' })
          break
          
        case 'tool_use':
          addMessage({
            id: data.tool_id,
            role: 'tool',
            name: data.tool_name,
            input: data.tool_input,
            status: 'running'
          })
          break
          
        case 'tool_result':
          updateStreamingMessage(data.tool_id, {
            status: 'complete',
            output: data.result
          })
          break
      }
    }
    
    wsRef.current = ws
    return () => ws.close()
  }, [sessionId])

  const sendMessage = (content: string) => {
    wsRef.current?.send(JSON.stringify({
      type: 'user_message',
      content
    }))
  }

  return { sendMessage }
}
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
| 配置 | `/api/config` | 模型、Agent、工具配置 |
| Agent | `/api/agents` | Agent 类型管理 |

### 7.2 API 详细设计

**认证 API：**

```
POST   /api/auth/login          # 登录
POST   /api/auth/register       # 注册
POST   /api/auth/logout         # 登出
GET    /api/auth/me             # 获取当前用户
POST   /api/auth/refresh        # 刷新 Token
```

**用户 API（管理员）：**

```
GET    /api/users               # 用户列表
POST   /api/users               # 创建用户
GET    /api/users/{id}          # 用户详情
PUT    /api/users/{id}          # 更新用户
DELETE /api/users/{id}          # 删除用户
PUT    /api/users/{id}/role     # 更改角色
```

**Session API：**

```
GET    /api/sessions            # Session 列表（当前用户）
POST   /api/sessions            # 创建 Session
GET    /api/sessions/{id}       # Session 详情（含消息）
DELETE /api/sessions/{id}       # 删除 Session
PATCH  /api/sessions/{id}/title # 更新标题
PATCH  /api/sessions/{id}/archive # 归档
```

**聊天 API（WebSocket）：**

```
WS     /api/ws/{session_id}     # WebSocket 连接
POST   /api/chat/{session_id}/message  # 发送消息（备用 HTTP）
GET    /api/chat/{session_id}/stream   # SSE 流（备用）
```

**配置 API：**

```
GET    /api/config/models       # 获取可用模型列表
PUT    /api/config/models       # 更新模型配置
GET    /api/config/default-model # 获取默认模型
PUT    /api/config/default-model # 设置默认模型

GET    /api/config/agents       # 获取 Agent 类型列表
POST   /api/config/agents       # 创建 Agent 类型
PUT    /api/config/agents/{id}  # 更新 Agent 类型
DELETE /api/config/agents/{id}  # 删除 Agent 类型

GET    /api/config/tools        # 获取工具列表
PUT    /api/config/tools/permissions # 更新工具权限

GET    /api/config/mcp-servers  # MCP Server 配置
POST   /api/config/mcp-servers  # 添加 MCP Server
DELETE /api/config/mcp-servers/{id} # 删除 MCP Server
```

### 7.3 API 实现示例

```python
# main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api import auth, users, sessions, chat, config

app = FastAPI(
    title="Agent Platform API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(sessions.router)
app.include_router(chat.router)
app.include_router(config.router)

# WebSocket 路由
@app.websocket("/api/ws/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    await websocket.accept()
    
    # 验证用户
    user = await verify_websocket_user(websocket)
    
    # 创建 Agent 实例
    agent = await create_agent_for_session(session_id, user)
    
    try:
        while True:
            # 接收用户消息
            data = await websocket.receive_json()
            
            if data["type"] == "user_message":
                # 发送给 Agent
                await agent.query(data["content"])
                
                # 流式返回
                async for msg in agent.receive_response():
                    await websocket.send_json(msg.to_dict())
                    
    except WebSocketDisconnect:
        await agent.close()
```

---

## 8. 模型配置设计

### 8.1 模型配置数据模型

```python
# models/config.py
from pydantic import BaseModel
from typing import Literal

class ModelConfig(BaseModel):
    """模型配置"""
    id: str
    name: str  # claude-opus-4-6, claude-sonnet-4-5...
    display_name: str  # Claude Opus 4, Claude Sonnet 4...
    is_enabled: bool = True
    
    # 模型参数
    default_temperature: float = 0.7
    max_output_tokens: int = 4096
    
    # 成本信息（用于显示）
    input_cost_per_1k: float  # 美元/1k tokens
    output_cost_per_1k: float
    
    # 权限控制
    allowed_roles: list[str] = ["user", "admin", "super_admin"]  # 哪些角色可用

class SystemModelSettings(BaseModel):
    """系统级模型设置"""
    default_model: str = "claude-sonnet-4-5"
    fallback_model: str = "claude-haiku-4-5"  # 失败时的备用模型
    max_tokens_limit: int = 100000  # 单 Session 最大 tokens
    
    # 模型列表
    available_models: list[ModelConfig] = []
```

### 8.2 模型配置 API

```python
# api/config.py
from fastapi import APIRouter, Depends

router = APIRouter(prefix="/api/config", tags=["配置"])

@router.get("/models")
async def get_models(user: User = Depends(get_current_user)):
    """获取可用模型列表（根据用户角色过滤）"""
    all_models = await get_all_model_configs()
    
    # 根据用户角色过滤
    available = [
        m for m in all_models 
        if m.is_enabled and user.role in m.allowed_roles
    ]
    return available

@router.put("/models")
async def update_models(
    req: UpdateModelsRequest,
    user: User = Depends(require_admin)
):
    """更新模型配置（管理员）"""
    await update_model_configs(req.models)
    return {"success": True}

@router.get("/default-model")
async def get_default_model(user: User = Depends(get_current_user)):
    """获取用户的默认模型"""
    # 用户个人设置优先
    if user.settings.default_model:
        return {"model": user.settings.default_model}
    # 否则用系统默认
    system_default = await get_system_default_model()
    return {"model": system_default}

@router.put("/default-model")
async def set_default_model(
    req: SetDefaultModelRequest,
    user: User = Depends(get_current_user)
):
    """设置用户默认模型"""
    # 验证模型可用
    models = await get_models(user)
    if req.model not in [m.name for m in models]:
        raise HTTPException(400, "模型不可用")
    
    await update_user_settings(user.id, {"default_model": req.model})
    return {"success": True}
```

### 8.3 动态模型切换

```python
# services/agent_manager.py
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

class AgentManager:
    """Agent 实例管理"""
    
    async def create_agent(
        session_id: str,
        user: User,
        model: str = None
    ):
        """创建 Agent 实例"""
        # 获取配置
        model = model or user.settings.default_model
        agent_type = await get_session_agent_type(session_id)
        agent_config = await get_agent_config(agent_type)
        
        # 构建 Options
        options = ClaudeAgentOptions(
            system_prompt=agent_config.system_prompt,
            allowed_tools=agent_config.allowed_tools,
            model=model,
            permission_mode=user.settings.permission_mode,
            session_store=DatabaseSessionStore(session_id, user.id)
        )
        
        return ClaudeSDKClient(options=options)
    
    async def switch_model(self, client: ClaudeSDKClient, new_model: str):
        """动态切换模型"""
        await client.set_model(new_model)
```

---

## 9. Agent 模块设计

### 9.1 Agent 类型管理

```python
# models/agent.py
from pydantic import BaseModel
from typing import Optional

class AgentTypeConfig(BaseModel):
    """Agent 类型配置"""
    id: str
    name: str  # researcher, coder, assistant...
    display_name: str  # 研究员, 编码助手...
    description: str
    
    # Agent 定义
    system_prompt: str
    allowed_tools: list[str]
    disallowed_tools: list[str] = []
    default_model: str = "claude-sonnet-4-5"
    
    # 权限
    allowed_roles: list[str] = ["user", "admin"]
    
    # 是否启用
    is_enabled: bool = True

# 存储 Agent 类型配置到数据库
# 管理员可在后台页面编辑
```

### 9.2 Agent 动态加载

```python
# services/agent_loader.py
from claude_agent_sdk import AgentDefinition

async def load_agent_configs() -> dict[str, AgentDefinition]:
    """从数据库加载 Agent 配置"""
    configs = await db.query("SELECT * FROM agent_types WHERE is_enabled = true")
    
    return {
        c.name: AgentDefinition(
            name=c.name,
            system_prompt=c.system_prompt,
            allowed_tools=c.allowed_tools,
            disallowed_tools=c.disallowed_tools,
            model=c.default_model
        )
        for c in configs
    }

async def get_agent_options(
    agent_type: str,
    user: User
) -> ClaudeAgentOptions:
    """获取指定 Agent 的 Options"""
    config = await get_agent_config(agent_type)
    
    return ClaudeAgentOptions(
        system_prompt=config.system_prompt,
        allowed_tools=config.allowed_tools,
        disallowed_tools=config.disallowed_tools,
        model=user.settings.default_model,
        permission_mode=user.settings.permission_mode,
        session_store=DatabaseSessionStore(session_id, user.id),
        hooks=await load_hooks_for_user(user)
    )
```

---

## 10. 工具系统设计

### 10.1 工具配置管理

```python
# models/tool.py
from pydantic import BaseModel

class ToolConfig(BaseModel):
    """工具配置"""
    name: str
    description: str
    is_builtin: bool  # 内置工具 vs 自定义工具
    is_enabled: bool = True
    
    # 权限规则
    allowed_roles: list[str] = ["user"]
    requires_confirmation: bool = False  # 是否需要用户确认
    
    # MCP Server 来源（如果是 MCP 工具）
    mcp_server: Optional[str] = None

class MCPServerConfig(BaseModel):
    """MCP Server 配置"""
    id: str
    name: str
    command: str  # 启动命令
    args: list[str] = []
    env: dict[str, str] = {}
    is_enabled: bool = True
```

### 10.2 工具权限控制

```python
# services/tool_permissions.py

async def get_allowed_tools(user: User, agent_type: str) -> list[str]:
    """获取用户可用的工具列表"""
    # 1. Agent 类型允许的工具
    agent_config = await get_agent_config(agent_type)
    agent_tools = set(agent_config.allowed_tools)
    
    # 2. 用户角色允许的工具
    all_tools = await get_all_tool_configs()
    role_tools = {
        t.name for t in all_tools
        if t.is_enabled and user.role in t.allowed_roles
    }
    
    # 3. 用户个人设置的工具
    user_tools = set(user.settings.allowed_tools) if user.settings.allowed_tools else role_tools
    
    # 交集
    return list(agent_tools & role_tools & user_tools)

async def check_tool_permission(
    tool_name: str,
    user: User,
    session_id: str
) -> bool:
    """检查工具执行权限"""
    tool_config = await get_tool_config(tool_name)
    
    if not tool_config.is_enabled:
        return False
    
    if user.role not in tool_config.allowed_roles:
        return False
    
    if tool_config.requires_confirmation:
        # 需要前端确认
        await request_user_confirmation(session_id, tool_name)
    
    return True
```

---

## 11. 项目目录结构

### 11.1 完整项目结构

```
agent_platform/
├── frontend/                    # 前端应用
│   ├── src/
│   │   ├── pages/
│   │   │   ├── Login.tsx
│   │   │   ├── Chat.tsx
│   │   │   ├── Settings/
│   │   │   │   ├── Models.tsx
│   │   │   │   ├── Agents.tsx
│   │   │   │   ├── Tools.tsx
│   │   │   │   ├── Users.tsx
│   │   │   │   └── System.tsx
│   │   ├── components/
│   │   ├── hooks/
│   │   ├── stores/
│   │   ├── services/
│   │   ├── types/
│   │   ├── App.tsx
│   │   └── main.tsx
│   ├── package.json
│   └── vite.config.ts
│
├── backend/                     # 后端服务
│   ├── api/
│   │   ├── __init__.py
│   │   ├── auth.py              # 认证 API
│   │   ├── users.py             # 用户 API
│   │   ├── sessions.py          # Session API
│   │   ├── chat.py              # 聊天 API
│   │   ├── config.py            # 配置 API
│   │   └── agents.py            # Agent API
│   │
│   ├── models/
│   │   ├── __init__.py
│   │   ├── user.py              # 用户模型
│   │   ├── session.py           # Session 模型
│   │   ├── config.py            # 配置模型
│   │   ├── agent.py             # Agent 模型
│   │   └── tool.py              # 工具模型
│   │
│   ├── services/
│   │   ├── __init__.py
│   │   ├── user_manager.py      # 用户管理
│   │   ├── session_manager.py   # Session 管理
│   │   ├── session_store.py     # Session 存储
│   │   ├── agent_manager.py     # Agent 管理
│   │   ├── agent_loader.py      # Agent 配置加载
│   │   ├── config_manager.py    # 配置管理
│   │   └── tool_permissions.py  # 工具权限
│   │
│   ├── core/
│   │   ├── __init__.py
│   │   ├── database.py          # 数据库连接
│   │   ├── redis.py             # Redis 连接
│   │   ├── auth.py              # JWT 认证
│   │   └── security.py          # 安全工具
│   │
│   ├── tools/                   # 自定义工具
│   │   ├── __init__.py
│   │   ├── registry.py
│   │   ├── database.py
│   │   └── notification.py
│   │
│   ├── hooks/                   # 业务 Hooks
│   │   ├── __init__.py
│   │   ├── audit.py
│   │   └── policy.py
│   │
│   ├── migrations/              # 数据库迁移
│   │   ├── 001_init.py
│   │   └── 002_add_agent_types.py
│   │
│   ├── main.py                  # FastAPI 入口
│   ├── config.py                # 服务配置
│   └── requirements.txt
│
├── docker/
│   ├── docker-compose.yml
│   ├── frontend.Dockerfile
│   ├── backend.Dockerfile
│   └── nginx.conf
│
├── docs/
│   ├── api.md                   # API 文档
│   ├── frontend.md              # 前端文档
│   └── deployment.md            # 部署文档
│
├── scripts/
│   ├── init_db.py               # 初始化数据库
│   └── seed_data.py             # 种子数据
│
└── README.md
```

---

## 12. 数据库设计

### 12.1 数据表设计

**用户表 (users)：**

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) DEFAULT 'user',  -- user, admin, super_admin
    settings JSONB DEFAULT '{}',       -- 用户个人设置
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP NULL
);
```

**Session 表 (sessions)：**

```sql
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    title VARCHAR(200) DEFAULT '新对话',
    model VARCHAR(50) DEFAULT 'claude-sonnet-4-5',
    agent_type VARCHAR(50) DEFAULT 'assistant',
    status VARCHAR(20) DEFAULT 'active',  -- active, archived, deleted
    total_input_tokens INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    total_cost DECIMAL(10, 4) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP NULL
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_status ON sessions(status);
```

**Agent 类型表 (agent_types)：**

```sql
CREATE TABLE agent_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    description TEXT,
    system_prompt TEXT NOT NULL,
    allowed_tools JSONB DEFAULT '[]',
    disallowed_tools JSONB DEFAULT '[]',
    default_model VARCHAR(50) DEFAULT 'claude-sonnet-4-5',
    allowed_roles JSONB DEFAULT '["user", "admin"]',
    is_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**模型配置表 (model_configs)：**

```sql
CREATE TABLE model_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,      -- claude-opus-4-6
    display_name VARCHAR(100) NOT NULL,    -- Claude Opus 4
    is_enabled BOOLEAN DEFAULT true,
    default_temperature DECIMAL(3, 2) DEFAULT 0.7,
    max_output_tokens INTEGER DEFAULT 4096,
    input_cost_per_1k DECIMAL(10, 4),
    output_cost_per_1k DECIMAL(10, 4),
    allowed_roles JSONB DEFAULT '["user", "admin"]',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**工具配置表 (tool_configs)：**

```sql
CREATE TABLE tool_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_builtin BOOLEAN DEFAULT false,
    is_enabled BOOLEAN DEFAULT true,
    allowed_roles JSONB DEFAULT '["user"]',
    requires_confirmation BOOLEAN DEFAULT false,
    mcp_server VARCHAR(50) NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**MCP Server 配置表 (mcp_servers)：**

```sql
CREATE TABLE mcp_servers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    command TEXT NOT NULL,
    args JSONB DEFAULT '[]',
    env JSONB DEFAULT '{}',
    is_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**系统配置表 (system_config)：**

```sql
CREATE TABLE system_config (
    key VARCHAR(50) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 默认配置
INSERT INTO system_config (key, value) VALUES
('default_model', '"claude-sonnet-4-5"'),
('fallback_model', '"claude-haiku-4-5"'),
('max_tokens_limit', '100000');
```

### 12.2 数据库连接

```python
# core/database.py
from sqlalchemy import create_engine
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

DATABASE_URL = "postgresql+asyncpg://user:pass@localhost/agent_platform"

engine = create_async_engine(DATABASE_URL, echo=True)
async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

async def get_db():
    async with async_session() as session:
        yield session
```

---

## 13. 实施计划

### 13.1 开发阶段（总计 6 周）

| 阶段 | 时间 | 任务 | 产出 |
|------|------|------|------|
| Phase 1 | 第 1 周 | 后端基础 + 用户系统 | 用户认证 API、数据库 |
| Phase 2 | 第 2 周 | Session 管理 + Agent 核心 | Session API、Agent 引擎 |
| Phase 3 | 第 3 周 | 前端聊天页面 | 聊天 UI、WebSocket |
| Phase 4 | 第 4 周 | 前端后台设置页面 | 模型/Agent 配置 UI |
| Phase 5 | 第 5 周 | 自定义工具 + Hooks | 业务工具集成 |
| Phase 6 | 第 6 周 | 测试 + 部署 | 完整系统上线 |

### 13.2 详细任务分解

**Phase 1: 后端基础 + 用户系统（第 1 周）**

```
Day 1-2: 项目初始化
├── 创建项目目录结构
├── 初始化数据库（PostgreSQL）
├── 配置 Redis
├── 初始化 FastAPI 项目
└── 编写数据库表定义

Day 3-4: 用户系统
├── 实现用户注册 API
├── 实现用户登录 API（JWT）
├── 实现用户管理 API（管理员）
├── 编写认证中间件
└── 单元测试

Day 5: 验证与文档
├── API 文档生成（Swagger）
├── 测试用户 CRUD 流程
└── 编写 README
```

**Phase 2: Session 管理 + Agent 核心（第 2 周）**

```
Day 1-2: Session 管理
├── 实现 Session Store（Redis + 文件）
├── 实现 Session CRUD API
├── 实现 Session 列表查询
├── Session 权限验证

Day 3-4: Agent 核心
├── 集成 Claude Agent SDK
├── 实现 AgentManager
├── 实现 WebSocket 聊天 API
├── 流式消息处理

Day 5: 集成测试
├── 测试完整对话流程
├── 测试 Session 持久化
├── 性能测试
```

**Phase 3: 前端聊天页面（第 3 周）**

```
Day 1-2: 基础框架
├── 初始化 React 项目
├── 配置路由
├── 实现登录页面
├── 实现认证逻辑

Day 3-4: 聊天 UI
├── Session 历史侧边栏
├── 消息列表组件
├── 流式消息渲染
├── 工具调用展示
├── WebSocket 连接

Day 5: 验证
├── 前后端联调
├── 测试完整聊天流程
├── UI 优化
```

**Phase 4: 前端后台设置页面（第 4 周）**

```
Day 1: 用户管理页面
├── 用户列表表格
├── 用户编辑表单
├── 权限管理

Day 2: 模型配置页面
├── 模型列表
├── 模型参数配置
├── 默认模型设置

Day 3: Agent 配置页面
├── Agent 类型管理
├── System Prompt 编辑器
├── 工具绑定配置

Day 4: 工具配置页面
├── 工具列表
├── MCP Server 配置
├── 权限规则设置

Day 5: 系统设置页面
├── API Key 管理
├── 成本监控展示
├── 日志查看
```

**Phase 5: 自定义工具 + Hooks（第 5 周）**

```
Day 1-2: 自定义工具
├── 实现 SDK MCP Server
├── 开发业务工具（数据库查询等）
├── 工具注册
├── 测试工具调用

Day 3-4: Hooks
├── 实现审计 Hook
├── 实现安全 Hook
├── 实现成本追踪 Hook
├── Hooks 配置管理

Day 5: 集成
├── 工具与 Agent 集成
├── 权限控制测试
├── 完整流程验证
```

**Phase 6: 测试 + 部署（第 6 周）**

```
Day 1-2: 测试完善
├── 后端单元测试
├── 前端组件测试
├── E2E 测试
├── 边界情况测试

Day 3-4: 部署准备
├── Docker 配置
├── nginx 配置
├── 环境变量配置
├── 部署脚本

Day 5: 上线
├── 生产环境部署
├── 监控配置
├── 文档完善
├── 演示验证
```

### 13.3 验收标准

| 标准 | 要求 |
|------|------|
| 多用户支持 | 用户注册/登录、角色权限、配置隔离 |
| 聊天功能 | 多轮对话、流式输出、Session 历史 |
| 后台配置 | 模型配置、Agent 配置、工具配置、用户管理 |
| 数据持久化 | Session 存储、配置存储、用户数据 |
| 安全认证 | JWT 认证、权限控制、数据隔离 |
| 性能 | WebSocket 流式响应 < 100ms |

---

## 附录 A: 快速开始

### 后端启动

```bash
# 安装依赖
cd backend
pip install -r requirements.txt

# 初始化数据库
python scripts/init_db.py

# 启动服务
uvicorn main:app --reload --port 8000
```

### 前端启动

```bash
# 安装依赖
cd frontend
npm install

# 启动开发服务器
npm run dev
```

### Docker 部署

```bash
# 构建并启动
docker-compose up -d --build

# 查看日志
docker-compose logs -f
```

---

## 附录 B: 参考资料

1. [Claude Agent SDK Python](https://github.com/anthropics/claude-agent-sdk-python)
2. [Claude Agent SDK Demos](https://github.com/anthropics/claude-agent-sdk-demos)
3. [FastAPI 文档](https://fastapi.tiangolo.com/)
4. [React 文档](https://react.dev/)
5. [Ant Design 文档](https://ant.design/)
6. Claude Code 源码调研：`/data/caidanfeng/project/doc/md-doc/agent/claude-code-research/0_code_flow.md`