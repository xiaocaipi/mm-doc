# CodeGraph 使用指南

> GitHub: https://github.com/colbymchenry/codegraph  
> npm: `@colbymchenry/codegraph`

## 一、什么是 CodeGraph

CodeGraph 是一个**本地优先的代码智能工具**，通过预构建代码知识图谱，为 AI 编程助手提供精确的代码上下文，大幅节省 Token 消耗。

### 1.1 核心价值

| 指标 | 平均节省 |
|------|----------|
| 成本 | ~16% cheaper |
| Tokens | ~47% fewer |
| 时间 | ~22% faster |
| 工具调用 | ~58% fewer |

### 1.2 支持的 AI 编程助手

| 工具 | 支持状态 |
|------|----------|
| Claude Code | ✅ 支持 |
| Cursor | ✅ 支持 |
| Codex CLI | ✅ 支持 |
| opencode | ✅ 支持 |
| Hermes Agent | ✅ 支持 |
| Gemini CLI | ✅ 支持 |
| Antigravity IDE | ✅ 支持 |
| Kiro | ✅ 支持 |

---

## 二、安装

### 2.1 安装 CLI

**方式一：脚本安装（无需 Node.js）**

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh

# Windows (PowerShell)
irm https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.ps1 | iex
```

**方式二：npm 安装**

```bash
npm i -g @colbymchenry/codegraph
```

### 2.2 连接到 AI 编程助手

```bash
# 全局安装（推荐）- 所有项目都能用
codegraph install --target=auto --location=global --yes

# 项目本地安装 - 只当前项目可用
codegraph install --target=auto --location=local

# 交互式安装（会提示选择）
codegraph install
```

### 2.3 初始化项目索引

```bash
cd /path/to/your/project
codegraph init -i    # -i 表示同时构建初始图谱
```

---

## 三、Global vs Local 配置

### 3.1 参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `--target` | `auto` | 自动检测已安装的助手 |
| `--target` | `all` | 配置所有支持的助手 |
| `--target` | `claude` | 只配置 Claude Code |
| `--target` | `claude,cursor` | 配置指定的多个助手 |
| `--location` | `global` | 全局配置，所有项目可用 |
| `--location` | `local` | 项目本地配置，只当前项目可用 |

### 3.2 配置文件位置

| location | 配置文件位置 | 生效范围 |
|----------|--------------|----------|
| `global` | `~/.claude/settings.json` | 所有项目 |
| `local` | `/项目/.mcp.json` | 当前项目 |

### 3.3 选择建议

| 场景 | 推荐 |
|------|------|
| 个人开发 | `--location=global` |
| 团队协作 | `--location=local`（配置随项目分发） |
| 只用 Claude Code | `--target=claude` |
| 多助手用户 | `--target=auto` |

---

## 四、MCP 配置文件详解

### 4.1 .mcp.json 是什么

**MCP = Model Context Protocol（模型上下文协议）**

`.mcp.json` 是 MCP server 的配置文件，告诉 Claude Code 如何启动外部工具。

### 4.2 配置内容示例

```json
{
  "mcpServers": {
    "codegraph": {
      "type": "stdio",
      "command": "codegraph",
      "args": ["serve", "--mcp"]
    }
  }
}
```

**含义：**
- `type`: 通信方式（stdio = 标准输入输出）
- `command`: 启动命令
- `args`: 命令参数

### 4.3 Claude Code 配置加载机制

```
Claude Code 启动时：
    ↓
查找当前目录的 .mcp.json（local）
或读取 ~/.claude/settings.json（global）
    ↓
发现 MCP server 配置
    ↓
执行命令启动 MCP server
    ↓
获取工具列表
    ↓
用户可以直接使用这些工具
```

---

## 五、MCP 工具列表

### 5.1 可用工具

| 工具 | 功能 | 使用场景 |
|------|------|----------|
| `codegraph_explore` | **主要工具** - 一次调用返回相关代码源码 | 理解代码流程、架构、bug定位 |
| `codegraph_search` | 快速符号搜索（只返回位置） | 查找符号定义位置 |
| `codegraph_node` | 获取单个符号详情（签名、调用链、源码） | 深入了解单个符号 |
| `codegraph_callers` | 查找调用者 | 影响分析 |
| `codegraph_callees` | 查找被调用者 | 流程追踪 |
| `codegraph_impact` | 影响半径分析 | 重构前评估 |
| `codegraph_files` | 索引文件树 | 快速了解项目结构 |
| `codegraph_status` | 索引健康检查 | 调试用 |

### 5.2 工具调用示例

```javascript
// 理解代码流程
codegraph_explore({
  query: "AuthService loginUser"
})

// 查找符号位置
codegraph_search({
  query: "PaymentService",
  kind: "class"
})

// 分析修改影响
codegraph_impact({
  symbol: "loginUser",
  depth: 2
})

// 跨项目查询
codegraph_explore({
  query: "UserService",
  projectPath: "/path/to/other/project"
})
```

---

## 六、Claude Code 如何触发 MCP Tool

### 6.1 完整流程

```
Step 1: Claude Code 启动
    ↓
读取 MCP 配置
    ↓
执行命令：codegraph serve --mcp
    ↓
MCP server 进程启动

Step 2: MCP 协议握手
    ↓
Claude Code ↔ MCP Server
    ↓
Claude: "你有哪些工具？"
    ↓
Server: 返回工具列表

Step 3: 用户提问
    ↓
用户："AuthService 是怎么工作的？"
    ↓
Claude 分析问题，决定使用工具
    ↓
选择：codegraph_explore

Step 4: Claude 调用 MCP Tool
    ↓
通过 stdio 发送 JSON-RPC 请求
    ↓
MCP server 执行，返回结果
    ↓
Claude 收到结果，继续处理
```

### 6.2 通信方式

```
Claude Code (父进程)
      ↓↑ stdin/stdout
MCP Server (子进程)

Claude 写入 stdout → Server 从 stdin读取
Server 写入 stdout → Claude 从 stdin读取
```

### 6.3 JSON-RPC 消息格式

**请求：**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codegraph_explore",
    "arguments": {
      "query": "AuthService"
    }
  }
}
```

**响应：**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "## AuthService\n\n找到以下代码..."
      }
    ]
  }
}
```

---

## 七、多会话与跨项目查询

### 7.1 多个 Claude Code 会话

**每个会话启动独立的 MCP server 进程：**

```
Claude 会话 1 → codegraph serve --mcp (进程 1)
Claude 会话 2 → codegraph serve --mcp (进程 2)
Claude 会话 3 → codegraph serve --mcp (进程 3)
```

**SQLite WAL 模式处理并发：**
- 多个读者可以同时访问
- 写入者独占，其他等待
- 不会数据损坏

### 7.2 跨项目查询流程

**场景：在路径 C 启动 Claude，查询项目 A 和项目 B**

```
路径 C（启动 Claude Code）
    ↓
MCP server 启动
    ↓
调用工具时指定 projectPath：
    ↓
codegraph_explore({
  query: "AuthService",
  projectPath: "/项目A"
})
    ↓
MCP server 去/项目A/.codegraph/ 查找索引
    ↓
返回结果
```

**前提条件：**
- 目标项目必须已初始化索引（`codegraph init -i`）
- 目标项目必须有 `.codegraph/` 目录

### 7.3 索引查找机制

| 方式 | 说明 |
|------|------|
| 当前目录 | 查找当前目录的 `.codegraph/` |
| 向上查找 | 向父目录查找，类似 git 找 `.git/` |
| 参数指定 | `projectPath: "/path/to/project"` |

---

## 八、支持的语言和框架

### 8.1 支持的语言（20+）

| 类别 | 语言 |
|------|------|
| 前端 | TypeScript, JavaScript, Svelte |
| 后端 | Python, Go, Rust, Java, C#, PHP, Ruby |
| 移动端 | Swift, Kotlin, Dart, Objective-C |
| 其他 | C, C++, Lua, Luau, Liquid, Pascal/Delphi |

### 8.2 支持的框架路由（14种）

| 框架 | 识别的路由形式 |
|------|----------------|
| Django | `path()`, `re_path()`, `url()` |
| Flask | `@app.route('/path')` |
| FastAPI | `@app.get()`, `@router.post()` |
| Express | `app.get()`, `router.post()` |
| NestJS | `@Controller`, `@Get/@Post` |
| Laravel | `Route::get()`, `Route::resource()` |
| Rails | `get '/x', to: 'users#index'` |
| Spring | `@GetMapping`, `@RequestMapping` |
| Gin | `r.GET()` |
| ASP.NET | `[HttpGet("/x")]` |

---

## 九、完整使用流程示例

### 9.1 最佳实践命令序列

```bash
# Step 1: 全局安装 CLI
npm i -g @colbymchenry/codegraph

# Step 2: 连接到 AI 助手（全局）
codegraph install --target=auto --location=global --yes

# Step 3: 在项目中初始化索引
cd /path/to/your/project
codegraph init -i

# Step 4: 验证状态
codegraph status

# Step 5: 启动 Claude Code 使用
claude
```

### 9.2 团队协作配置

```bash
# 项目本地安装
cd /path/to/project
codegraph install --target=claude --location=local

# 配置随项目分发，团队成员克隆后：
git clone /path/to/project
cd project
codegraph init -i
```

---

## 十、常见问题

### 10.1 配置问题

| 问题 | 解决方案 |
|------|----------|
| 其他目录不能用 CodeGraph | 使用 `--location=global` 全局安装 |
| 找不到索引 | 确保项目已执行 `codegraph init -i` |
| 多会话冲突 | SQLite WAL 模式自动处理，无需担心 |

### 10.2 使用问题

| 问题 | 解决方案 |
|------|----------|
| 索引过时 | 自动同步，无需手动操作 |
| 大型项目索引慢 | 正常现象，索引后查询极快 |
| 跨项目查询报错 | 确保目标项目已初始化索引 |

---

## 十一、卸载

```bash
# 移除所有助手配置
codegraph uninstall

# 移除项目索引
cd your-project
codegraph uninit
```

---

## 十二、总结

### 核心概念

| 概念 | 说明 |
|------|------|
| **MCP** | Model Context Protocol，AI 连接外部工具的协议 |
| **.mcp.json** | MCP server 配置文件 |
| **MCP server** | 提供工具的服务进程 |
| **stdio** | Claude Code 与 MCP server 的通信方式 |
| **.codegraph/** | 项目索引目录（SQLite 数据库） |

### 关键流程

```
安装CLI → 连接 AI 助手 → 初始化项目索引 → Claude Code 自动调用工具
```

### 最佳实践

| 场景 | 推荐 |
|------|------|
| 个人开发 | `--location=global --target=auto` |
| 团队协作 | `--location=local` + 提交 `.mcp.json` |
| 跨项目查询 | 指定 `projectPath` 参数 |

---

## 参考资料

- GitHub: https://github.com/colbymchenry/codegraph
- 文档: https://colbymchenry.github.io/codegraph/
- npm: https://www.npmjs.com/package/@colbymchenry/codegraph