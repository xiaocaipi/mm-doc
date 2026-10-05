# Codex 调用 Claude/GLM MCP 使用文档

## 1. 背景

当前机器已有 Claude Code 启动包装脚本：

```bash
/root/e1.sh
```

该脚本会设置 DashScope Anthropic 兼容接口相关环境变量，并执行 `claude "$@"`。

`/root/e1.sh` 本身不是 MCP Server。Codex 不能直接把它当 MCP 使用，因此增加了一层 stdio MCP Server：

```bash
/data/caidanfeng/project/sessions/codex/s1/mcp/claude_glm_server.py
```

当前目标不是“第二意见顾问模式”，而是“任务模式”：Codex 通过 MCP 把任务下发给 Claude Code，由 Claude Code 自己在指定目录中执行任务，最后把结果返回给 Codex。

链路如下：

```text
Codex -> MCP tools/call -> claude_glm_server.py -> /root/e1.sh -> Claude Code -> DashScope glm-5 -> 最终结果返回 Codex
```

## 2. 当前文件

MCP Server：

```bash
/data/caidanfeng/project/sessions/codex/s1/mcp/claude_glm_server.py
```

本地 README：

```bash
/data/caidanfeng/project/sessions/codex/s1/mcp/README.md
```

Claude/GLM wrapper：

```bash
/root/e1.sh
```

注意：`/root/e1.sh` 中包含明文 token，排查时不要把完整内容贴到公共文档、issue、PR 或聊天中。

## 3. MCP 工具

当前只暴露一个工具：

```text
run_claude_glm_task
```

用途：把一个真实 Claude Code 任务委托给 Claude/GLM 执行，并返回最终结果。

参数：

```json
{
  "task": "必填，要交给 Claude Code 执行的完整任务",
  "cwd": "可选，任务工作目录，默认是 MCP Server 启动目录",
  "system_prompt": "可选，追加系统提示词",
  "timeout_sec": "可选，默认 900 秒，最大 3600 秒",
  "permission_mode": "可选，默认 acceptEdits",
  "allowed_tools": "可选，默认 Read,Grep,Glob,Bash,Edit,Write"
}
```

默认执行方式接近：

```bash
bash /root/e1.sh \
  --bare \
  --print \
  --output-format text \
  --no-session-persistence \
  --permission-mode acceptEdits \
  --allowedTools Read,Grep,Glob,Bash,Edit,Write \
  --add-dir "$cwd" \
  --system-prompt "..." \
  "$task"
```

这意味着 Claude Code 可以在指定目录内读取、搜索、执行命令、编辑和写入文件。

每次调用都会创建任务落盘目录：

```text
/data/caidanfeng/project/sessions/codex/s1/mcp/tasks/
```

MCP 返回结果中会包含本次调用的 `Task dir`。每个任务目录包含：

```text
request.json   原始工具参数和解析后的 cwd
command.json   执行命令摘要，鉴权信息已打码
status.json    running/succeeded/failed/timeout 状态
stdout.txt     Claude Code stdout，运行过程中直接写入
stderr.txt     Claude Code stderr，运行过程中直接写入
result.txt     MCP wrapper 完成时写入的最终返回文本
```

如果 Codex 外层等待 `tools/call` 超时，可以先看最新任务目录。若 `status.json` 仍是 `running`，通常表示外层调用先停止等待，wrapper 没来得及写最终状态；此时 `stdout.txt` 和 `stderr.txt` 仍可能保留已经产生的输出。

## 4. Codex 注册方式

已经执行过全局注册：

```bash
codex mcp add claude_glm -- /data/caidanfeng/project/sessions/codex/s1/mcp/claude_glm_server.py
```

也可以手动写入 `~/.codex/config.toml`：

```toml
[mcp_servers.claude_glm]
command = "/data/caidanfeng/project/sessions/codex/s1/mcp/claude_glm_server.py"
startup_timeout_sec = 20
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

这里有两层超时：

1. `tool_timeout_sec` 是 Codex 等 MCP `tools/call` 返回的外层超时。
2. `timeout_sec` 是 `run_claude_glm_task` 内部等待 Claude Code 子进程的超时。

如果调用参数里传 `timeout_sec=900`，但配置里没有 `tool_timeout_sec` 或仍是 300 秒，Codex 外层会先报：

```text
timed out awaiting tools/call after 300s
```

因此长任务应保证 `tool_timeout_sec` 大于等于常用的 `timeout_sec`。当前已配置为 1200 秒。

注册后建议重启 Codex，或开一个新的 Codex 任务。

## 5. 状态确认

查看 MCP 注册状态：

```bash
codex mcp list
```

应看到：

```text
claude_glm  /data/caidanfeng/project/sessions/codex/s1/mcp/claude_glm_server.py  enabled
```

在 Codex TUI 或桌面端中，也可以通过 `/mcp` 检查 `claude_glm` 是否已连接。

## 6. 工具列表验证

执行：

```bash
printf '%s\n' \
'{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
| /data/caidanfeng/project/sessions/codex/s1/mcp/claude_glm_server.py
```

应只看到一个工具：

```text
run_claude_glm_task
```

## 7. 端到端测试

真实 MCP 调用示例：

```bash
printf '%s\n' \
'{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"run_claude_glm_task","arguments":{"task":"只回复四个字：链路连通","timeout_sec":120,"allowed_tools":""}}}' \
| /data/caidanfeng/project/sessions/codex/s1/mcp/claude_glm_server.py
```

成功时返回类似：

```json
{"jsonrpc":"2.0","id":12,"result":{"content":[{"type":"text","text":"链路连通"}]}}
```

如果要让 Claude Code 做真实项目任务，需要指定 `cwd`，例如：

```json
{
  "task": "在当前项目中修复 XXX 问题，完成后说明修改和验证结果",
  "cwd": "/data/caidanfeng/project/sessions/codex/s1",
  "timeout_sec": 1800
}
```

## 8. 已处理的问题

### 8.1 `/root/e1.sh` 没有 shebang

直接执行 `/root/e1.sh` 会报：

```text
OSError: [Errno 8] Exec format error: '/root/e1.sh'
```

当前 MCP Server 已改为：

```bash
bash /root/e1.sh ...
```

因此无需修改 `/root/e1.sh`。

### 8.2 Claude CLI 没有自动带 Authorization header

`/root/e1.sh` 设置的是：

```bash
ANTHROPIC_AUTH_TOKEN=...
```

但 Claude Code 2.1.197 debug 中不会自动把它转成 DashScope 兼容接口需要的：

```bash
Authorization: Bearer <token>
```

当前 MCP Server 会从 `/root/e1.sh` 读取既有 token，并在调用 Claude CLI 前设置：

```bash
ANTHROPIC_CUSTOM_HEADERS="Authorization: Bearer <token>"
```

不要在日志中打印真实 token。

### 8.3 代理问题

当前环境需要代理访问 DashScope。沙箱内可能出现：

```text
curl: (7) Failed to connect to 10.4.196.74 port 3128
```

绕过代理时可能出现：

```text
Could not resolve host: coding.dashscope.aliyuncs.com
```

如果 MCP 调用超时，优先检查代理环境：

```bash
env | rg -i '^(http|https|all|no)_proxy='
```

## 9. 直接验证 DashScope 接口

绕过 Claude CLI，直接验证 DashScope Anthropic 兼容接口：

```bash
curl -sS -i --max-time 30 \
  https://coding.dashscope.aliyuncs.com/apps/anthropic/v1/messages \
  -H 'content-type: application/json' \
  -H 'anthropic-version: 2023-06-01' \
  -H "Authorization: Bearer $(sed -n 's/^export ANTHROPIC_AUTH_TOKEN=//p' /root/e1.sh)" \
  --data '{"model":"glm-5","max_tokens":32,"messages":[{"role":"user","content":"只回复四个字：接口连通"}]}'
```

成功时响应中会包含：

```json
{
  "model": "glm-5",
  "content": [
    {
      "type": "text",
      "text": "接口连通"
    }
  ]
}
```

## 10. 使用方式

在 Codex 中直接说：

```text
用 claude_glm 的 run_claude_glm_task 在当前目录执行这个任务：...
```

或：

```text
把这个问题交给 run_claude_glm_task 处理，cwd 用当前项目目录，timeout 给 1800 秒
```

建议在任务描述中明确：

1. 目标是什么。
2. 工作目录是什么。
3. 是否允许修改文件。
4. 需要跑哪些验证。
5. 最终需要返回什么结果。

## 11. 风险提醒

`run_claude_glm_task` 是真实任务模式，不是只读顾问模式。默认允许 Claude Code 使用：

```text
Read,Grep,Glob,Bash,Edit,Write
```

因此它可能会修改工作区文件。使用前应确认：

1. `cwd` 指向正确项目目录。
2. 当前 git 工作区中已有变更不会被误伤。
3. 长任务设置足够的 `timeout_sec`。
4. 最终由 Codex 或人工再检查一次 diff 和验证结果。
