# 2026-09-16 Cognitivesvc 函数注释编写规范

本规范定义"给单个函数（Java 方法）补充业务注释"的通用做法：方法上方 javadoc 写什么、方法体内变量和关键逻辑怎么加例子、示例数据用什么格式、如何验证。与模块无关，适用于 `cognitivesvc-kestrel` 各模块的普通方法、调度方法、工具方法。

与既有文档的分工：

- [代码逻辑文档生成方法参考](/data/caidanfeng/project/doc/mm-doc/env/2026-09-16-代码逻辑文档生成方法参考.md)：整套"文档 + 源码注释"方法论，本文是其"源码注释"部分的实操细化。
- [模型调度文档写作规范](/data/caidanfeng/project/sessions/claude/s600_studio/s603_cog/doc/spec/2026-09-15-模型调度文档写作规范.md)：模型调度系列文档的写作标准，重点是 Markdown 文档；本文不绑定任何专题。

## 1. 适用场景与目标

适合以下动作：用户要求"给某方法加例子/加注释"、补写文档对应方法的源码注释、排查后把结论落到方法旁。

一次注释交付要满足三条：

1. **契约可读**：方法上方说明输入代表什么、返回和副作用是什么、异常怎么传播，读者不必跳到别处猜。
2. **例子可触发**：方法体内用具体值解释关键变量和分支，例子必须是该分支真实可触达的输入，标明是假设。
3. **行为零改动**：只加注释，不改条件、不重命名、不移动语句、不改变返回。

## 2. 方法注释（javadoc）怎么写

### 2.1 模板

```java
/**
 * <一句话说明本方法负责什么，输入输出和边界一次讲清>。
 * <第二行起补充重要边界：修改了谁、什么情况下复用旧数据、哪些动作不在本方法内发生>。
 *
 * 当前示例状态：<一句话点明对象、轮次、关键值；有贯穿示例时与文档示例保持一致>。
 * 输入示例：<参数或成员依赖的代表性取值；无显式参数写"无显式参数">。
 * 输出及副作用：<真实返回类型的结果示例；void 写"无返回值"并说明副作用>。
 *
 * @param <参数名> <参数的业务含义，不是字面翻译>
 * @return <返回值的业务含义；无返回值不写 @return>
 */
```

要点：

- **首行是职责**，不是方法名翻译。`处理数据`、`执行调度`、`返回结果` 都不算有效说明。
- **边界单独成句**：例如"查询异常可能复用旧对象""集合不可修改但内部对象可被预测改动""HTTP 只受理不等待加载"。
- **示例写在 javadoc 内**，用 `当前示例状态 / 输入示例 / 输出及副作用` 三个标签；这不是必须的栏目名，但同一项目内保持一致，便于检索。
- 复杂方法的示例可以超过一行，用连续 `*` 行列出多条取值。

### 2.2 当前示例状态

一句话交代"这次讲解用的是哪份数据"，例如：

```java
 * 当前示例状态：R2 第 1 轮，两台 GPU Worker 查询成功，均无动态模型、GPU 使用率为 0。
```

- 有贯穿示例的项目（如模型调度系列的 R2）必须与文档示例数值一致，不许悄悄改数。
- 没有贯穿示例时，自造一个最小可理解场景，并说明是模拟假设。

### 2.3 输入示例

显式参数给具体取值；成员依赖（仓储、Holder、注册发现）单独说明来源，不假装是形参：

```java
 * 输入示例：isMaster=true；注册发现返回 XWorker 实例 W1、W2，query 接口返回：
 *   W1 -> QueryWorkerResult{identity="GPU-A", availableGpuMemory=16000, avgGpuRate=0, dynamicModels=[]}
 *   W2 -> QueryWorkerResult{identity="GPU-B", availableGpuMemory=16000, avgGpuRate=0, dynamicModels=[]}
```

- 只列相关字段，不贴整份大对象。
- `null`、空集合等特殊输入要写出来，例如"json 为 null 或空数组时返回空列表"。

### 2.4 输出及副作用

必须区分三件事：**返回值**、**副作用**（改了哪个成员/环境/数据库）、**没发生什么**（例如"不发送 HTTP""不等待加载完成"）。

```java
 * 输出及副作用：无返回值，holder 重建为本轮新视图，关键字段示例：
 *   instanceIdMap = { W1 -> (W1实例, W1快照), W2 -> (W2实例, W2快照) }
 *   identityMap   = { GPU-A -> "0", GPU-B -> "1" }
 *   scoreMap      = { W1 -> 100.0, W2 -> 100.0 }
 * 外层集合不可修改，但内部 QueryWorkerResult 可被后续 GPU 预测原地改变。
```

- void 方法写"无返回值"，不用 null 冒充，也不造 `{"hasReturnValue": false}` 这种 Java 里不存在的结构（那是文档专用标记）。
- 有返回值但业务语义特殊时，说明 true/false 分别意味着什么，例如"true 表示目标发生变化，false 不表示需求已满足"。

### 2.5 异常与异步边界

方法会抛异常、吞异常、异步返回、定时触发时，javadoc 里必须写明：

| 情况 | 写法示例 |
| --- | --- |
| 异常向上传播 | `初始化异常会向外传播，已注册的 BeanDefinition 不在此撤销` |
| 异常被吞掉 | `解析异常只记日志，不向调用方抛出，返回空列表` |
| 失败可复用旧数据 | `查询失败时可能复用上轮实例对象，不能把每次调用都当成全新实测` |
| 异步/定时执行 | `由 fixedDelay=2000 的独立定时方法调用，不阻塞 HTTP 请求线程` |
| 受理不等于完成 | `本方法只记录目标并返回成功，模型加载在后续心跳中执行` |

## 3. 方法体内变量与逻辑注释

### 3.1 变量注释：`// 例：...` + 具体 JSON 值

在关键变量构建处，用一行内联注释给出"这个变量此时是什么值、为什么是这个值"。**例子必须给具体的 JSON 值**，不是文字描述或伪对象语法。推荐格式，**例子放在变量声明上方、业务说明注释（`/** ... */`）之后**：

```java
/** 构建GPU身份映射，用于识别GPU资源 */
// 例：R2 得到 {"GPU-A":"0","GPU-B":"1"}，即 identity -> gpuId；独占身份、required/preferred 都按此映射匹配 Worker。
Map<String, String> identityMap = instanceWorkerList.stream()...;
```

规则：

- **值必须是 JSON**：键和字符串加引号、数字不带引号、数组用 `[]`、对象用 `{}`、null 写 `null`。反例：`{ demoFace -> [W1, W2] }`、`[(W1, W1快照)]`、`QueryWorkerResult{identity="GPU-A"}` 都不是合法 JSON。
- **JSON 长时拆多行**：每个 `//` 行续写一段，缩进用 3 空格对齐，最后一行再接用途说明。
- **只列相关字段**：复杂对象给代表性字段，注明"仅列相关字段"或用 `...` 省略中间字段（如 `{"instanceId":"W1","identity":"GPU-A",...}`）。
- **例子要具体**：有真实键值，不用"存了 GPU 信息"这种空话。
- **两种情况都展示有值的 JSON**：用"情况 1 / 情况 2"分行列出两种**都有具体取值**的场景（如单条 vs 多条、一种来源 vs 两种来源、全部命中 vs 部分剔除），不把空值（`[]`/`{}`/`null`）单独当一个例子；空值行为如需交代，用一句话带过（如"无记录时为空列表"），不作为例子的取值主体。
- **一行讲一个点**：值是什么 + 谁消费它。超过两件事就拆两行。
- **放在变量声明上方**，紧跟业务说明注释之后；读者先读注释再读变量，不需要在长构建语句（尤其 stream 链）之后往回找。
- 变量构建完成后需要额外解释的中间过程（如循环里如何累加），才在该逻辑旁补第二处注释。
- 与 javadoc 的贯穿示例一致：javadoc 说 W1 是 GPU-A，内联例子也写 GPU-A。

示例（多行 JSON 写法）：

```java
/** 获取所有XWorker实例并查询其状态信息 */
// 例：两种取值情况——
//   情况 1（假设仅 W1 一台查询成功）：
//     [{"instanceId":"W1","identity":"GPU-A","gpuId":"0","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]}]
//   情况 2（R2：W1、W2 均查询成功）：
//     [{"instanceId":"W1","identity":"GPU-A","gpuId":"0","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]},
//      {"instanceId":"W2","identity":"GPU-B","gpuId":"1","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]}]，
//   ERROR 实例不会出现在这里，查询失败时复用上轮快照。
List<Pair<ServiceInstance, QueryWorkerResult>> instanceWorkerList = instances.parallelStream()...;
```

### 3.2 逻辑注释：解释"为什么"，不翻译语法

| 代码 | 注释要回答 | 反例 |
| --- | --- | --- |
| 条件判断 | 这个条件在业务上指什么，成立/不成立走哪条路 | `如果 num > env.getLeft() 就更新最大值` |
| 循环/筛选 | 遍历什么、怎么选、迭代间是否共享修改 | `遍历 instanceWorkerList` |
| 集合更新 | 改哪个对象、立即改还是收集后改、谁继续用 | `把 model 放进 map` |
| 提前返回 | 此时已完成了什么、哪些动作不再执行 | `条件不满足就返回` |
| 调用其他方法 | 为什么现在调它、参数哪来的、结果怎么影响流程 | `调用 score 方法` |

主例没走的分支，在分支旁补一个可触发的小例子，例如：

```java
// 身份在当前快照中可见就清零；例如旧计数为 2，恢复后再缺失从 1 开始。
```

### 3.3 注释里的例子必须是"假设"

所有模拟值、假定依赖返回、独立触发场景，注释里要能看出是假设，不能写成系统固定规则：

- 可以写"例如旧计数为 2"、"本例假定估算显存 2000"。
- 不能写"系统规定 3 轮才清理"（实际可能是按模型计数累加）、"一定保留 GPU-A"（实际可能受遍历顺序影响）。
- 不确定的业务动机写"待确认"，不写成定论。

### 3.4 涉表代码：注释写明表名

方法或语句读写数据库表时，注释必须点明具体表名，便于排查与对表。

- 写入用「写表 <table>」，读取用「读表 <table>」；跨表事务把涉及的表都写明。
- 表名以 ORM 的 `TableName()`/实体映射为准，不凭记忆写（如 `Conversation -> conversations`、`Message -> messages`）。
- 行取值例子仍按 §3.1 给合法 JSON，字段名用真实列名。
- 纯内存计算、无表读写的方法不必标表。

示例（以 Go 落地的真实写法为例，Java 的 MyBatis/JPA 映射遵循同样约定）：

```go
	// 根分支行写入表 conversation_branches；固定命名 "main"，是会话后续聊天的默认挂载点。
	// 例：{"id":"branch-demo","conversation_id":"conv-demo","name":"main","parent_branch_id":"","status":"active"}
	return store.NewBranchRepo(tx).Create(ctx, &store.ConversationBranch{
		ID:             rootBranchID,
		ConversationID: conversationID,
		Name:           "main",
		Status:         store.BranchStatusActive,
	})
```

### 3.5 复杂方法：开头注释画"一图看懂"流程图（推荐，简单方法可不画）

分支多、步骤长（两条以上分支，或五个以上步骤）的方法，在方法开头注释（javadoc / 开头注释）里加一段"一图看懂"ASCII 流程图，让读者先看画面、再看细节：

- **纵向主干**：`输入 → ① 阶段 → ② 阶段 → … → 输出`，流向用 `│` / `▼` 表示。
- **分支用 `├─` / `└─` 缩进树**，与主干同列对齐；**每档出口写明"结果是什么"**（如 `→ compose free sidecar`、`→ bind_missing 标记`），不写"进入分支"这种空话。
- 流程图里的编号（① ② ③）、页 ID、数值与下文"当前示例状态 / 输入示例"**用同一套**，不许悄悄换数。
- **简单方法（两三步、无分支）不画**，避免为画而画；流程图是导读不是细节清单，细节仍由正文 `// 例：` JSON 例子承担。

示例（节选自 ppt-compose `_write_page_inputs` 的开头注释）：

```python
    写单流程（一图看懂）：

      deck / pages / skeleton_by_page / need
        │
        ▼
        ① 准备：读 visual_spec / brief → palette、template_mode、总页数
        │
        ▼
        ② 逐页写单（只处理 need 里的页）
        ├─ template 模式：解析模板绑定 → 组装 v4 模板 sidecar
        │     ├─ style_fill：物化填充 HTML 内联
        │     └─ style_rewrite：rewrite_brief → style_spec → lint
        └─ free 模式：body 页按拓扑情况分三种
              ├─ 已绑拓扑 + hydrate → compose free sidecar
              ├─ 缺拓扑 → bind_missing 标记
              └─ 普通 free 页 → skeleton 路线
        │
        ▼
        ③ 落盘：写 htmls/<page_id>.input.json，返回 meta
```

## 4. 示例数据规范

1. **一律用合法 JSON**：变量例子、javadoc 输入输出示例都用 JSON 对象/数组/标量表达；键加引号、字符串加引号、数字布尔 null 不带引号。不用 `A -> B`、`Map{...}`、`Class{field=value}` 等伪对象语法。
2. **字段名用真实代码字段**：`availableGpuMemory`、`avgGpuRate`、`dynamicModels`，不另造同义字段。
3. **类型保持真实**：字符串带引号、数字不带、布尔写 `true/false`、null 写 `null`（不写 `"null"`）。
4. **只列相关字段**：说明需要哪些列哪些，复杂对象可省略次要字段；省略处用 `...` 并在注释里说明，例如 `{"instanceId":"W1","identity":"GPU-A",...}`。
5. **标明来源**：`{"before": 16000, "after": 14000}` 这种变化增量要写明"这是说明用的状态增量，不是方法返回对象"。
6. **敏感信息不进注释**：不写密码、license、完整环境变量。
7. **示例与实现一致**：注释里写的分值、映射、目标必须能由代码推出来（例如两台 Worker 显存 16000、使用率 0、模型数 0，评分就是 100.0）。

## 5. 完整样例

以下是对 `refresh(boolean isMaster)`（`cognitivesvc-xswitcher` 的 `XModelWatcher`）实际落地的注释，作为"方法注释 + 内联例子"组合的示范：

```java
/**
 * 从注册发现、实例查询和数据库构建本轮 Holder；仅刷新快照，不触发模型调度。
 * 查询失败时可能复用上轮实例对象，无法回退时使用 ERROR；成功查询并未在此清零历史错误计数。
 * Holder 的集合不可修改，但 QueryWorkerResult 仍是共享可变对象，GPU 预测会修改其中的显存和模型列表。
 *
 * 当前示例状态：R2 第 1 轮，两台 GPU Worker 查询成功，均无动态模型、GPU 使用率为 0，无 GPU Switcher 身份占用。
 * 输入示例：isMaster=true；注册发现返回 XWorker 实例 W1、W2，query 接口返回的 Worker 快照为：
 *   W1 -> {"identity":"GPU-A","gpuId":"0","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]}
 *   W2 -> {"identity":"GPU-B","gpuId":"1","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]}
 * 输出及副作用：无返回值，holder 重建为本轮新视图，关键字段示例：
 *   instanceIdMap = {"W1":{"identity":"GPU-A","availableGpuMemory":16000,"dynamicModels":[]},"W2":{"identity":"GPU-B","availableGpuMemory":16000,"dynamicModels":[]}}
 *   identityMap   = {"GPU-A":"0","GPU-B":"1"}
 *   scoreMap      = {"W1":100.0,"W2":100.0}
 *   avgGpuMap     = {"W1":0,"W2":0}
 *   instanceSwitcherList、annotatorModelMap、modelDynamicInstanceMap、annotatorMap 等的取值见方法体内"两种取值情况"例子
 * 外层集合不可修改，但内部 QueryWorkerResult 可被 GPU 预测原地改变；查询异常可能复用旧对象，
 * 不能把每次 refresh 都理解成全新实测。
 * @param isMaster 传给 Worker 查询接口的主节点标志，不是本方法的执行门禁
 */
public synchronized void refresh(boolean isMaster) {
```

方法体内示例（摘录）：例子统一放在变量声明上方、业务说明注释之后，值为合法 JSON：

```java
/** 获取所有XSwitcher实例并过滤健康状态 */
// 例：两种取值情况——
//   情况 1（仅 S1 一个 XSwitcher 占用 GPU-A）：
//     [{"instanceId":"S1","incharge":true,"identity":"GPU-A","gpuId":"0","lowRateDevices":[]}]
//   情况 2（S1、S2 两个 XSwitcher 分别占用 GPU-A、GPU-C）：
//     [{"instanceId":"S1","incharge":true,"identity":"GPU-A","gpuId":"0","lowRateDevices":[]},
//      {"instanceId":"S2","incharge":false,"identity":"GPU-C","gpuId":"2","lowRateDevices":[]}]
// 列表供独占组避让读取（identity 即该 XSwitcher 占用的 GPU 身份）。
List<Pair<ServiceInstance, QuerySwitcherResult>> instanceSwitcherList = discoveryClient.getServices()...;

/** 获取所有XWorker实例并查询其状态信息 */
// 例：两种取值情况——
//   情况 1（假设仅 W1 一台查询成功）：
//     [{"instanceId":"W1","identity":"GPU-A","gpuId":"0","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]}]
//   情况 2（R2：W1、W2 均查询成功）：
//     [{"instanceId":"W1","identity":"GPU-A","gpuId":"0","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]},
//      {"instanceId":"W2","identity":"GPU-B","gpuId":"1","availableGpuMemory":16000,"avgGpuRate":0,"dynamicModels":[]}]，
//   ERROR 实例不会出现在这里，查询失败时复用上轮快照。
List<Pair<ServiceInstance, QueryWorkerResult>> instanceWorkerList = instances.parallelStream()...;

/** 构建注解器模型映射，用于快速查找模型信息 */
// 例：两种取值情况——
//   情况 1（W1 快照含 running 的 demoFace）：{"demoFace":{"annotatorName":"demoFace","status":"running"}}
//   情况 2（W1 快照含 demoFace 和 faceRec）：{"demoFace":{"annotatorName":"demoFace","status":"running"},"faceRec":{"annotatorName":"faceRec","status":"running"}}
// 同名后写覆盖先写。
Map<String, Model> annotatorModelMap = new HashMap<String, Model>();

/** 计算每个GPU实例的评分，用于负载均衡决策 */
// 例：两种取值情况——
//   情况 1（R2：两台 GPU 使用率 0、可用显存 16000、模型数 0）：{"W1":100.0,"W2":100.0}
//   情况 2（假设 W2 的 avgGpuRate 升到 95）：{"W1":100.0,"W2":50.0}
// ERROR 实例评分为 -1 且不进入此 Map。
Map<ServiceInstance, Double> scoreMap = instanceAvailableModelList.stream()...;

/** 构建GPU身份映射，用于识别GPU资源 */
// 例：两种取值情况——
//   情况 1（仅 W1 一台 GPU Worker）：{"GPU-A":"0"}
//   情况 2（R2：W1、W2 两台 GPU Worker）：{"GPU-A":"0","GPU-B":"1"}
// 即 identity -> gpuId；独占身份、required/preferred 都按此映射匹配 Worker。
Map<String, String> identityMap = instanceWorkerList.stream()...;
```

## 6. 验证与交付

1. **只改注释**：提交前 `git diff` 逐行核对，新增必须是注释行，无逻辑变化；保留原有缩进与换行风格。
2. **注释定界符**：确认 `/* */`、`//` 没有破坏源码结构（尤其 javadoc 内嵌 `*/` 或代码块反引号）。
3. **语法检查可选**：环境允许时用模块 `javac`/`mvn` 验证；离线缺依赖导致编译失败时，只要确认错误全部是 `cannot find symbol` 类、无语法类错误，即可说明注释未破坏源码，并在交付里说明"未执行完整编译"。
4. **与文档核对**：若项目有对应链路文档，注释示例与文档贯穿示例数值一致；源码改动后行号变化需同步文档入口。
5. **交付说明**：列出改动文件、方法、添加的注释位置、验证结果、未完成或待确认项。不因写注释重启服务、部署或改数据。

## 7. 检查清单

- [ ] 方法上方 javadoc 首行是业务职责，不是方法名翻译
- [ ] 输入示例有真实字段取值，成员依赖单独说明来源
- [ ] 输出与副作用分开写，void 方法写了副作用而非假返回
- [ ] 异常/异步/复用旧数据等边界在 javadoc 里写明
- [ ] 方法体内关键变量有 `// 例：...` 内联例子，值为合法 JSON（键和字符串加引号，不用 `A -> B` 伪对象语法）
- [ ] 变量例子放在声明上方、业务说明注释之后（长构建语句不需要在下方往回找）
- [ ] 条件、循环、提前返回处解释"为什么"，不是翻译语法
- [ ] 所有模拟值标明是假设，没把示例写成固定规则
- [ ] 复杂方法开头注释有"一图看懂"流程图导读，简单方法不画（§3.5）
- [ ] 示例字段名、类型与真实代码一致，无敏感信息
- [ ] 与链路文档的贯穿示例数值一致
- [ ] `git diff` 确认只加注释，无行为改动
- [ ] 注释定界符未破坏源码；编译/语法验证结果如实交代

## 8. 参考文档

- [代码逻辑文档生成方法参考](/data/caidanfeng/project/doc/mm-doc/env/2026-09-16-代码逻辑文档生成方法参考.md)
- [模型调度文档写作规范](/data/caidanfeng/project/sessions/claude/s600_studio/s603_cog/doc/spec/2026-09-15-模型调度文档写作规范.md)
- [模型调度代码逻辑说明](/data/caidanfeng/project/sessions/claude/s600_studio/s603_cog/doc/architecture/调度/模型调度/2026-09-16-cognitivesvc-模型调度-代码逻辑说明.md)
