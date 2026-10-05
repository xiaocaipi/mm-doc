# AGENTS.md 参考模板

## 使用说明

- 本文件是给 Codex、Claude 或其他 agent 使用的项目工作引导模板。
- 复制到具体项目地址后，先把 `<...>` 占位符替换为真实信息。
- 明确区分代码地址和项目地址：代码地址放源码；项目地址放会话文档、引导文件和沉淀材料。
- 没有实际确认的信息不要编造；环境、namespace、ConfigMap、启动参数必须来自用户提供或只读查询结果。

## 基本信息

- **项目/服务名**: `<project-or-service-name>`
- **代码地址**: `<source-code-path>`
- **项目地址**: `<session-or-doc-project-path>`
- **服务前缀**: `<service-prefix>`
- **Git 地址**: `<git-url>`
- **Helmfile / Chart 地址**: `<helmfile-or-chart-path>`
- **运行环境**:
  - 本地: `<local-env-or-empty>`
  - 开发: `<dev-env-or-empty>`
  - 测试: `<test-env-or-empty>`
  - 历史参考: `<legacy-env-or-empty>`
- **Kubernetes namespace**: `<confirmed-namespace-or-empty>`
- **相关服务**: `<related-services>`
- **子模块**: `<submodules-or-empty>`

## 工作边界

- 当前项目只处理 `<service-name>` 相关工作，不要和其他服务混为一个模块。
- 当前服务负责：`<write-core-responsibilities>`。
- 当前服务不负责：`<write-out-of-scope-items>`。
- 源码以代码地址为准；项目地址只放 `CLAUDE.md`、`AGENTS.md`、`docs/`、session 总结和问题记录。
- 修改代码前先确认代码目录是否是 Git 仓库，再查看工作区状态，避免覆盖他人改动。
- 不要把本地调试配置、token、密码、Redis/MinIO/数据库凭据提交到仓库或贴到回复里。

## 代码入口

优先列出 3 到 8 个最关键入口：

- HTTP/RPC/API 入口: `<path>`
- Worker / 任务入口: `<path>`
- 核心调度 / 主流程: `<path>`
- 配置加载: `<path>`
- 部署配置: `<path>`
- 本地启动配置: `<path>`
- 测试入口: `<path>`

## 项目文档模块

项目文档默认放在：

```text
<session-or-doc-project-path>/docs
```

文档目录约定：

| 目录 | 用途 |
| --- | --- |
| `docs/spec/` | 需求 spec、设计 spec、实施计划 |
| `docs/architecture/` | 架构说明、部署架构、组件关系、流程图 |
| `docs/session-summary/` | 阶段性 session 总结、交接记录、决策回顾 |
| `docs/bugs/` | bug 分析、问题复盘、修复记录、验证记录 |

命名和标题格式：

```text
YYYY-MM-DD-<topic>-<doc-type>.md
```

```markdown
# YYYY-MM-DD <service/topic> <Doc Type>
```

文档语言约定：

- 新增 Markdown 文档尽量使用中文。
- 文件名、代码符号、配置键、命令、日志原文按实际内容保留。
- spec、架构、session 总结、bug 文档默认放项目地址的 `docs/` 下，不放源码目录。

## 服务形态

用简短列表描述服务组成，不写长篇架构分析：

- API: `<api-service-name-and-purpose>`
- Worker / Job: `<worker-name-and-purpose>`
- Queue / Broker: `<queue-or-broker>`
- 存储: `<database-object-storage-cache>`
- 外部依赖: `<external-services>`
- 部署方式: `<docker-compose-helm-k8s-or-other>`

## 常用命令

基础检查：

```bash
cd <source-code-path>
git status --short --branch
git diff
```

本地启动：

```bash
cd <source-code-path>
<local-start-command>
```

测试和验证：

```bash
cd <source-code-path>
<test-command>
<api-or-smoke-test-command>
```

停止本地服务：

```bash
cd <source-code-path>
<local-stop-command>
```

## 构建和镜像

稳定构建入口：

- Dockerfile: `<dockerfile-path>`
- Compose: `<compose-file-path>`
- 构建脚本: `<build-script-path>`
- Helmfile / Chart: `<helmfile-or-chart-path>`

构建命令：

```bash
cd <source-code-path>
<build-command>
```

镜像 tar、临时 tag、一次性临时编号容易过期，只有在用户明确要求或项目已有记录时再写。

## 远端环境

远端环境只做只读查询。不要删除资源、重启服务、扩缩容、发布、写 ConfigMap 或修改 Secret，除非用户明确要求。

发现资源时优先使用服务前缀：

```bash
ssh <env> "kubectl get deploy,sts,ds,svc,cm -A | grep -i '<service-prefix>'"
```

如果已确认 namespace，可以写成：

```bash
ssh <env> "kubectl get deploy,sts,ds,svc,cm -n <namespace> | grep -i '<service-prefix>'"
```

已知资源只记录少量名称：

- Namespace: `<namespace>`
- Workload: `<deployment-statefulset-daemonset>`
- Service: `<service-name>`
- ConfigMap: `<configmap-name>`
- Secret: `<secret-name-if-safe-to-name>`

不要在文档中展开完整 YAML、完整环境变量、完整 ConfigMap、完整启动参数。

## 修改前检查清单

- 确认用户目标：是改代码、查问题、写文档、部署排障，还是只读分析。
- 确认代码地址和项目地址没有混用。
- 在代码地址查看 Git 状态，识别已有改动是否来自用户。
- 优先阅读入口文件、配置文件、测试和部署文件，再动手修改。
- 修改后按风险运行最小必要验证；不能验证时说明原因和剩余风险。

## 禁止事项

- 不要执行 `git reset --hard`、删除文件、删除资源等破坏性操作，除非用户明确要求。
- 不要重启、扩缩容、发布、写 ConfigMap、修改 Secret，除非用户明确要求。
- 不要假设 namespace；namespace 只能来自用户明确提供或实际查询结果。
- 不要泄露 token、密码、密钥、完整环境变量、完整 ConfigMap 内容。
- 不要把其他项目的服务名、仓库名、路径、项目编号、镜像名复制到当前项目文档。
- 不要把项目地址当代码地址；代码改动应发生在代码地址。

## 禁止事项 很重要
- 禁止重启docker 服务
