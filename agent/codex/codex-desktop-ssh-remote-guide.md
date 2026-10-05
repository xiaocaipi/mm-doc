# Codex Desktop 通过 SSH 使用远程项目

本文记录 Codex Desktop 通过 SSH 连接远程服务器、打开远程项目，并在企业 HTTP 代理环境中正常使用 GPT-5.6 的配置与排障方法。

## 1. 当前环境

- 客户端：Windows Codex Desktop
- 远程服务器：`root@172.20.25.104`
- 系统：Rocky Linux 8.6
- 远程项目：`/data/caidanfeng/project/sessions`
- Codex CLI：`0.144.1`
- Node.js：`18.20.8`
- Codex 安装路径：`/root/.nvm/versions/node/v18.20.8/bin/codex`
- 代理 wrapper 修复脚本：`/root/bin/fix-codex-proxy-wrapper.sh`
- 代理环境文件：`/root/.codex_proxy_env`

> 安全提示：代理用户名和密码不得写入仓库或本文档。`/root/.codex_proxy_env` 必须保持 `600` 权限，修复脚本应保持仅 root 可读写执行。

## 2. 正确的使用架构

Codex Desktop 打开 SSH 远程项目时，会在服务器上自动启动：

```text
codex app-server
codex app-server proxy
```

模型请求、文件访问和命令执行由远程 app-server 完成，桌面版负责界面和任务交互。

因此：

- 在 Codex Desktop 中连接 SSH 主机并选择远程项目目录。
- 在桌面版任务窗口中提交需求。
- 不需要在远程 Terminal 中再次运行交互式 `codex` TUI。
- 终端 `codex` TUI 与桌面版远程 app-server 是不同的交互路径，不能用 TUI 是否转圈来判断桌面版远程连接是否正常。

## 3. 本次问题现象

排障过程中出现过以下现象：

1. 模型列表只有 GPT-5.5，看不到 GPT-5.6。
2. `models_cache.json` 显示旧客户端版本，例如 `0.141.0`。
3. 多个旧的 app-server 同时运行并争用控制 socket。
4. 日志出现：

   ```text
   app-server control socket is already in use
   ```

5. 服务器无法直接连接 `api.openai.com:443`，必须经过企业代理。
6. 只在 `.bashrc` 中配置代理不能保证 Codex Desktop 的 SSH 启动命令继承代理。
7. `git config --global http.proxy ...` 只影响 Git，不影响 Codex。

## 4. 根因

最终确认有三个关键原因：

### 4.1 服务器没有 OpenAI 直连出口

服务器直连 OpenAI 端口 443 会超时。通过企业代理访问以下端点可以建立 TLS 并获得正常的未鉴权响应：

- `https://api.openai.com/v1/models` 返回 `401`
- `https://chatgpt.com/backend-api/codex/models` 返回 `401`

这里的 `401` 表示网络链路已打通，只是测试请求没有携带认证信息。

### 4.2 SSH 自动启动不一定读取交互式 shell 配置

Codex Desktop 使用非交互 SSH 命令启动远程 app-server。仅在 `.bashrc` 中写 `HTTP_PROXY`/`HTTPS_PROXY` 不够稳定，因此代理需要加在实际 `codex` 可执行入口外层。

### 4.3 旧 app-server 和控制 socket 没有退出

重启桌面版并不一定立即结束服务器上的旧进程。旧主服务继续持有：

```text
/root/.codex/app-server-control/app-server-control.sock
```

新桌面连接只能启动 proxy，无法启动新的主 app-server，最终表现为模型缓存不刷新、连接异常或 socket 冲突。

## 5. 最终代理 wrapper 方案

现有修复脚本：

```text
/root/bin/fix-codex-proxy-wrapper.sh
```

脚本会执行以下操作：

1. 将原始 Codex 启动入口移动为：

   ```text
   /root/.nvm/versions/node/v18.20.8/bin/codex.real
   ```

2. 在原路径创建 wrapper：

   ```text
   /root/.nvm/versions/node/v18.20.8/bin/codex
   ```

3. wrapper 加载：

   ```text
   /root/.codex_proxy_env
   ```

4. 最后执行真实的 `codex.real` 并原样传递参数。

代理环境文件需要同时设置大小写变量：

```bash
export HTTP_PROXY="http://<username>:<url-encoded-password>@<proxy-host>:3128"
export HTTPS_PROXY="$HTTP_PROXY"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"
```

安装或刷新 wrapper 时，应明确指定 NVM 中的 Codex 路径，避免误包装其他软链接：

```bash
CODEX_BIN=/root/.nvm/versions/node/v18.20.8/bin/codex \
  /root/bin/fix-codex-proxy-wrapper.sh
```

为了兼容已经缓存过旧路径的 shell，保留以下软链接：

```text
/root/.local/bin/codex -> /root/.nvm/versions/node/v18.20.8/bin/codex
```

验证入口：

```bash
which codex
codex --version
ls -l /root/.local/bin/codex
ls -l /root/.nvm/versions/node/v18.20.8/bin/codex*
```

如果 Bash 仍缓存已经删除的旧路径，可执行：

```bash
hash -r
```

## 6. 清理旧 app-server 并重新连接

执行此步骤前，应先在 Codex Desktop 中关闭远程项目或退出桌面版，避免中断正在运行的任务。

查看进程：

```bash
ps -eo pid,lstart,comm,args | grep '[c]odex.*app-server'
```

仅结束 `comm` 为 `codex` 且参数包含 `app-server` 的进程：

```bash
ps -eo pid=,comm=,args= \
  | awk '$2 == "codex" && $0 ~ /app-server/ {print $1}' \
  | xargs -r kill -TERM
```

等待几秒后，确认没有遗留的原生 Codex app-server，再清理控制文件：

```bash
rm -f /root/.codex/app-server-control/app-server-control.sock
rm -f /root/.codex/app-server-control/desktop-ssh-websocket-v0.sock
rm -f /root/.codex/app-server-control/app-server-startup.lock
```

随后重新打开 Codex Desktop、连接服务器并打开：

```text
/data/caidanfeng/project/sessions
```

桌面版会自动重新启动一组主 app-server 和 proxy。

## 7. 验证远程桌面链路

### 7.1 检查进程时间

```bash
ps -eo pid,lstart,comm,args | grep '[c]odex.*app-server'
```

正常情况下应看到本次重连时间对应的：

- 一组 `codex ... app-server --listen unix://`
- 一组 `codex app-server proxy`

### 7.2 检查控制 socket 持有者

```bash
fuser /root/.codex/app-server-control/app-server-control.sock
```

输出 PID 应对应新的主 app-server。

### 7.3 检查主服务是否继承代理

将 `<PID>` 替换为主 app-server 的原生 `codex` PID：

```bash
strings /proc/<PID>/environ \
  | cut -d= -f1 \
  | grep -E '^(HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy|NO_PROXY|no_proxy)$' \
  | sort
```

这里只检查变量名，避免把代理凭据打印到终端。

### 7.4 检查模型缓存

```bash
jq '{client_version,fetched_at,models:[.models[]|.slug]}' \
  /root/.codex/models_cache.json
```

本次修复后的期望结果：

- `client_version` 为 `0.144.1`
- 模型列表包含：
  - `gpt-5.6-sol`
  - `gpt-5.6-terra`
  - `gpt-5.6-luna`
  - `gpt-5.5`

### 7.5 检查代理基础连通性

不要在命令行中直接写密码，也不要开启 `set -x`。可临时加载受保护的环境文件：

```bash
set -a
source /root/.codex_proxy_env
set +a

curl -sS --connect-timeout 8 --max-time 15 \
  -o /dev/null -w 'HTTP %{http_code}\n' \
  https://api.openai.com/v1/models
```

未携带 API Key 时返回 `401` 即代表网络和 TLS 正常。

## 8. 常见问题

### 模型缓存仍显示 `0.141.0`

说明旧插件或旧 app-server 仍在写缓存。检查所有 Codex 进程的实际二进制路径和启动时间，停止旧进程后重新连接桌面版。

### 出现 `app-server control socket is already in use`

先用 `fuser` 确认 socket 是否由当前主服务持有：

- 若由当前新主服务持有，且桌面版可用，通常只是重复启动探测产生的日志。
- 若由旧进程持有，关闭桌面版、停止旧 app-server、删除失主 socket 后重连。

### `which codex` 正确，但执行时提示旧路径不存在

Bash 可能缓存了旧命令路径。执行 `hash -r`，或确认 `/root/.local/bin/codex` 兼容软链接存在。

### Git 配置了代理，但 Codex 仍无法访问网络

以下配置只影响 Git：

```bash
git config --global http.proxy  "http://<proxy>"
git config --global https.proxy "http://<proxy>"
```

它们不会传递给 Codex。随后执行 `git config --global --unset ...` 还会立即取消 Git 代理。

### 远程 Terminal 中运行 `codex` 一直显示 Working

这属于 CLI TUI 路径，不等同于桌面版 SSH app-server。桌面版远程开发应直接在桌面任务窗口工作，不需要在远程 Terminal 再启动一个 TUI。

## 9. 回滚 wrapper

如需恢复原始 Codex 入口：

```bash
CODEX_BIN=/root/.nvm/versions/node/v18.20.8/bin/codex \
  /root/bin/fix-codex-proxy-wrapper.sh --restore
```

回滚后检查：

```bash
ls -l /root/.nvm/versions/node/v18.20.8/bin/codex*
codex --version
```

如果仍保留兼容软链接，应确认它指向恢复后的真实入口。

## 10. 安全注意事项

1. 代理密码必须 URL 编码，例如 `@` 写为 `%40`。
2. `/root/.codex_proxy_env` 权限必须为 `600`。
3. 修复脚本包含代理地址时，建议权限为 `700`。
4. 不要把代理环境文件、认证文件或完整日志提交到 Git。
5. 不要在开启 `set -x` 的 shell 中加载代理环境文件。
6. 如果代理密码曾出现在聊天、工单或共享终端记录中，应尽快轮换密码。

## 11. 最终状态

2026-07-10 验证结果：

- Codex Desktop 重启后成功重新建立 SSH 远程 app-server。
- 主 app-server 正确持有控制 socket。
- 主服务继承 HTTP/HTTPS 代理和 NO_PROXY。
- 模型缓存由 `0.144.1` 刷新。
- GPT-5.6 Sol、Terra、Luna 均出现在远程模型目录中。

Codex 官方文档入口：<https://developers.openai.com/codex/>
