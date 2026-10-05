# Codex 远程项目代理 Wrapper 使用文档

## 1. 当前结论

当前机器的 Codex CLI 已经通过 wrapper 注入代理环境变量。

已核对状态：

- `codex` 的 PATH 入口: `/root/.local/bin/codex`
- `/root/.local/bin/codex` 是软链，指向 `/root/.nvm/versions/node/v18.20.8/bin/codex`
- `/root/.nvm/versions/node/v18.20.8/bin/codex` 是 wrapper
- wrapper 会加载 `/root/.codex_proxy_env`
- 真实 Codex CLI: `/root/.nvm/versions/node/v18.20.8/bin/codex.real`
- `codex.real` 当前是软链，指向 npm 安装目录下的 `codex.js`
- 修复脚本: `/root/bin/fix-codex-proxy-wrapper.sh` 已同步为新版逻辑
- 当前版本: `codex-cli 0.153.4`

当前 wrapper 内容形态应类似：

```bash
#!/usr/bin/env bash
# CODEX_PROXY_WRAPPER

if [ -f "/root/.codex_proxy_env" ]; then
  source "/root/.codex_proxy_env"
fi

exec "/root/.nvm/versions/node/v18.20.8/bin/codex.real" "$@"
```

当前代理环境文件 `/root/.codex_proxy_env` 包含：

```bash
export HTTP_PROXY="http://<user>:<url-encoded-password>@10.4.196.74:3128"
export HTTPS_PROXY="$HTTP_PROXY"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"
```

不要把真实代理账号、密码、token 写进文档或提交到 Git。

## 2. 背景

在远程服务器上，Codex CLI 可以通过代理环境变量访问外部模型服务：

```bash
export HTTP_PROXY="http://<user>:<url-encoded-password>@<proxy-host>:<proxy-port>"
export HTTPS_PROXY="$HTTP_PROXY"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"
```

但 Codex 桌面端连接远程项目时，远程启动的 Codex 进程不一定继承当前 SSH 终端里手动 `export` 的环境变量，因此可能出现桌面端一直“正在重新连接”的问题。

更稳的做法是给 `codex` 命令本身加一层 wrapper，让任何方式启动 `codex` 时都会先加载代理环境。

## 3. 为什么不只依赖 `config.toml`

当前机器的 `/root/.codex/config.toml` 只有：

```toml
[shell_environment_policy]
inherit = "core"
```

这个配置主要影响 Codex 启动子进程时继承哪些环境变量，例如 Codex 内部执行网络命令时是否带代理。

它不能保证 Codex 进程自己启动时连接 OpenAI 或其他模型服务的请求一定使用代理，所以仍然建议保留命令 wrapper。

## 4. 路径注意事项

不要只依赖 `which codex` 的输出。当前机器上：

```bash
type -P codex
```

会返回：

```text
/root/.local/bin/codex
```

但它是软链：

```text
/root/.local/bin/codex -> /root/.nvm/versions/node/v18.20.8/bin/codex
```

因此脚本必须使用 `readlink -f` 解析真实路径。否则默认把 `REAL_BIN` 算成 `/root/.local/bin/codex.real`，会导致 wrapper 指向不存在的真实文件。

## 5. 推荐修复脚本

把脚本保存为：

```bash
/root/bin/fix-codex-proxy-wrapper.sh
```

脚本内容：

```bash
#!/usr/bin/env bash
set -euo pipefail

# 真实代理地址不要写进项目文档或 Git。
# 用法一：PROXY_URL='http://user:urlencoded-pass@host:port' /root/bin/fix-codex-proxy-wrapper.sh
# 用法二：先维护 /root/.codex_proxy_env，脚本会从里面读取 HTTP_PROXY。
PROXY_ENV="${PROXY_ENV:-/root/.codex_proxy_env}"
NO_PROXY_LIST="${NO_PROXY_LIST:-localhost,127.0.0.1,::1}"

if [ -z "${PROXY_URL:-}" ] && [ -f "$PROXY_ENV" ]; then
  # shellcheck disable=SC1090
  source "$PROXY_ENV"
  PROXY_URL="${HTTP_PROXY:-${HTTPS_PROXY:-}}"
fi

if [ -z "${PROXY_URL:-}" ]; then
  echo "ERROR: 请先设置 PROXY_URL，或准备好 $PROXY_ENV。"
  exit 1
fi

resolve_path() {
  if resolved="$(readlink -f "$1" 2>/dev/null)" && [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
  else
    readlink -m "$1"
  fi
}

hash -r 2>/dev/null || true

CODEX_ENTRY="${CODEX_BIN:-$(type -P codex || true)}"
if [ -z "$CODEX_ENTRY" ]; then
  echo "ERROR: codex not found in PATH."
  exit 1
fi

# 当前机器的 codex PATH 入口可能是 /root/.local/bin/codex 软链。
# 必须解析真实路径，否则 REAL_BIN 可能会算错。
CODEX_BIN="$(resolve_path "$CODEX_ENTRY")"
CODEX_DIR="$(dirname "$CODEX_BIN")"
PACKAGE_BIN="$(resolve_path "${CODEX_DIR}/../lib/node_modules/@openai/codex/bin/codex.js")"
TS="$(date +%Y%m%d-%H%M%S)"

echo "Codex wrapper path: $CODEX_BIN"
echo "Proxy env path: $PROXY_ENV"

detect_real_bin() {
  if grep -q 'CODEX_PROXY_WRAPPER' "$CODEX_BIN" 2>/dev/null; then
    awk -F'"' '/^exec "/ {print $2; exit}' "$CODEX_BIN"
  fi
  return 0
}

REAL_BIN="${CODEX_REAL_BIN:-$(detect_real_bin)}"
if [ -z "$REAL_BIN" ]; then
  REAL_BIN="${CODEX_BIN}.real"
fi

ensure_real_bin() {
  if [ -f "$REAL_BIN" ] || [ -L "$REAL_BIN" ]; then
    return 0
  fi

  if [ -f "$PACKAGE_BIN" ] || [ -L "$PACKAGE_BIN" ]; then
    echo "Real codex missing; linking to package bin: $PACKAGE_BIN"
    ln -s "$PACKAGE_BIN" "$REAL_BIN"
    return 0
  fi

  echo "ERROR: real codex not found: $REAL_BIN"
  echo "ERROR: package bin not found: $PACKAGE_BIN"
  exit 1
}

if [ "${1:-}" = "--restore" ]; then
  ensure_real_bin

  if grep -q 'CODEX_PROXY_WRAPPER' "$CODEX_BIN" 2>/dev/null; then
    rm -f "$CODEX_BIN"
    mv "$REAL_BIN" "$CODEX_BIN"
    chmod +x "$CODEX_BIN"
    echo "已恢复原始 codex: $CODEX_BIN"
  else
    echo "当前 codex 不是 wrapper，无需恢复。"
  fi
  exit 0
fi

cat > "$PROXY_ENV" <<ENVEOF
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="\$HTTP_PROXY"
export http_proxy="\$HTTP_PROXY"
export https_proxy="\$HTTPS_PROXY"
export NO_PROXY="$NO_PROXY_LIST"
export no_proxy="\$NO_PROXY"
ENVEOF
chmod 600 "$PROXY_ENV"

if grep -q 'CODEX_PROXY_WRAPPER' "$CODEX_BIN" 2>/dev/null; then
  ensure_real_bin
  echo "当前 codex 已经是 wrapper，保留真实 codex: $REAL_BIN"
else
  if [ -e "$CODEX_BIN" ] || [ -L "$CODEX_BIN" ]; then
    if [ -e "$REAL_BIN" ] || [ -L "$REAL_BIN" ]; then
      echo "发现已有真实 codex，先备份: ${REAL_BIN}.bak.${TS}"
      mv "$REAL_BIN" "${REAL_BIN}.bak.${TS}"
    fi

    echo "把当前 codex 移动为真实可执行文件: $REAL_BIN"
    mv "$CODEX_BIN" "$REAL_BIN"
  else
    ensure_real_bin
  fi
fi

cat > "$CODEX_BIN" <<WRAPEOF
#!/usr/bin/env bash
# CODEX_PROXY_WRAPPER

if [ -f "$PROXY_ENV" ]; then
  source "$PROXY_ENV"
fi

exec "$REAL_BIN" "\$@"
WRAPEOF

chmod +x "$CODEX_BIN"

echo
echo "完成。当前文件："
ls -l "$CODEX_BIN" "$REAL_BIN" "$PROXY_ENV" 2>/dev/null || true
echo
echo "测试版本："
"$CODEX_BIN" --version || true
```

## 6. 安装和使用

首次安装脚本：

```bash
mkdir -p /root/bin
chmod 700 /root/bin/fix-codex-proxy-wrapper.sh
```

如果 `/root/.codex_proxy_env` 已经存在，直接执行：

```bash
/root/bin/fix-codex-proxy-wrapper.sh
```

如果是第一次配置代理，不要把真实密码写进项目文档。可以在命令行临时传入：

```bash
PROXY_URL='http://<user>:<url-encoded-password>@10.4.196.74:3128' \
  /root/bin/fix-codex-proxy-wrapper.sh
```

如果升级后 `codex` 路径变化，可以手动指定：

```bash
CODEX_BIN="$(type -P codex)" /root/bin/fix-codex-proxy-wrapper.sh
```

也可以指定解析后的固定路径：

```bash
CODEX_BIN="/root/.nvm/versions/node/v18.20.8/bin/codex" \
  /root/bin/fix-codex-proxy-wrapper.sh
```

## 7. 验证方法

查看当前入口：

```bash
type -a codex
readlink -f "$(type -P codex)"
```

查看 wrapper：

```bash
head -20 "$(readlink -f "$(type -P codex)")"
```

查看真实文件：

```bash
ls -l /root/.local/bin/codex /root/.nvm/versions/node/v18.20.8/bin/codex*
```

测试 CLI：

```bash
codex --version
codex
```

只读网络探测：

```bash
curl -L -I --max-time 10 https://api.openai.com/v1/models
```

如果看到 `HTTP/1.1 200 Connection established` 后跟随 `401`，通常说明代理链路通了，只是请求没有带 API 认证。

## 8. 桌面端仍然无法连接时

如果 Codex 桌面端远程项目仍然卡在“正在重新连接”，说明桌面端可能没有调用当前 `codex` 路径，或启动进程没有吃到代理。

查看远程机器上的 Codex 进程：

```bash
ps auxww | grep -i codex | grep -v grep
```

找到 PID 后查看环境变量：

```bash
tr '\0' '\n' < /proc/<PID>/environ | grep -i proxy
```

如果能看到：

```text
HTTP_PROXY=...
HTTPS_PROXY=...
```

说明代理已经注入成功。

如果没有输出，说明桌面端启动的 Codex 进程没有使用当前 wrapper，或者启动链路清掉了代理环境。

## 9. 恢复原状

优先使用脚本恢复：

```bash
/root/bin/fix-codex-proxy-wrapper.sh --restore
```

手动恢复前先确认真实文件路径：

```bash
readlink -f "$(type -P codex)"
ls -l /root/.nvm/versions/node/v18.20.8/bin/codex*
```

当前机器如果保持默认布局，手动恢复命令是：

```bash
rm /root/.nvm/versions/node/v18.20.8/bin/codex
mv /root/.nvm/versions/node/v18.20.8/bin/codex.real \
  /root/.nvm/versions/node/v18.20.8/bin/codex
chmod +x /root/.nvm/versions/node/v18.20.8/bin/codex
```

不要在没有确认 `codex.real` 存在时执行手动恢复。

## 10. 注意事项

- 不要把真实代理账号、密码、token 写进文档或提交到 Git。
- `/root/.codex_proxy_env` 权限应保持 `600`。
- 修复脚本建议放在 `/root/bin` 或当前用户私有目录。
- 当前机器的 `codex` PATH 入口是软链，脚本必须解析真实路径。
- 每次 Codex CLI 升级后建议重新执行一次脚本。
- 当前 `/root/bin/fix-codex-proxy-wrapper.sh` 已按本文件的新版逻辑同步；如果以后被覆盖，使用前再按本文件替换。
