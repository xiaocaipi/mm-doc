# 2026-07-27 clotho-inference Helmfile Submit Remote Update Experience

## 目标

记录一套通用操作经验：本地改完 Helmfile values 后，如何提交到 Git，再到远端环境同步代码、重启 Helm release，并做最小验证。

适用场景:

- 修改 `senseraccoon` 中某个服务的 values。
- 修改后需要推到 `harness` 分支。
- 远端环境通过 `/data/awesome/senseraccoon` 拉取最新配置。
- 使用 `helmfile -l name=xxx destroy` 和 `helmfile -l name=xxx sync` 重启服务。

## 常用路径

本地 Helmfile 仓库:

```text
/data/caidanfeng/viper/charts/senseraccoon
```

185 远端 Helmfile 仓库:

```text
ssh root@10.111.32.185:/data/awesome/senseraccoon
```

Clotho values:

```text
/data/caidanfeng/viper/charts/senseraccoon/values/clotho-inference/values-default.yaml
```

## 本地修改后先检查

先看工作区，避免把无关改动一起提交:

```bash
cd /data/caidanfeng/viper/charts/senseraccoon
git status --short --branch
git diff
```

如果只想提交某个服务，重点确认 diff 只落在该服务目录，例如:

```text
values/clotho-inference/values-default.yaml
release.yaml
```

如果看到无关文件，先不要提交，单独确认这些改动是谁的、要不要保留。

## 本地渲染验证

提交前一定先让 Helmfile 渲染一次，确认 values 和 chart 能组合成功:

```bash
cd /data/caidanfeng/viper/charts/senseraccoon
helmfile -e dev -l name=clotho-inference-default template >/tmp/clotho-inference-template-check.yaml
```

常看几类字段:

```bash
rg -n 'image:|name: clotho|ConfigMap|origin_name|base_addr|server_type' /tmp/clotho-inference-template-check.yaml
```

如果涉及敏感字段，例如 `api_key`、token、password:

- 不要把明文贴到聊天或文档。
- 可以只检查是否存在、是否为空、是否和来源配置一致。
- 需要对比时输出 `present` / `empty` / `match` / `mismatch` 即可。

提交前再跑一次格式检查:

```bash
git diff --check
```

## 本地提交

只 stage 本次需要的文件:

```bash
cd /data/caidanfeng/viper/charts/senseraccoon
git add values/clotho-inference/values-default.yaml
```

如果同时改了 chart 版本，再加:

```bash
git add release.yaml
```

提交:

```bash
git commit -m "Update clotho inference config"
```

推送到部署使用的分支:

```bash
git push origin harness
```

推送后确认本地干净:

```bash
git status --short --branch
git log --oneline -3
```

## 远端同步前检查

先看远端有没有未提交改动:

```bash
ssh root@10.111.32.185 "cd /data/awesome/senseraccoon && git status --short --branch"
```

如果远端有未提交改动，先判断能不能丢。

可以丢弃时再执行:

```bash
ssh root@10.111.32.185 "cd /data/awesome/senseraccoon && git reset --hard && git pull --ff-only origin harness && git status --short --branch"
```

注意: `git reset --hard` 会删除远端本地未提交改动，不确认就不要执行。

如果远端改动需要保留，应先备份、提交到临时分支，或人工合并，不能直接 reset。

## 远端重启服务

按当前约定，先 destroy 再 sync:

```bash
ssh root@10.111.32.185 "cd /data/awesome/senseraccoon && helmfile -e dev -l name=clotho-inference-default destroy"
ssh root@10.111.32.185 "cd /data/awesome/senseraccoon && helmfile -e dev -l name=clotho-inference-default sync"
```

通用格式:

```bash
helmfile -e <env> -l name=<release-name> destroy
helmfile -e <env> -l name=<release-name> sync
```

## 部署后验证

确认 Helm release:

```bash
ssh root@10.111.32.185 "helm status clotho-inference-default -n default"
```

确认 Deployment rollout:

```bash
ssh root@10.111.32.185 "kubectl -n default rollout status deployment/clotho-inference-default --timeout=180s"
```

确认镜像:

```bash
ssh root@10.111.32.185 "kubectl -n default get deploy clotho-inference-default -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"
```

确认 Pod:

```bash
ssh root@10.111.32.185 "kubectl -n default get pods -l app.kubernetes.io/instance=clotho-inference-default -o wide"
```

确认 ConfigMap 摘要:

```bash
ssh root@10.111.32.185 "kubectl -n default get cm clotho-inference-default-config -o jsonpath='{.data.config\\.toml}' | grep -E '^\\s*\\[tgi_config\\.model_list\\.|origin_name\\s*=|base_addr\\s*=|server_type\\s*='"
```

确认服务 HTTP 进程已响应:

```bash
ssh root@10.111.32.185 "kubectl -n default exec deploy/clotho-inference-default -- sh -lc 'if command -v curl >/dev/null 2>&1; then curl -sS -o /dev/null -w %{http_code} --max-time 5 http://127.0.0.1:8080/metrics; elif command -v wget >/dev/null 2>&1; then wget -q --spider --timeout=5 http://127.0.0.1:8080/metrics && echo 200 || echo wget_failed; else echo no-http-client; fi'"
```

## 判断是否成功

至少满足:

- 远端 `/data/awesome/senseraccoon` 已拉到本地提交的 commit。
- `helmfile sync` 成功。
- Helm release 是 `deployed`。
- Deployment rollout 成功。
- Pod 是 `Running` 且 `READY` 为 `1/1`。
- 镜像 tag 是预期值。
- ConfigMap 关键字段是预期值。
- 服务健康探测返回正常状态码。

## 回滚经验

如果 sync 后服务异常，先保留现场:

```bash
ssh root@10.111.32.185 "kubectl -n default get pods -l app.kubernetes.io/instance=clotho-inference-default -o wide"
ssh root@10.111.32.185 "kubectl -n default describe pod -l app.kubernetes.io/instance=clotho-inference-default"
ssh root@10.111.32.185 "kubectl -n default logs deploy/clotho-inference-default --tail=200"
```

常见回滚方式:

- 回退 `senseraccoon` 到上一个可用 commit 后重新 `helmfile sync`。
- 修改 values 回到上一版配置，提交后再同步远端。
- 如果只是镜像问题，可以临时改回上一版镜像 tag，但后续仍要把 Helmfile 中的配置修正提交。

## 注意事项

- 不要把完整 ConfigMap、明文 key、token、password、敏感日志写进文档或聊天。
- 远端 reset 前必须确认未提交改动可以丢。
- 本地提交时只 stage 本次相关文件。
- `helmfile template` 通过不代表服务一定可用，部署后还要看 rollout、Pod、ConfigMap 和 HTTP 探测。
- 如果 Chart 版本也变了，先确认 Chart CI 已经成功发布，再改 `senseraccoon/release.yaml`。
