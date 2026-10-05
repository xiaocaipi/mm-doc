# 2026-09-24 GitLab Commit 跑 Job 并更新 release.yaml 指南

## 1. 适用场景

用户（或开发）给一个 GitLab commit 地址（例如：

```text
https://gitlab.sz.sensetime.com/compass/raccoon/rag/knowledge-service/-/commit/963c404a19e9b3a645ca9b5bff3e1abc4e2de2fc
```

或直接给 commit sha）。要求：

1. 把该 commit 对应的 CI pipeline 的**全部 job 跑完**（含 manual 的 release 系列 job）；
2. 从 `release:helm` job 的日志里读取 **chart 号**（`HELM_CHART_VERSION`）；
3. 更新本地文件 `/data/caidanfeng/viper/charts/senseraccoon/release.yaml` 里 `knowledge-service` 的 `version`；
4. 更新完成后告知用户。

当前流程针对项目：`compass/raccoon/rag/knowledge-service`（project_id = **54756**，私有项目）。

## 2. 前置条件

- 本机可 `ssh root@172.20.25.104`（免密，用于取 GitLab token）。
- 本机无 `curl`/`jq`/`glab`，HTTP 请求用 `python3`（urllib）+ 关闭 SSL 校验（内网 GitLab 证书不受信任）。
- 目标仓库本地 clone 存在：`/data/caidanfeng/project/ai/agent_open/raccoon/knowledge-service`（可选，用于对照 Chart.yaml 版本）。

## 3. 获取并设置 GitLab Token

Token 不写死在本机，而是从 172.20.25.104 上已登录的 `glab` 配置里读取（该机 `glab auth login` 过 `gitlab.sz.sensetime.com`）。

### 3.1 SSH 读取 token

```bash
ssh root@172.20.25.104 'sed -n "/gitlab.sz.sensetime.com:/,/token:/p" /root/.config/glab-cli/config.yml'
```

其中 `token: xxxxx` 即 Personal Access Token（需 `read_api` 以上权限；当前所用 token 满足）。

### 3.2 导出到环境变量（不要写进命令历史/文档）

```bash
export GITLAB_TOKEN="从上面读到的 token"
```

### 3.3 用 python3 封装 API 调用

本机没有 curl，统一用 python3（注意内网证书需要关闭校验）：

```python
import urllib.request, json, ssl, os
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
HOST = "https://gitlab.sz.sensetime.com"
TOK  = os.environ["GITLAB_TOKEN"]
PID  = 54756  # compass/raccoon/rag/knowledge-service

def api(path, method="GET", data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(f"{HOST}/api/v4{path}",
                                 headers={"PRIVATE-TOKEN": TOK, "User-Agent": "curl/8"},
                                 method=method, data=body)
    with urllib.request.urlopen(req, timeout=60, context=ctx) as r:
        return json.load(r)
```

## 4. 从 commit 地址解析出 pipeline

### 4.1 解析 commit sha

从用户给的 commit URL 里取 `/-/commit/<sha>` 的 sha 部分（可能是短 sha）。

### 4.2 查询 commit 的完整信息与 latest pipeline

```python
c = api(f"/projects/{PID}/repository/commits/{sha}")
full_sha = c["id"]          # 40 位完整 sha
last_pipeline = c.get("last_pipeline")   # 可能为 None
```

### 4.3 用完整 sha 查 pipeline（短 sha 查不到，必须完整 40 位）

```python
pipes = api(f"/projects/{PID}/pipelines?sha={full_sha}&per_page=5")
# 取最新一条：pipeline_id = pipes[0]["id"], status = pipes[0]["status"]
```

> 注意：commit 必须已经 push 且触发了 pipeline（`workflow.rules` 中分支 push 会触发）。若 `pipes` 为空，说明该 commit 没有对应 pipeline（如未 push、或在被 MR 排除的分支上）。

## 5. 跑完全部 Job

pipeline 的 job 分两类：

- **自动 job**：`check`（stage: check）——push 后自动运行，无需手动触发。
- **manual job**（`when: manual`，`allow_failure: true`）：`release:cross-builder`、`release:image-amd64`、`release:image-arm64`、`release:image-manifest`、`release:helm` —— 需要逐个 `play` 触发。

### 5.1 列出 pipeline 全部 job

```python
jobs = api(f"/projects/{PID}/pipelines/{pipeline_id}/jobs?per_page=100")
for j in jobs:
    print(j["id"], j["stage"], j["name"], j["status"])
```

### 5.2 play 所有 manual 未运行的 job

对状态为 `manual` 的 job 调用 play：

```python
for j in jobs:
    if j["status"] == "manual":
        played = api(f"/projects/{PID}/jobs/{j['id']}/play", method="POST")
        print("played", played["id"], played["name"], "->", played["status"])
```

各 release job 依赖顺序：`docker_push`（cross-builder / image-amd64 / image-arm64）→ `docker_manifest`（image-manifest）→ `release`（release:helm）。GitLab 会按 stage 顺序排队；只要全部 play 即可。

> 注意：`release:*` 系列 job 的 `script` 中会 `docker login` 并用 registry 凭据（CI 变量注入），play 后由 runner 执行，不需要本机 docker。

### 5.3 轮询等待全部 job 结束

```python
import time
def wait_all(pipeline_id):
    while True:
        jobs = api(f"/projects/{PID}/pipelines/{pipeline_id}/jobs?per_page=100")
        statuses = {j["name"]: j["status"] for j in jobs}
        pending = [n for n, s in statuses.items() if s in ("pending", "running", "manual")]
        print(statuses)
        if not pending:
            return statuses
        time.sleep(30)
```

跑完的标准：所有 job 状态为 `success` / `failed`（manual 未触发但 allow_failure 时 pipeline 仍可能 success——实际流程中请确认 release:* 均已跑完并拿日志）。`check` 失败时一般应先修复代码，否则 release job 即使 play 也会失败。

## 6. 从 release:helm job 读取 chart 号

### 6.1 找到 release:helm job 并下载 trace

```python
jid = next(j["id"] for j in jobs if j["name"] == "release:helm")
req = urllib.request.Request(f"{HOST}/api/v4/projects/{PID}/jobs/{jid}/trace",
                             headers={"PRIVATE-TOKEN": TOK, "User-Agent": "curl/8"})
with urllib.request.urlopen(req, timeout=60, context=ctx) as r:
    trace = r.read().decode("utf-8", "replace")
```

### 6.2 提取 chart 号

在日志中查找：

```text
Successfully packaged chart and saved it to: dist/charts/knowledge-service-<CHART_VERSION>.tgz
```

或查找 `HELM_CHART_VERSION` 相关行。

```python
import re
m = re.search(r"knowledge-service-([0-9][\w.+-]*)\.tgz", trace)
chart_version = m.group(1)
print(chart_version)  # 例如 1.0.0-963c404a
```

**chart 号格式**：`Chart.yaml 的 version + "-" + commit 短 sha`（如 `1.0.0-963c404a`）。`Chart.yaml` 版本在仓库 `deploy/chart/Chart.yaml`（当前 `version: 1.0.0`）。

### 6.3 校验 chart 确实发布成功

日志尾部应包含：

```text
Pushing knowledge-service-<CHART_VERSION>.tgz to compass...
helm search repo ... --version <CHART_VERSION>
```

## 7. 更新本地 release.yaml

文件：`/data/caidanfeng/viper/charts/senseraccoon/release.yaml`

内容（YAML）：

```yaml
releases:
  knowledge-service:
    version: 1.0.0-963c404a
    group: raccoon
    repo: compass
```

用新的 `chart_version` 替换 `knowledge-service.version`：

```bash
cd /data/caidanfeng/viper/charts/senseraccoon
# 直接编辑 release.yaml，只改 knowledge-service 的 version 一行
```

编辑后核对：

```bash
sed -n '/knowledge-service:/,/repo:/p' /data/caidanfeng/viper/charts/senseraccoon/release.yaml
```

## 8. 完成反馈

告知用户：

- 跑过的 pipeline id 与各 job 状态；
- 新的 chart 号（如 `1.0.0-963c404a`）；
- `release.yaml` 已更新为对应 version。

## 9. 常见错误

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 401 Unauthorized | token 未设 / 过期 / 权限不够 | 重新到 172.20.25.104 读配置里的 token |
| 404 Project Not Found | 项目私有且 token 无权限，或 path 未 URL encode | 用 project_id 54756 直接访问 |
| 查询 pipeline 为空 | 用了短 sha | 用 commit API 拿完整 40 位 sha 再查 |
| play 返回 405/403 | job 不处于 manual 状态 / token 无写权限 | 检查 job 状态；token 需 `api` 权限才能 play |
| release:helm 失败 | 镜像没 push 成功、chart push 凭据缺失 | 先看同 pipeline 的 image 系列 job，再查 release:helm trace |
| release.yaml 与其他服务不同步 | 只看 knowledge-service 的 version | 单次只改 knowledge-service |

## 10. 参考

- 项目：`https://gitlab.sz.sensetime.com/compass/raccoon/rag/knowledge-service`
- CI 配置：仓库 `.gitlab-ci.yml`（stages: check / docker_push / docker_manifest / release）
- 版本推导：`build/ci/release-coordinates.sh`（branch 场景 `chart_version = Chart.yaml.version + "-" + short_sha`）
- 相关文档：`GitLab Job日志获取指南.md`（单 job trace 拉取）

## 附：一次完整执行参考（2026-09-24 已验证）

- 目标 commit：`963c404a`（`chore: bump harness dependency and use internal download URL`，main 分支最新）
- pipeline：#1372259，状态 success
- job 全量结果：check / release:image-amd64 / release:image-arm64 / release:image-manifest / release:helm 全部 success；release:cross-builder 为 manual（可跳过，本流程也可 play）
- chart 号：`1.0.0-963c404a`
- release.yaml 对应更新：`knowledge-service.version: 1.0.0-963c404a`（执行时已是该值，无需再改）