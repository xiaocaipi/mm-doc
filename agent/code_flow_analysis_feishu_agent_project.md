# 飞书 Agent 代码流程深度分析报告

## 文件信息
- **项目路径**: `/data/caidanfeng/project/ai/agent/agent-feishu`
- **分析时间**: 2026-05-29
- **语言**: Python 3.12
- **分析深度**: 递归深度分析
- **项目架构**: FastAPI + Claude Agent SDK + 多员工协作

## 概述

飞书 Agent（AI诸葛亮）是一个基于 Claude Agent SDK 的多员工协作系统，支持：
- **AI诸葛亮**: 任务分发机器人，负责接收用户请求并分配给对应员工
- **员工 Agent**: 拥有特定技能的任务执行者，通过 MCP Server 工具执行具体操作
- **记忆隔离**: 每个 chat_id 使用独立的 session，实现对话记忆隔离
- **Skills 机制**: 员工绑定的技能通过 SDK Skills 系统加载，实现能力扩展

## 系统架构流程图

### 1. 整体架构图

```mermaid
flowchart TB
    subgraph Feishu["飞书平台"]
        User["用户"]
        Group["群聊"]
        Bot["机器人"]
    end
    
    subgraph Service["服务层"]
        Main["FastAPI 主进程<br/>app/main.py"]
        Run["启动脚本<br/>run.py"]
    end
    
    subgraph Core["核心组件"]
        Agent["FeishuAgent<br/>Claude Agent SDK"]
        MsgHandler["MessageHandler<br/>消息处理器"]
        WsManager["WebSocketManager<br/>进程管理器"]
        Cache["EmployeeCache<br/>员工缓存"]
        Registry["AgentRegistry<br/>Agent 注册表"]
    end
    
    subgraph Listener["监听层"]
        WsListener["ws_listener.py<br/>独立进程"]
        FeishuListener["FeishuWebSocketListener"]
    end
    
    subgraph Data["数据层"]
        MySQL["MySQL 数据库<br/>feishu_agent"]
        CRUD["CRUD 操作"]
    end
    
    subgraph MCP["MCP 服务"]
        MCPServer["MCP Server<br/>HTTP 端点"]
        Tools["MCP 工具"]
    end
    
    subgraph Skills["技能系统"]
        SkillDir["employee_skills/<id>/"]
        SkillMd["SKILL.md"]
        Scripts["scripts/"]
    end
    
    User --> Group --> Bot
    Bot --> WsListener --> WsManager --> Main
    Main --> Agent --> CRUD --> MySQL
    Main --> MsgHandler --> Agent
    Main --> Cache --> CRUD
    Main --> Registry --> Agent
    Agent --> MCP --> Tools
    Agent --> Skills --> SkillMd
```

### 2. 生命周期流程图

```mermaid
flowchart LR
    Start["服务启动<br/>run.py"] --> Cleanup["清理旧进程"]
    Cleanup --> Init["初始化组件<br/>lifespan()"]
    Init --> CacheInit["刷新员工缓存"]
    CacheInit --> AgentInit["初始化主 Agent"]
    AgentInit --> WsStart["启动 WebSocket"]
    WsStart --> EmpInit["初始化员工 Agent"]
    EmpInit --> Running["服务运行"]
    Running --> Shutdown["关闭服务"]
    Shutdown --> WsStop["停止 WebSocket"]
    WsStop --> AgentDisconnect["断开 Agent"]
    AgentDisconnect --> CacheStop["停止缓存刷新"]
    CacheStop --> End["服务停止"]
```

### 3. 多进程架构图

```mermaid
flowchart TB
    subgraph MainProcess["主进程 (run.py)"]
        FastAPI["FastAPI HTTP 服务"]
        Commander["AI诸葛亮 Agent"]
        WsManager["WebSocketManager"]
        Cache["EmployeeCache 刷新"]
    end
    
    subgraph EmployeeProcess["员工进程池"]
        Emp1["ws_listener.py<br/>员工1"]
        Emp2["ws_listener.py<br/>员工2"]
        Emp3["ws_listener.py<br/>员工N"]
    end
    
    MainProcess -->|"创建/管理"| EmployeeProcess
    
    EmployeeProcess -->|"stdout JSON"| WsManager
    WsManager -->|"回调处理"| Commander
    
    Commander -->|"@员工 分配"| EmployeeProcess
```

## 时序图

### 3.1 总体时序图 - 消息处理完整流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant Feishu as 飞书平台
    participant WsListener as WebSocket监听器
    participant WsManager as 进程管理器
    participant Main as FastAPI主进程
    participant Agent as FeishuAgent
    participant ClaudeSDK as Claude SDK
    participant MCP as MCP Server
    participant DB as MySQL数据库
    
    Note over User, DB: 消息接收与处理总览
    
    User->>Feishu: 1. 发送消息
    Feishu->>WsListener: 2. WebSocket 推送事件
    Note over WsListener: 独立子进程运行<br/>监听 im.message.receive_v1
    WsListener->>WsManager: 3. 输出 JSON 事件
    Note over WsManager: stdout 解析<br/>包含 employee_id
    WsManager->>Main: 4. 回调 on_employee_message()
    Main->>Agent: 5. 获取员工 Agent
    Main->>Agent: 6. 发送快速确认
    Agent->>Feishu: 7. 回复"正在处理"
    
    Main->>Agent: 8. 处理消息 process()
    Agent->>ClaudeSDK: 9. 创建/获取 Client
    Note over ClaudeSDK: Client Pool<br/>每个 chat_id 一个
    Agent->>ClaudeSDK: 10. 发送 query
    ClaudeSDK->>ClaudeSDK: 11. 调用 MCP 工具
    ClaudeSDK->>MCP: 12. 执行 MCP 操作
    MCP-->>ClaudeSDK: 13. 返回结果
    ClaudeSDK-->>Agent: 14. 流式响应
    Agent-->>Main: 15. 响应文本
    
    Main->>Feishu: 16. 发送详细结果
    Feishu-->>User: 17. 用户收到回复
```

### 3.2 子时序图 - 服务启动流程

```mermaid
sequenceDiagram
    participant Run as run.py
    participant Main as app/main.py
    participant Cache as EmployeeCache
    participant Agent as FeishuAgent
    participant Registry as AgentRegistry
    participant WsManager as WebSocketManager
    participant WsListener as FeishuListener
    participant DB as MySQL
    
    Note over Run, DB: 服务启动初始化
    
    Run->>Run: 1. cleanup_old_processes()
    Note over Run: 清理遗留 ws_listener 进程
    Run->>Main: 2. 启动 FastAPI
    
    Main->>Main: 3. lifespan() 入口
    Main->>WsManager: 4. 创建 WebSocketManager
    Main->>Cache: 5. 刷新员工缓存
    Cache->>DB: 6. EmployeeCRUD.list()
    DB-->>Cache: 7. 返回员工列表
    Cache-->>Main: 8. 缓存就绪
    
    Main->>Agent: 9. 创建主 Agent (AI诸葛亮)
    Agent->>Agent: 10. initialize()
    Note over Agent: 加载 MCP Server<br/>构建 system_prompt<br/>设置 allowed_tools
    Agent-->>Main: 11. Agent 就绪
    
    Main->>WsListener: 12. 启动 WebSocket 监听
    WsListener->>WsListener: 13. 连接飞书
    
    Main->>Registry: 14. 初始化员工 Agent
    Registry->>DB: 15. 获取员工 skills
    Registry->>Registry: 16. 写入 SKILL.md
    Registry->>Agent: 17. create_agent()
    Agent->>Agent: 18. initialize()
    Agent-->>Registry: 19. Agent 就绪
    
    Main->>Cache: 20. 启动定时刷新 (30s)
    Main-->>Run: 21. 服务运行中
```

### 3.3 子时序图 - 员工处理消息

```mermaid
sequenceDiagram
    participant WsManager as WebSocketManager
    participant Callback as on_employee_message
    participant Registry as AgentRegistry
    participant Agent as FeishuAgent
    participant ClientPool as Client Pool
    participant ClaudeSDK as Claude SDK Client
    participant MCP as MCP Server
    participant Feishu as 飞书 API
    
    Note over WsManager, Feishu: 员工消息处理流程
    
    WsManager->>Callback: 1. JSON 事件数据
    Note over Callback: event_type: im.message.receive_v1<br/>包含 employee_id, chat_id
    
    Callback->>Callback: 2. 检测确认流程
    Callback->>Registry: 3. get_agent(employee_id)
    Registry-->>Callback: 4. 返回 Agent
    
    Callback->>Feishu: 5. 发送快速确认
    Note over Feishu: "收到任务，正在处理..."
    
    Callback->>Agent: 6. process(user_input, context)
    Agent->>ClientPool: 7. _get_or_create_client(chat_id)
    
    alt 新 chat_id
        Agent->>ClaudeSDK: 8a. 创建新 Client
        Note over ClaudeSDK: session_id: UUID<br/>resume: 恢复已有 session
    else 已有 chat_id
        Agent->>ClientPool: 8b. 返回已有 Client
    end
    
    Agent->>ClaudeSDK: 9. query(prompt)
    ClaudeSDK->>ClaudeSDK: 10. 接收响应流
    
    loop 响应流
        ClaudeSDK->>Agent: 11. AssistantMessage
        Agent->>Agent: 12. 解析 TextBlock/ToolUseBlock
    end
    
    ClaudeSDK-->>Agent: 13. ResultMessage
    Agent-->>Callback: 14. response_text
    
    Callback->>Feishu: 15. 发送详细结果
```

### 3.4 子时序图 - 员工重启流程

```mermaid
sequenceDiagram
    participant API as API /restart
    participant WsManager as WebSocketManager
    participant DB as MySQL + CRUD
    participant Process as ws_listener 进程
    participant Skills as Skills 目录
    participant Feishu as 飞书
    
    Note over API, Feishu: 员工重启流程
    
    API->>WsManager: 1. restart_employee(id, config)
    
    WsManager->>Process: 2. stop_employee()
    Process->>Process: 3. terminate()
    Process-->>WsManager: 4. 进程停止
    
    WsManager->>Skills: 5. 清理旧 skills 目录
    Note over Skills: 保留 projects 目录<br/>（对话记忆）
    
    WsManager->>DB: 6. SkillCRUD.get_by_name()
    DB-->>WsManager: 7. 返回 skill 内容
    
    WsManager->>Skills: 8. 写入 SKILL.md
    Note over Skills: YAML frontmatter + content
    
    WsManager->>Skills: 9. 复制公共脚本
    Note over Skills: shared_scripts/<skill>/scripts
    
    WsManager->>Process: 10. 启动新进程
    Note over Process: python ws_listener.py<br/>--employee-id <id>
    
    Process-->>WsManager: 11. 进程就绪
    
    WsManager->>DB: 12. 更新状态 active
    WsManager-->>API: 13. 重启成功
```

### 3.5 子时序图 - 飞书卡片确认交互流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant Feishu as 飞书平台
    participant WsListener as ws_listener
    participant WsManager as WebSocketManager
    participant Callback as on_employee_message
    participant Detect as detect_confirm_scenario
    participant Flow as 确认流程管理
    participant Card as 交互卡片
    participant Session as CONFIRM_SESSIONS
    participant Agent as FeishuAgent
    
    Note over User, Agent: 飞书卡片确认交互流程（如推流确认）
    
    User->>Feishu: 1. 发送 "推流" 消息
    Feishu->>WsListener: 2. WebSocket 推送 im.message.receive_v1
    WsListener->>WsManager: 3. 输出 JSON (employee_id, chat_id, content)
    WsManager->>Callback: 4. 回调 on_employee_message()
    
    Callback->>Detect: 5. detect_confirm_scenario("推流")
    Detect->>Detect: 6. 匹配 CONFIRM_SCENARIOS 关键词
    Detect-->>Callback: 7. 返回 "推流确认"
    
    Note over Callback: 检测到确认流程<br/>不发送"正在处理"确认
    
    Callback->>Flow: 8. start_confirm_flow(chat_id, "推流确认")
    Flow->>Session: 9. 初始化 CONFIRM_SESSIONS[chat_id]
    Note over Session: scenario="推流确认"<br/>current_step=0<br/>user_choices={}
    
    Flow->>Card: 10. build_interactive_card(第一步)
    Note over Card: 标题: 推流路径确认<br/>选项: test/mm_agent_tt, 自定义路径
    
    Flow->>Feishu: 11. send_interactive_card()
    Feishu-->>User: 12. 显示交互卡片
    
    User->>Feishu: 13. 点击按钮选择
    Feishu->>WsListener: 14. WebSocket 推送 card.action.trigger
    Note over WsListener: action_tag: "button"<br/>action_value: {selected, step}
    
    WsListener->>WsManager: 15. 输出 JSON 回调事件
    WsManager->>Callback: 16. 回调 on_employee_message()
    Callback->>Callback: 17. 检测 event_type == "card.action.trigger"
    
    Callback->>Callback: 18. on_card_callback(data)
    Callback->>Session: 19. 获取 CONFIRM_SESSIONS[chat_id]
    Callback->>Flow: 20. continue_confirm_flow(chat_id, selected_value, step_name)
    
    Flow->>Session: 21. 记录 user_choices["rtsp_path"] = selected_value
    Flow->>Flow: 22. 计算下一步索引 next_step
    
    alt 还有下一步
        Flow->>Session: 23a. 更新 current_step = next_step
        Flow->>Card: 24a. build_interactive_card(第二步)
        Note over Card: 标题: 黑色片段时长<br/>选项: 20秒, 30秒, 60秒
        Flow->>Feishu: 25a. send_interactive_card()
        Feishu-->>User: 26a. 显示第二个卡片
    else 流程完成
        Flow->>Session: 23b. 获取所有 user_choices
        Note over Flow: choices = {rtsp_path: "...", black_duration: "20"}
        
        Flow->>Flow: 24b. 构建 exec_prompt
        Note over Flow: "使用 stream-push 技能执行推流<br/>参数：rtsp_path=..., black_duration=20"
        
        Flow->>Feishu: 25b. 发送执行提示 "开始执行..."
        Flow->>Agent: 26b. agent.process(exec_prompt, context)
        
        Agent->>Agent: 27b. 执行 MCP 工具
        Agent-->>Flow: 28b. 返回执行结果
        
        Flow->>Feishu: 29b. 发送执行结果
        Feishu-->>User: 30b. 用户收到结果
        
        Flow->>Session: 31b. 清除 CONFIRM_SESSIONS[chat_id]
    end
```

## 飞书卡片确认机制详解

### 1. 确认场景定义 (CONFIRM_SCENARIOS)

**位置**: `app/main.py:75-101`

确认场景是预定义的操作流程，用于需要用户确认参数的敏感操作：

```python
CONFIRM_SCENARIOS = {
    "推流确认": {
        "trigger_keyword": ["推流", "帮我推流", "开始推流", "RTSP推流"],
        "skill_name": "stream-push",  # 确认完成后执行的技能
        "steps": [
            {
                "name": "rtsp_path",
                "title": "推流路径确认",
                "description": "请选择推流路径：",
                "options": [
                    {"label": "test/mm_agent_tt（推荐）", "value": "test/mm_agent_tt"},
                    {"label": "自定义路径", "value": "custom"}
                ]
            },
            {
                "name": "black_duration",
                "title": "黑色片段时长",
                "description": "请选择黑色片段时长：",
                "options": [
                    {"label": "20秒（推荐）", "value": "20"},
                    {"label": "30秒", "value": "30"},
                    {"label": "60秒", "value": "60"}
                ]
            }
        ]
    }
}
```

**场景结构说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| trigger_keyword | list | 触发关键词列表，用户消息匹配任一关键词触发确认流程 |
| skill_name | str | 确认完成后执行的技能名称 |
| steps | list | 确认步骤列表，每个步骤是一个参数选择 |

**步骤结构说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| name | str | 步骤名称（用于存储用户选择） |
| title | str | 卡片标题 |
| description | str | 卡片描述文本 |
| options | list | 选项列表，每个选项包含 label 和 value |

### 2. 确认会话状态管理 (CONFIRM_SESSIONS)

**位置**: `app/main.py:67`

```python
CONFIRM_SESSIONS = {}  # chat_id -> session 数据
```

Session 数据结构：

```python
{
    "scenario": "推流确认",           # 场景名称
    "current_step": 1,               # 当前步骤索引 (0, 1, 2...)
    "user_choices": {                # 用户已做出的选择
        "rtsp_path": "test/mm_agent_tt",
        "black_duration": "20"
    },
    "employee_id": "xxx",            # 员工 ID
    "app_id": "xxx",                 # 飞书 App ID（用于发送消息）
    "app_secret": "xxx",             # 飞书 App Secret
    "start_time": "2026-05-29T..."  # 开始时间
}
```

### 3. 交互卡片 JSON 结构

**位置**: `app/main.py:104-145`

```python
def build_interactive_card(title: str, description: str, options: list) -> dict:
```

生成的卡片 JSON：

```json
{
    "config": {
        "wide_screen_mode": true
    },
    "header": {
        "title": {
            "tag": "plain_text",
            "content": "推流路径确认"
        },
        "template": "blue"
    },
    "elements": [
        {
            "tag": "div",
            "text": {
                "tag": "lark_md",
                "content": "请选择推流路径："
            }
        },
        {
            "tag": "action",
            "actions": [
                {
                    "tag": "button",
                    "text": {
                        "tag": "plain_text",
                        "content": "test/mm_agent_tt（推荐）"
                    },
                    "type": "primary",
                    "value": {
                        "selected": "test/mm_agent_tt",
                        "step": "rtsp_path"
                    }
                },
                {
                    "tag": "button",
                    "text": {
                        "tag": "plain_text",
                        "content": "自定义路径"
                    },
                    "type": "default",
                    "value": {
                        "selected": "custom",
                        "step": "rtsp_path"
                    }
                }
            ]
        }
    ]
}
```

**关键字段说明**:

| 字段 | 说明 |
|------|------|
| value.selected | 用户选择的值 |
| value.step | 当前步骤名称（用于 continue_confirm_flow 判断） |
| type: "primary" | 第一个按钮为主按钮（蓝色高亮） |
| type: "default" | 其他按钮为默认样式 |

### 4. 核心函数详解

#### 4.1 detect_confirm_scenario()

**位置**: `app/main.py:182-194`

**功能**: 检测用户消息是否触发确认流程

```python
def detect_confirm_scenario(user_input: str) -> str:
    user_input_lower = user_input.lower()
    for scenario_name, scenario_config in CONFIRM_SCENARIOS.items():
        for keyword in scenario_config["trigger_keywords"]:
            if keyword.lower() in user_input_lower:
                return scenario_name  # 返回匹配的场景名称
    return None  # 未匹配返回 None
```

**输入输出**:

| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| user_input | str | 输入 | 用户消息内容 |
| scenario_name | str | 返回 | 匹配的场景名称（如 "推流确认"）或 None |

#### 4.2 start_confirm_flow()

**位置**: `app/main.py:197-236`

**功能**: 开始确认流程，发送第一个交互卡片

```python
async def start_confirm_flow(chat_id, scenario_name, employee_id, app_id, app_secret):
    scenario = CONFIRM_SCENARIOS.get(scenario_name)
    first_step = scenario["steps"][0]
    
    # 初始化会话状态
    CONFIRM_SESSIONS[chat_id] = {
        "scenario": scenario_name,
        "current_step": 0,
        "user_choices": {},
        "employee_id": employee_id,
        "app_id": app_id,
        "app_secret": app_secret,
        "start_time": datetime.now().isoformat()
    }
    
    # 构建并发送卡片
    card = build_interactive_card(first_step["title"], first_step["description"], first_step["options"])
    await send_interactive_card(chat_id, card, app_id, app_secret)
```

**输入输出**:

| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| chat_id | str | 输入 | 聊天 ID |
| scenario_name | str | 输入 | 场景名称 |
| employee_id | str | 输入 | 员工 ID |
| app_id | str | 输入 | 飞书 App ID |
| app_secret | str | 输入 | 飞书 App Secret |

#### 4.3 continue_confirm_flow()

**位置**: `app/main.py:238-374`

**功能**: 处理用户按钮点击，继续确认流程

```python
async def continue_confirm_flow(chat_id, selected_value, step_name):
    session = CONFIRM_SESSIONS.get(chat_id)
    scenario = CONFIRM_SCENARIOS[session["scenario"]]
    
    # 1. 记录用户选择
    session["user_choices"][step_name] = selected_value
    
    # 2. 计算下一步索引
    current_step = 找到 step_name 对应的索引
    next_step = current_step + 1
    
    if next_step >= len(scenario["steps"]):
        # 流程完成 - 执行技能
        choices = session["user_choices"]
        skill_name = scenario.get("skill_name", "")
        
        # 构建执行提示词
        if skill_name == "stream-push":
            exec_prompt = f"使用 stream-push 技能执行推流，参数：rtsp_path={choices['rtsp_path']}, black_duration={choices['black_duration']}"
        
        # 调用 Agent 执行
        agent.process(exec_prompt, context)
        
        # 清除会话
        CONFIRM_SESSIONS.pop(chat_id, None)
    else:
        # 发送下一个卡片
        next_step_config = scenario["steps"][next_step]
        card = build_interactive_card(...)
        await send_interactive_card(chat_id, card, ...)
```

**输入输出**:

| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| chat_id | str | 输入 | 聊天 ID |
| selected_value | str | 输入 | 用户选择的值 |
| step_name | str | 输入 | 当前步骤名称 |

#### 4.4 on_card_callback()

**位置**: `app/main.py:377-414`

**功能**: 处理飞书卡片按钮点击回调

```python
async def on_card_callback(data: dict):
    employee_id = data.get('employee_id')
    chat_id = data.get('chat_id')
    action_tag = data.get('action_tag')  # "button"
    action_value = data.get('action_value', {})
    selected_value = data.get('selected_value')
    
    # 检查是否有活跃的确认会话
    session = CONFIRM_SESSIONS.get(chat_id)
    
    if session and action_tag == "button":
        step_name = action_value.get("step", "")
        await continue_confirm_flow(chat_id, selected_value, step_name)
```

**回调数据结构**:

```python
{
    "event_type": "card.action.trigger",
    "employee_id": "xxx",
    "chat_id": "oc_xxx",
    "user_open_id": "ou_xxx",
    "message_id": "om_xxx",
    "action_tag": "button",
    "action_value": {
        "selected": "test/mm_agent_tt",
        "step": "rtsp_path"
    },
    "selected_value": "test/mm_agent_tt"
}
```

### 5. 用户操作流程图

```mermaid
flowchart TD
    A[用户发送: 推流] --> B{检测关键词}
    B -->|匹配 推流| C[不发送正在处理确认]
    B -->|未匹配| D[发送正在处理确认]
    
    C --> E[发送交互卡片]
    E --> F[卡片: 推流路径确认]
    F --> G[按钮: test/mm_agent_tt | 自定义路径]
    
    G --> H{用户点击按钮}
    H -->|点击选项| I[飞书触发 card.action.trigger]
    
    I --> J[ws_listener 输出 JSON]
    J --> K[WsManager 回调]
    K --> L[on_card_callback]
    
    L --> M[记录 user_choices]
    M --> N{还有下一步?}
    
    N -->|Yes| O[发送下一个卡片]
    O --> P[卡片: 黑色片段时长]
    P --> Q[按钮: 20秒 | 30秒 | 60秒]
    Q --> H
    
    N -->|No| R[流程完成]
    R --> S[构建 exec_prompt]
    S --> T[调用 Agent 执行]
    T --> U[发送执行结果]
    U --> V[清除 CONFIRM_SESSIONS]
```

### 6. 与普通消息处理的对比

| 场景 | 用户消息处理 | 卡片确认流程 |
|------|-------------|-------------|
| 触发条件 | 所有消息 | 匹配 CONFIRM_SCENARIOS 关键词 |
| 快速确认 | 发送"正在处理..." | 不发送（直接发送卡片） |
| 响应方式 | Agent 处理 → 发送结果 | 发送交互卡片 → 等待用户选择 |
| 事件类型 | im.message.receive_v1 | card.action.trigger |
| 状态管理 | Client Pool (session) | CONFIRM_SESSIONS |
| 执行时机 | 收到消息后立即执行 | 所有步骤完成后执行 |

### 7. ws_listener 卡片回调处理

**位置**: `ws_listener.py:79-126`

```python
def do_p2_card_action_trigger(data: P2CardActionTrigger) -> P2CardActionTriggerResponse:
    operator = data.event.operator
    action = data.event.action
    context = data.event.context
    
    # 提取用户选择
    selected_value = None
    action_value = {}
    
    if action.tag == "button":
        action_value = action.value or {}
        selected_value = action_value.get("selected", "")
    
    # 构建回调事件数据
    event_data = {
        "event_type": "card.action.trigger",
        "employee_id": employee_id,
        "chat_id": context.open_chat_id,
        "user_open_id": operator.open_id,
        "action_tag": action.tag,
        "action_value": action_value,
        "selected_value": selected_value
    }
    
    # 输出 JSON
    print(json.dumps(event_data))
    
    # 返回 Toast 提示
    return P2CardActionTriggerResponse(d={"toast": {"type": "success", "content": "已收到您的选择"}})
```

## 完整调用树

```
run.py
├── cleanup_old_processes() - 清理旧进程
│   ├── subprocess.run(["pgrep", "-f", "ws_listener.py"])
│   └── os.kill(pid, signal.SIGTERM/SIGKILL)
└── main() - 主入口
    ├── uvicorn.Config() - 创建配置
    └── uvicorn.Server.serve() - 启动服务
        │
        └── app/main.py (FastAPI)
            ├── lifespan() - 应用生命周期
            │   ├── WebSocketManager(on_message=on_employee_message) - 创建管理器
            │   ├── EmployeeCache.refresh() - 刷新员工缓存
            │   │   └── EmployeeCRUD.list() - 查询所有员工
            │   │       └── get_connection() - 获取数据库连接
            │   │       └── cursor.execute("SELECT * FROM employees")
            │   ├── FeishuAgent() - 创建主 Agent
            │   │   └── initialize()
            │   │       ├── _load_mcp_servers() - 加载 MCP Server
            │   │       │   └── MCPServerCRUD.get_by_name() - 查询 MCP 配置
            │   │       ├── _get_system_prompt() - 构建系统提示词
            │   │       │   └── get_bot_profile() - 获取角色配置
            │   │       │   └── SkillCRUD.get_by_name() - 获取技能信息
            │   │       └── ClaudeAgentOptions() - 构建 SDK 配置
            │   ├── MessageHandler() - 创建消息处理器
            │   ├── FeishuWebSocketListener() - 启动监听
            │   │   └── start() - 启动 WebSocket
            │   └── AgentRegistry.create_agent() - 初始化员工 Agent
            │       └── FeishuAgent.initialize()
            │           └── 写入 SKILL.md 到员工目录
            │           └── 复制公共脚本
            │   └── EmployeeCache.start_periodic_refresh() - 定时刷新
            │   │
            │   └── yield - 服务运行
            │   │
            │   └── 关闭流程
            │       ├── ws_manager.stop_all()
            │       ├── feishu_listener.stop()
            │       ├── agent.disconnect_all()
            │       └── registry.remove_agent()
            │
            ├── 路由处理
            │   ├── /health - 健康检查
            │   ├── /status - 状态查询
            │   ├── /employees - 员工管理
            │   │   ├── list_employees() - 获取员工列表
            │   │   ├── create_employee() - 创建员工
            │   │   ├── restart_employee() - 重启员工
            │   │   │   └── ws_manager.restart_employee()
            │   │   │       ├── stop_employee()
            │   │   │       ├── 写入 SKILL.md
            │   │   │       └── start_employee()
            │   │   │           └── asyncio.create_subprocess_exec()
            │   │   └── delete_employee() - 删除员工
            │   └── /internal - 内部 API
            │
            └── on_employee_message() - 消息回调
                ├── detect_confirm_scenario() - 检测确认流程
                ├── get_agent_registry().get_agent() - 获取 Agent
                ├── send_employee_message() - 发送快速确认
                └── agent.process() - 处理消息
                    ├── _get_or_create_client() - 获取/创建 Client
                    │   ├── _generate_session_uuid() - 生成 session ID
                    │   ├── 检查 session 文件是否存在
                    │   └── ClaudeSDKClient() - 创建 Client
                    │       ├── ClaudeAgentOptions(resume/session_id)
                    │       └── client.connect()
                    └── query() - 发送请求
                    └── receive_response() - 接收响应
                        ├── AssistantMessage - 解析消息
                        │   ├── TextBlock - 文本内容
                        │   └── ToolUseBlock - 工具调用
                        └── ResultMessage - 结束信号
                └── send_employee_message() - 发送结果

ws_listener.py (独立进程)
├── main() - 主入口
│   ├── argparse 解析命令行参数
│   ├── EventDispatcherHandler.builder() - 创建事件处理器
│   │   ├── register_p2_im_message_receive_v1()
│   │   └── register_p2_card_action_trigger()
│   └── Client() - 创建 WebSocket 客户端
│       └── start() - 启动监听
│
├── do_p2p_im_message_receive_v1() - 处理消息
│   ├── _extract_content() - 提取消息内容
│   │   ├── json.loads() - 解析 JSON
│   │   └── _extract_post_text() - 提取富文本
│   ├── _extract_mentions() - 提取 @提及
│   └── print(json.dumps()) - 输出 JSON
│
└── do_p2_card_action_trigger() - 处理卡片回调
    └── print(json.dumps()) - 输出 JSON
```

## 核心方法详细分析

### 1. FeishuAgent.initialize()

**位置**: `app/core/feishu_agent.py:62-137`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| employee_id | str | 输入 | 员工 ID（None 为 AI诸葛亮） |
| employee_config | dict | 输入 | 员工配置（skills, mcp_servers 等） |
| _mcp_servers | dict | 输出 | MCP Server 配置字典 |
| _allowed_tools | list | 输出 | 允许的工具列表 |
| _client_options | ClaudeAgentOptions | 输出 | SDK 配置对象 |

**内部实现**:
1. 加载 MCP Server（HTTP 方式）- 从数据库查询
2. 获取机器人信息 - bot_open_id
3. 构建 allowed_tools - 自动获取所有 MCP 工具名
4. 构建系统提示词 - 包含身份、工具权限、飞书说明
5. 设置工作目录 - 员工目录或 commander 目录
6. 构建 SDK 配置 - ClaudeAgentOptions
7. 设置 CLAUDE_CONFIG_DIR - session 文件保存在员工目录

**调用关系**:
- 调用: `_load_mcp_servers()`, `_get_system_prompt()`, `_get_skill_names()`
- 被调用: `lifespan()`, `AgentRegistry.create_agent()`

---

### 2. FeishuAgent.process()

**位置**: `app/core/feishu_agent.py:383-476`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| user_input | str | 输入 | 用户消息内容 |
| context | MessageContext | 输入 | 消息上下文（chat_id, user_id） |
| response_text | str | 返回 | Agent 响应文本 |

**内部实现**:
1. 构建 prompt - 包含员工信息（AI诸葛亮）或任务说明（员工）
2. 获取或创建 Client - 每个 chat_id 一个独立 Client
3. 发送 query - 调用 SDK
4. 接收响应流 - 异步迭代
5. 解析 AssistantMessage - TextBlock + ToolUseBlock
6. 等待 ResultMessage - 结束信号
7. 返回响应文本

**调用关系**:
- 调用: `_get_or_create_client()`, `client.query()`, `client.receive_response()`
- 被调用: `MessageHandler.handle()`, `on_employee_message()`

---

### 3. FeishuAgent._get_or_create_client()

**位置**: `app/core/feishu_agent.py:144-210`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| chat_id | str | 输入 | 聊天 ID |
| client | ClaudeSDKClient | 返回 | SDK 客户端实例 |

**内部实现**:
1. 检查 Client 池 - 是否已有对应 chat_id 的 Client
2. 生成 session UUID - 从 employee_id + chat_id 派生
3. 检查 session 文件是否存在 - 决定使用 resume 或 session_id
4. 创建 ClaudeSDKClient - 连接 SDK
5. 存入 Client 池 - 按 chat_id 存储

**关键逻辑**:
- 使用 UUID.uuid5 生成确定性 session_id，保证同一 chat_id 使用相同 session
- resume 参数恢复已存在 session，避免 "Session ID already in use" 错误
- Client 池实现多 chat 记忆隔离

---

### 4. WebSocketManager.start_employee()

**位置**: `app/core/ws_manager.py:64-102`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| employee_id | str | 输入 | 员工 ID |
| app_id | str | 输入 | 飞书 App ID |
| app_secret | str | 输入 | 飞书 App Secret |
| success | bool | 返回 | 启动是否成功 |

**内部实现**:
1. 获取 Python 路径 - sys.executable
2. 创建子进程 - asyncio.create_subprocess_exec()
3. 传入参数 --employee-id, --app-id, --app-secret
4. 创建 EmployeeProcess 对象 - 存入 _processes
5. 启动消息读取任务 - _read_messages(), _read_stderr()

---

### 5. WebSocketManager.restart_employee()

**位置**: `app/core/ws_manager.py:129-220`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| employee_id | str | 输入 | 员工 ID |
| employee_config | dict | 输入 | 员工配置 |
| success | bool | 返回 | 重启是否成功 |

**内部实现**:
1. 停止旧进程 - stop_employee()
2. 清理旧 skills 目录 - 保留 projects（对话记忆）
3. 从数据库读取 skills - SkillCRUD.get_by_name()
4. 写入 SKILL.md - YAML frontmatter + content
5. 复制公共脚本 - shared_scripts/ 到员工目录
6. 启动新进程 - start_employee()
7. 更新数据库状态 - EmployeeCRUD.update_status()
8. 通知 AI诸葛亮 - _notify_ai_zhugeliang()

---

### 6. MessageHandler.handle()

**位置**: `app/handlers/message_handler.py:45-86`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| event | FeishuMessageEvent | 输入 | 飞书消息事件 |
| response_text | str | 返回 | 发送到飞书的回复 |

**内部实现**:
1. 构建 MessageContext - chat_id, user_id, message_id
2. 检查是否需要处理 - 群消息需 @机器人
3. 过滤机器人自己的消息
4. 发送表情反应 - THUMBSUP
5. 提取实际消息内容 - 移除 @提及
6. 调用 Agent 处理 - agent.process()
7. 发送回复消息 - _send_message()

---

### 7. on_employee_message()

**位置**: `app/main.py:499-581`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| data | dict | 输入 | WebSocket 消息 JSON |
| 无返回值 | - | - | 直接发送消息到飞书 |

**内部实现**:
1. 解析事件类型 - im.message.receive_v1 或 card.action.trigger
2. 处理卡片回调 - on_card_callback()
3. 检测确认流程 - detect_confirm_scenario()
4. 发送快速确认 - "收到任务，正在处理..."
5. 构建 MessageContext
6. 调用 Agent 处理 - agent.process()
7. 发送详细结果

---

### 8. ws_listener.do_p2p_im_message_receive_v1()

**位置**: `ws_listener.py:49-76`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| data | P2ImMessageReceiveV1 | 输入 | 飞书 SDK 消息对象 |
| stdout JSON | str | 输出 | 打印到标准输出 |

**内部实现**:
1. 提取 message, sender 信息
2. 构建事件数据 dict
3. 提取消息内容 - _extract_content()
4. 提取 @提及 - _extract_mentions()
5. 输出 JSON - print(json.dumps())

---

### 9. EmployeeCache.refresh()

**位置**: `app/core/employee_cache.py:22-73`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| 无参数 | - | - | 刷新缓存 |
| _cache | dict | 输出 | 员工信息缓存 |

**内部实现**:
1. 查询所有员工 - EmployeeCRUD.list()
2. 清理不在数据库的员工 - 移除过期缓存
3. 过滤非活跃员工 - status != active
4. 获取 skills 详情 - SkillCRUD.get_by_name()
5. 更新缓存 - 保存 skill_names 和 skills_detail

---

### 10. EmployeeCache.get_employee_prompt_section()

**位置**: `app/core/employee_cache.py:131-163`

**输入输出**:
| 参数 | 类型 | 方向 | 描述 |
|------|------|------|------|
| 无参数 | - | - | 生成提示词 |
| prompt_section | str | 返回 | 员工信息提示词段落 |

**内部实现**:
1. 构建 "可用员工" 段落
2. 遍历缓存中的员工
3. 添加员工名称和 bot_open_id
4. 添加技能描述和触发关键词
5. 添加 @员工格式说明和示例

## 数据流分析

### 数据流图

```mermaid
flowchart LR
    subgraph Input["输入"]
        FeishuMsg["飞书消息"]
        UserInput["用户输入"]
    end
    
    subgraph Process["处理"]
        WsListener["ws_listener"]
        JsonParse["JSON 解析"]
        Cache["员工缓存"]
        Agent["FeishuAgent"]
        SDK["Claude SDK"]
        MCP["MCP 工具"]
    end
    
    subgraph Output["输出"]
        FeishuReply["飞书回复"]
        Session["Session 文件"]
        Log["日志文件"]
    end
    
    subgraph Storage["存储"]
        DB["MySQL"]
        SkillsDir["Skills 目录"]
    end
    
    FeishuMsg --> WsListener --> JsonParse
    JsonParse --> Cache --> Agent
    Agent --> SDK --> MCP
    
    DB --> Cache
    SkillsDir --> Agent
    
    Agent --> FeishuReply --> FeishuMsg
    SDK --> Session --> SkillsDir
    WsListener --> Log
```

### 数据流转详情

| 数据类型 | 来源 | 目标 | 格式 |
|---------|------|------|------|
| 飞书消息 | WebSocket | ws_listener stdout | JSON |
| 员工事件 | ws_listener | WsManager | JSON (employee_id, chat_id, content) |
| 员工配置 | MySQL | EmployeeCache | dict (id, name, skills, mcp_servers) |
| Skill 内容 | MySQL | SKILL.md | YAML frontmatter + Markdown |
| Agent prompt | process() | Claude SDK | string (包含员工信息) |
| MCP 工具调用 | Claude SDK | MCP Server | HTTP JSON |
| Session 记录 | Claude SDK | projects/<hash>/<uuid>.jsonl | JSONL |

## 关键决策点

| 位置 | 条件 | 结果 | 说明 |
|------|------|------|------|
| run.py:22 | pgrep 找到旧进程 | 清理进程 | 避免遗留进程冲突 |
| ws_listener.py:64 | event.is_group | 检查 @提及 | 群消息需 @机器人 |
| feishu_agent.py:229 | employee_id 为空 | AI诸葛亮不加载 MCP | 总指挥只分配任务 |
| feishu_agent.py:148 | chat_id in _clients | 返回已有 Client | Client 池复用 |
| feishu_agent.py:159 | session_file.exists() | 使用 resume | 恢复已有 session |
| ws_manager.py:143 | skills_dir.exists() | 清理但保留 projects | 保留对话记忆 |
| main.py:533 | detect_confirm_scenario() | 发送交互卡片 | 确认流程 |

## 异常处理

### 1. WebSocket 连接异常
- **位置**: ws_listener.py
- **处理**: auto_reconnect=True 自动重连
- **日志**: stderr 输出到员工日志文件

### 2. Agent 初始化失败
- **位置**: main.py lifespan
- **处理**: 捕获异常，记录日志，继续启动其他员工

### 3. MCP 工具调用失败
- **位置**: Claude SDK
- **处理**: 返回错误信息，Agent 在响应中说明

### 4. 消息发送失败
- **位置**: message_handler.py
- **处理**: 记录错误日志，不中断处理流程

### 5. 进程终止超时
- **位置**: ws_manager.py stop_employee
- **处理**: 5秒超时后 SIGKILL 强制终止

## 性能考虑

### 1. Client Pool 设计
- 每个 chat_id 一个独立 Client
- 避免 "Session ID already in use" 错误
- 支持多对话并行处理

### 2. 员工缓存定时刷新
- 每 30 秒刷新一次
- 减少 MySQL 查询压力
- AI诸葛亮 动态获取最新员工信息

### 3. 独立进程隔离
- 每个员工独立 WebSocket 进程
- 避免 WebSocket 连接共享冲突
- 进程崩溃不影响其他员工

### 4. Session 持久化
- 使用 resume 参数恢复 session
- 对话记忆保存在 JSONL 文件
- 服务重启不丢失记忆

## 总结

### 核心架构特点

1. **多进程架构**: 主进程管理多个员工子进程，实现隔离和并发
2. **Client Pool**: 每个 chat_id 独立 Client，实现记忆隔离
3. **Skills 动态加载**: 从数据库写入 SKILL.md，重启时更新
4. **MCP HTTP 方式**: 通过 HTTP 调用 MCP Server，无需本地进程

### 设计亮点

- **AI诸葛亮**: 总指挥只分配任务，不加载 MCP，避免直接操作
- **记忆持久化**: UUID.uuid5 生成确定性 session_id，resume 恢复已有 session
- **交互卡片**: 确认流程使用飞书交互卡片，提升用户体验
- **进程真实检查**: 通过 os.kill(pid, 0) 验证进程存活状态

### 可优化方向

- 增加 WebSocket 连接池管理
- 优化 Skills 同步机制（增量更新）
- 增加健康检查和自动恢复机制
- 支持 Agent 状态持久化