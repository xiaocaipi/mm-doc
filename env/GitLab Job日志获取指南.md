# GitLab Job 日志获取指南

## 1. 适用场景

别人发来一个 GitLab CI Job 链接，想在命令行里获取对应日志，便于排查构建、测试、镜像发布失败原因。

常见 Job 链接形态：

```text
https://gitlab.sz.sensetime.com/group/subgroup/project/-/jobs/123456
```

其中：

```text
GitLab 地址 = https://gitlab.sz.sensetime.com
项目路径    = group/subgroup/project
job_id      = 123456
```

## 2. 最快方式：浏览器查看

直接打开 Job 链接：

```text
https://gitlab.sz.sensetime.com/group/subgroup/project/-/jobs/123456
```

页面中间就是 job trace。适合人工快速看失败位置。

如果日志很长，建议用 API 拉原始日志，方便 `grep` / 保存 / 发给别人。

## 3. API 获取原始 Job 日志

GitLab API：

```text
GET /api/v4/projects/:project_id/jobs/:job_id/trace
```

推荐先用项目路径查询 `project_id`，再用 `job_id` 获取 trace。

### 3.1 准备变量

不要把 token 写进命令历史，建议放环境变量：

```bash
export GITLAB_HOST="https://gitlab.sz.sensetime.com"
export GITLAB_TOKEN="你的 GitLab Personal Access Token"
export PROJECT_PATH="group/subgroup/project"
export JOB_ID="123456"
```

Token 至少需要能读该项目 CI Job 的权限。通常 `read_api` 或等价权限即可，具体以 GitLab 实例配置为准。

### 3.2 查询 project_id

项目路径里的 `/` 需要 URL encode 成 `%2F`。

```bash
PROJECT_ENCODED=$(python3 - <<'PY'
import os
import urllib.parse
print(urllib.parse.quote(os.environ["PROJECT_PATH"], safe=""))
PY
)

PROJECT_ID=$(curl -sS \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_HOST}/api/v4/projects/${PROJECT_ENCODED}" \
  | jq -r '.id')

echo "${PROJECT_ID}"
```

如果没有 `jq`，可以先直接看返回：

```bash
curl -sS \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_HOST}/api/v4/projects/${PROJECT_ENCODED}"
```

### 3.3 获取 job trace

```bash
curl -sS \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_HOST}/api/v4/projects/${PROJECT_ID}/jobs/${JOB_ID}/trace" \
  -o "gitlab-job-${JOB_ID}.log"
```

查看最后 200 行：

```bash
tail -n 200 "gitlab-job-${JOB_ID}.log"
```

搜索错误：

```bash
grep -nEi "error|failed|panic|exception|timeout|denied|not found" "gitlab-job-${JOB_ID}.log"
```

## 4. 一条命令版

已经知道 `PROJECT_PATH` 和 `JOB_ID` 时：

```bash
GITLAB_HOST="https://gitlab.sz.sensetime.com" \
PROJECT_PATH="group/subgroup/project" \
JOB_ID="123456" \
bash -lc '
set -euo pipefail
: "${GITLAB_TOKEN:?set GITLAB_TOKEN first}"
PROJECT_ENCODED=$(python3 - <<PY
import os, urllib.parse
print(urllib.parse.quote(os.environ["PROJECT_PATH"], safe=""))
PY
)
PROJECT_ID=$(curl -sS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_HOST}/api/v4/projects/${PROJECT_ENCODED}" | jq -r ".id")
curl -sS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_HOST}/api/v4/projects/${PROJECT_ID}/jobs/${JOB_ID}/trace" \
  -o "gitlab-job-${JOB_ID}.log"
echo "saved: gitlab-job-${JOB_ID}.log"
tail -n 80 "gitlab-job-${JOB_ID}.log"
'
```

使用前先执行：

```bash
export GITLAB_TOKEN="你的 token"
```

## 5. 如果只有 Pipeline 链接

Pipeline 链接通常长这样：

```text
https://gitlab.sz.sensetime.com/group/subgroup/project/-/pipelines/987654
```

这时先查这个 pipeline 下有哪些 jobs：

```bash
export PIPELINE_ID="987654"

curl -sS \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_HOST}/api/v4/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID}/jobs" \
  | jq -r '.[] | [.id, .name, .status, .stage] | @tsv'
```

找到失败的 `job_id` 后，再按第 3.3 节获取 trace。

## 6. CI 内部获取当前 Job 日志

如果是在 GitLab CI Job 里面调用 API，可以优先尝试 `CI_JOB_TOKEN`：

```bash
curl -sS \
  --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
  "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/jobs/${CI_JOB_ID}/trace" \
  -o "current-job.log"
```

注意：不同 GitLab 实例对 `CI_JOB_TOKEN` 访问 API 的范围限制可能不同。如果返回 401/403，改用 Personal Access Token 或 Project Access Token。

## 7. 本机 glab 已登录时的 token 位置

当前机器如果已经用 `glab auth login` 登录过 GitLab，token 通常保存在：

```text
/root/.config/glab-cli/config.yml
```

可以查看 GitLab 登录状态：

```bash
glab auth status
```

查看配置文件：

```bash
sed -n '/gitlab.sz.sensetime.com:/,/^[^ ]/p' /root/.config/glab-cli/config.yml
```

或者直接搜索 token 字段：

```bash
grep -n "token" /root/.config/glab-cli/config.yml
```

配置结构通常类似：

```yaml
hosts:
  gitlab.sz.sensetime.com:
    token: xxxxx
    api_host: gitlab.sz.sensetime.com
    git_protocol: ssh
```

如果脚本要求 `GITLAB_TOKEN`，可以临时导出：

```bash
export GITLAB_TOKEN="从 /root/.config/glab-cli/config.yml 里看到的 token"
```

注意：

- 不要把真实 token 写进项目文档。
- 不要把包含 token 的文件提交到 git。
- 发日志给别人前先确认没有把 token、密码、registry 凭据贴出去。

## 8. 常见错误

### 8.1 401 Unauthorized

可能原因：

- token 没传；
- token 过期；
- token 权限不够；
- 使用了错误的 header，比如把 `PRIVATE-TOKEN` 写成了别的名字。

### 8.2 403 Forbidden

可能原因：

- 当前账号无项目权限；
- token 没有 API 读取权限；
- `CI_JOB_TOKEN` 被 GitLab 限制不能读目标项目。

### 8.3 404 Not Found

可能原因：

- `PROJECT_PATH` 没有 URL encode；
- `JOB_ID` 写错；
- job 不属于这个项目；
- 项目是私有的，但 token 没权限。

### 8.4 日志被截断

GitLab 页面可能只适合人工查看，长日志建议用 trace API 下载：

```bash
curl -sS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_HOST}/api/v4/projects/${PROJECT_ID}/jobs/${JOB_ID}/trace" \
  -o full.log
```

## 9. 给 Codex/Claude 排查时怎么发

推荐发：

```text
GitLab Job URL:
https://gitlab.sz.sensetime.com/group/subgroup/project/-/jobs/123456

失败现象:
例如 build image failed / go test failed / helm deploy failed

重点日志:
贴 tail -n 200 gitlab-job-123456.log
```

如果日志里有 token、密码、registry 凭据、内网账号等敏感信息，先脱敏再发。
