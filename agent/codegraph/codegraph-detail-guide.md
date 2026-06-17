# CodeGraph：代码知识图谱工具详解

> GitHub: https://github.com/colbymchenry/codegraph  
> npm: `@colbymchenry/codegraph`

## 一、项目概述

CodeGraph 是一个**本地优先的代码智能工具**，通过预构建代码知识图谱，为AI 编程助手提供精确的代码上下文，大幅节省Token消耗。

**核心数据（官方基准测试）：**
| 指标 | 平均节省 |
|------|----------|
| 成本 | ~16% cheaper |
| Tokens | ~47% fewer |
| 时间 | ~22% faster |
| 工具调用 | ~58% fewer |

**测试覆盖：** 7 个真实开源代码库，跨 7 种语言，每种 4 次运行取中位数。

---

## 二、支持的 AI 编程助手

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

## 三、快速安装

### 3.1 安装 CLI

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.ps1 | iex
```

**npm 安装（已有 Node.js）:**
```bash
npm i -g @colbymchenry/codegraph
```

### 3.2 连接到 AI 编程助手

```bash
codegraph install
```

此命令会自动检测并配置已安装的 AI 编程助手，将 CodeGraph MCP server 接入。

### 3.3 初始化项目

```bash
cd your-project
codegraph init -i   # -i 表示同时构建初始图谱
```

---

## 四、核心功能

### 4.1 MCP 工具列表

| 工具 | 功能 | 使用场景 |
|------|------|----------|
| `codegraph_explore` | **主要工具** -一次调用返回相关代码源码 | 理解代码流程、架构、bug定位 |
| `codegraph_search` | 快速符号搜索（只返回位置） | 查找符号定义位置 |
| `codegraph_node` | 获取单个符号详情（签名、调用链、源码） | 深入了解单个符号 |
| `codegraph_callers` | 查找调用者 | 影响分析 |
| `codegraph_callees` | 查找被调用者 | 流程追踪 |
| `codegraph_impact` | 影响半径分析 | 重构前评估 |
| `codegraph_files` |索引文件树 | 快速了解项目结构 |
| `codegraph_status` | 索引健康检查 | 调试用 |

### 4.2 核心特点

| 特点 | 说明 |
|------|------|
| **Smart Context Building** | 一次工具调用返回入口点、相关符号和代码片段 |
| **Full-Text Search** | FTS5 驱动的即时符号搜索 |
| **Impact Analysis** |追踪调用者、被调用者、影响半径 |
| **Always Fresh** | 文件监控 + 自动同步，图谱实时更新 |
| **100% Local** | 数据不离开机器，SQLite 本地存储 |

---

## 五、支持的语言

**20+ 种语言：**

| 类别 | 语言 |
|------|------|
| 前端 | TypeScript, JavaScript, Svelte |
| 后端 | Python, Go, Rust, Java, C#, PHP, Ruby |
| 移动端 | Swift, Kotlin, Dart, Objective-C |
| 其他 | C, C++, Lua, Luau, Liquid, Pascal/Delphi |

---

## 六、框架路由识别

CodeGraph 能识别 14 种 Web 框架的路由文件，将 URL 模式链接到处理函数：

| 框架 | 识别的路由形式 |
|------|----------------|
| **Django** | `path()`, `re_path()`, `url()`, `include()` |
| **Flask** | `@app.route('/path')`, blueprint routes |
| **FastAPI** | `@app.get()`, `@router.post()` |
| **Express** | `app.get()`, `router.post()` |
| **NestJS** | `@Controller`, `@Get/@Post`, GraphQL `@Resolver` |
| **Laravel** | `Route::get()`, `Route::resource()` |
| **Rails** | `get '/x', to: 'users#index'` |
| **Spring** | `@GetMapping`, `@RequestMapping` |
| **Gin / chi** | `r.GET()`, `router.HandleFunc()` |
| **Axum / actix** | `.route("/x", get(handler))` |
| **ASP.NET** | `[HttpGet("/x")]` attributes |
| **Vapor** | `app.get("x", use: handler)` |
| **React Router** | Route component nodes |
| **SvelteKit** | Route component nodes |

---

## 七、跨语言桥接

支持 iOS / React Native / Expo 的跨语言调用追踪：

| 场景 | JS/Swift端 | Native端 | 桥接方式 |
|------|-----------|----------|----------|
| Swift → ObjC | `obj.foo(bar:)` | `-fooWithBar:` | `@objc`自动桥接 |
| ObjC → Swift | `[obj fooWithBar:]` | `func foo(bar:)` | 反向桥接 |
| RN Legacy Bridge | `NativeModules.X.fn()` | `RCT_EXPORT_METHOD` | Macro解析 |
| RN TurboModules | `NativeM.fn()` | Codegen spec | 规范匹配 |
| Native → JS Events | `addListener('e', cb)` | `sendEventWithName:@"e"` | 事件名匹配 |
| Expo Modules | `requireNativeModule('X')` | `Module { Name("X") }` | DSL解析 |
| Fabric Components | `<MyView prop={v}/>` | Codegen spec + native impl | 规范桥接 |

---

## 八、基准测试数据

### 8.1 各项目详细数据

| 代码库 | 语言 | 文件数 | 成本 | Tokens | 时间 | 工具调用 |
|--------|------|--------|------|--------|------|----------|
| **VS Code** | TypeScript | ~10k | 18% cheaper | 64% fewer | 11% faster | 81% fewer |
| **Excalidraw** | TypeScript | ~640 | even | 25% fewer | 27% faster | 40% fewer |
| **Django** | Python | ~3k | 8% cheaper | 60% fewer | 13% faster | 77% fewer |
| **Tokio** | Rust | ~790 | even | 38% fewer | 18% faster | 57% fewer |
| **OkHttp** | Java | ~645 | 25% cheaper | 54% fewer | 31% faster | 50% fewer |
| **Gin** | Go | ~110 | 19% cheaper | 23% fewer | 24% faster | 44% fewer |
| **Alamofire** | Swift | ~110 | 40% cheaper | 64% fewer | 33% faster | 58% fewer |

### 8.2 为什么 CodeGraph 节省资源

```
无 CodeGraph：
  AI 扫描所有文件 → 逐个读取 → 分析 → 返回答案
  问题：大量 Token消耗、工具调用、上下文污染

有 CodeGraph：
  AI 查询预构建图谱 →精准定位 → 只读取必要代码 → 返回答案
  优势：Token 少、工具调用少、速度快
```

---

## 九、自动同步机制

三层机制确保图谱实时更新：

| 层级 | 机制 | 说明 |
|------|------|------|
| **1. 文件监控** | FSEvents / inotify / RDCW | 监控文件变更，2秒 debounce后同步 |
| **2. 陈旧提示** | `⚠️` banner | 变更文件未同步时提示 AI直接 Read |
| **3. 连接时同步** | catch-up sync | MCP server 启动时同步离线期间的变更 |

---

## 十、项目架构

### 10.1 目录结构

```
src/
├── index.ts          # CodeGraph 主类
├── bin/              # CLI 命令
├── db/               # SQLite 数据库层
├── extraction/       #代码提取（tree-sitter）
│   └── languages/    # 各语言提取器
├── resolution/       # 引用解析
│   └── frameworks/   #框架路由识别
├── graph/            # 图遍历算法
├── context/          # 上下文构建
├── search/           # FTS5 全文搜索
├── sync/             # 文件监控同步
├── mcp/              # MCP server
└── installer/        # 多助手安装器
```

### 10.2 数据流

```
文件 → ExtractionOrchestrator (tree-sitter) → DB (nodes/edges/files)
           ↓
    ReferenceResolver (imports, name-matching, framework patterns)
           ↓
    GraphQueryManager / GraphTraverser (callers, callees, impact)
           ↓
    ContextBuilder (markdown/JSON for AI consumption)
```

---

## 十一、NodeKind / EdgeKind

### 11.1节点类型

```
file, module, class, struct, interface, trait, protocol,
function, method, property, field, variable, constant,
enum, enum_member, type_alias, namespace, parameter,
import, export, route, component
```

### 11.2 边类型

```
contains, calls, imports, exports, extends, implements,
references, type_of, returns, instantiates, overrides, decorates
```

---

## 十二、卸载

```bash
codegraph uninstall
```

移除所有已配置助手中的 CodeGraph MCP server。

---

## 总结

| 核心价值 | 说明 |
|----------|------|
| **预索引** | 不读代码就能理解项目结构 |
| **本地运行** | 100% 本地，数据安全 |
| **节省资源** | 平均节省 47% Token、58% 工具调用 |
| **多助手支持** | Claude Code、Cursor、Codex 等8 种 |
| **跨语言桥接** | iOS / React Native / Expo 跨语言调用追踪 |
| **框架路由识别** | 14 种 Web 框架路由自动识别 |

---

## 参考资料

- GitHub: https://github.com/colbymchenry/codegraph
- 文档: https://colbymchenry.github.io/codegraph/
- npm: https://www.npmjs.com/package/@colbymchenry/codegraph
- 视频来源: https://v.douyin.com/YHkhqm1WcMA/